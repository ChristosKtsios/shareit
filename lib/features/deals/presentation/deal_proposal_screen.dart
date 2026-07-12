import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/safety_tips.dart';
import '../../../core/services/error_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/data/chat_repository.dart';
import '../data/deal_model.dart';
import '../providers/deal_provider.dart';

class DealProposalScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String listingId;
  final String listingTitle;
  final String otherUserUid;
  final String? existingDealId;

  const DealProposalScreen({
    super.key,
    required this.chatId,
    required this.listingId,
    required this.listingTitle,
    required this.otherUserUid,
    this.existingDealId,
  });

  @override
  ConsumerState<DealProposalScreen> createState() => _DealProposalScreenState();
}

class _DealProposalScreenState extends ConsumerState<DealProposalScreen> {
  final _titleCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  final _titleFocus = FocusNode();

  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;
  bool _loading = false;

  // Ονόματα και των 2 χρηστών
  String _myFullName = '';
  String _otherFullName = '';

  // Auto-suggest state
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  int _atIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadNames();
    _loadExistingProposal();
    _titleCtrl.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    _detailsCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    final myUid = ref.read(currentUserProvider)?.uid ?? '';
    if (myUid.isEmpty) return;

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(myUid).get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(widget.otherUserUid)
            .get(),
      ]);

      if (!mounted) return;
      final me = results[0].data() ?? {};
      final other = results[1].data() ?? {};

      setState(() {
        _myFullName = '${me['firstName'] ?? ''} ${me['lastName'] ?? ''}'.trim();
        _otherFullName =
            '${other['firstName'] ?? ''} ${other['lastName'] ?? ''}'.trim();
      });
    } catch (_) {}
  }

  Future<void> _loadExistingProposal() async {
    if (widget.existingDealId == null) return;
    final myUid = ref.read(currentUserProvider)?.uid ?? '';
    if (myUid.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('deals')
          .doc(widget.existingDealId)
          .get();
      if (!doc.exists || !mounted) return;

      final data = doc.data()!;
      final isUser1 = data['user1Uid'] == myUid;
      final myProposal = isUser1 ? data['proposal1'] : data['proposal2'];

      if (myProposal != null) {
        setState(() {
          _titleCtrl.text = myProposal['title'] ?? '';
          _detailsCtrl.text =
              myProposal['details'] ?? myProposal['description'] ?? '';

          final start = myProposal['startDate'] as Timestamp?;
          if (start != null) {
            final dt = start.toDate();
            _startDate = DateTime(dt.year, dt.month, dt.day);
            _startTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
          }

          final end =
              (myProposal['endDate'] ?? myProposal['deliveryAt']) as Timestamp?;
          if (end != null) {
            final dt = end.toDate();
            _endDate = DateTime(dt.year, dt.month, dt.day);
            _endTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
          }
        });
      }
    } catch (_) {}
  }

  /// Listener στο τίτλο για auto-suggestions.
  void _onTitleChanged() {
    final text = _titleCtrl.text;
    final cursorPos = _titleCtrl.selection.baseOffset;

    if (cursorPos < 0) {
      setState(() => _showSuggestions = false);
      return;
    }

    // Βρες το τελευταίο @ πριν τη θέση του cursor
    int atIdx = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atIdx = i;
        break;
      }
      // Αν βρούμε newline σταματάμε
      if (text[i] == '\n') break;
    }

    if (atIdx < 0) {
      setState(() => _showSuggestions = false);
      return;
    }

    // Πάρε το query (γράμματα μετά το @)
    final query = text.substring(atIdx + 1, cursorPos).toLowerCase();

    // Φιλτράρισμα προτεινόμενων
    final all = <String>[];
    if (_myFullName.isNotEmpty) all.add(_myFullName);
    if (_otherFullName.isNotEmpty) all.add(_otherFullName);

    final filtered =
        all.where((name) => name.toLowerCase().startsWith(query)).toList();

    setState(() {
      _atIndex = atIdx;
      _suggestions = filtered;
      _showSuggestions = filtered.isNotEmpty;
    });

    setState(() {});
  }

  /// Εισάγει το επιλεγμένο όνομα στο textfield.
  void _insertMention(String name) {
    final text = _titleCtrl.text;
    final cursorPos = _titleCtrl.selection.baseOffset;

    // Αντικατάσταση από το @ μέχρι την τρέχουσα θέση cursor με @Name + space
    final newText =
        '${text.substring(0, _atIndex)}@$name ${text.substring(cursorPos)}';

    final newCursorPos = _atIndex + name.length + 2; // 2 = @ + space

    _titleCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    setState(() => _showSuggestions = false);
  }

  /// Ελέγχει αν τίτλος περιέχει @full_name και των 2 χρηστών.
  bool get _hasMyMention =>
      _myFullName.isNotEmpty && _titleCtrl.text.contains('@$_myFullName');
  bool get _hasOtherMention =>
      _otherFullName.isNotEmpty && _titleCtrl.text.contains('@$_otherFullName');

  Future<void> _pickDateTime({required bool isStart}) async {
    final initialDate = (isStart ? _startDate : _endDate) ?? DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.primary, surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.primary, surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      if (isStart) {
        _startDate = date;
        _startTime = time;
      } else {
        _endDate = date;
        _endTime = time;
      }
    });
  }

  DateTime? _combineDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) return '';
    return '${date.day}/${date.month}/${date.year} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  /// Validation πριν το submit.
  String? _validate() {
    if (_titleCtrl.text.trim().isEmpty) {
      return 'myDeals.errFillTitle'.tr();
    }
    if (_detailsCtrl.text.trim().length < 20) {
      return 'myDeals.errDetailsMin'.tr();
    }

    final start = _combineDateTime(_startDate, _startTime);
    final end = _combineDateTime(_endDate, _endTime);

    if (start == null) return 'myDeals.pickStartDate'.tr();
    if (end == null) return 'myDeals.pickEndDate'.tr();

    if (end.isBefore(start)) {
      return 'myDeals.errEndAfterStart'.tr();
    }
    if (end.isBefore(DateTime.now())) {
      return 'myDeals.errEndFuture'.tr();
    }

    if (!_hasMyMention || !_hasOtherMention) {
      return 'mentions';
    }

    return null;
  }

  void _showMentionsError() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.danger, size: 22),
          const SizedBox(width: 8),
          Text('myDeals.missingMentions'.tr(),
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'myDeals.mentionBothTitle'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _MentionStatus(name: _myFullName, found: _hasMyMention),
            const SizedBox(height: 6),
            _MentionStatus(name: _otherFullName, found: _hasOtherMention),
            const SizedBox(height: 14),
            Text('myDeals.exampleLabel'.tr(),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'myDeals.exampleMention'.tr(
                    namedArgs: {'my': _myFullName, 'other': _otherFullName}),
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('myDeals.ok'.tr(),
                style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err == 'mentions') {
      _showMentionsError();
      return;
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _loading = true);
    try {
      final uid = ref.read(currentUserProvider)!.uid;
      final repo = ref.read(dealRepoProvider);

      String dealId = widget.existingDealId ?? '';

      if (dealId.isEmpty) {
        dealId = await repo.create(
          chatId: widget.chatId,
          listingId: widget.listingId,
          listingTitle: widget.listingTitle,
          user1Uid: uid,
          user2Uid: widget.otherUserUid,
        );
      }

      final proposal = DealProposal(
        userId: uid,
        title: _titleCtrl.text.trim(),
        details: _detailsCtrl.text.trim(),
        startDate: _combineDateTime(_startDate, _startTime)!,
        endDate: _combineDateTime(_endDate, _endTime)!,
      );

      await repo.sendProposal(dealId: dealId, userId: uid, proposal: proposal);

      try {
        await ChatRepository().sendDealProposalMessage(
          chatId: widget.chatId,
          senderId: uid,
          dealId: dealId,
          title: proposal.title,
          description: proposal.details,
          startDate: proposal.startDate,
          endDate: proposal.endDate,
        );
      } catch (e, s) {
        // Το deal δημιουργήθηκε (ο παραλήπτης βλέπει το banner μέσω provider),
        // αλλά η κάρτα μηνύματος στο chat δεν στάλθηκε — μην το κρύβουμε.
        logSwallowed(e, s, 'sendDealProposalMessage');
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('myDeals.proposalSent'.tr())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('myDeals.errorWith'.tr(namedArgs: {'e': '$e'}))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('msg.dealProposal'.tr())),
      body: SafeArea(
        child: Stack(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Προειδοποίηση κατά της απάτης. Εδώ ο χρήστης κλείνει
                // συμφωνία με άγνωστο — είναι η στιγμή που κινδυνεύει
                // περισσότερο, οπότε η κάρτα ΔΕΝ κρύβεται ποτέ.
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SafetyTips.card(),
                ),
                // Listing title banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.handshake_outlined,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(widget.listingTitle,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 20),

                // Hint banner
                _HintBanner(
                  myName: _myFullName,
                  otherName: _otherFullName,
                ),
                const SizedBox(height: 24),

                // ── 1. Τίτλος ──
                _Label('myDeals.step1Title'.tr()),
                const SizedBox(height: 6),
                _SubLabel('myDeals.step1Sub'.tr()),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleCtrl,
                  focusNode: _titleFocus,
                  maxLength: 120,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'myDeals.titleHint'.tr(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                // Live status indicators
                if (_myFullName.isNotEmpty && _otherFullName.isNotEmpty)
                  Row(children: [
                    _MentionStatus(name: _myFullName, found: _hasMyMention),
                    const SizedBox(width: 16),
                    _MentionStatus(
                        name: _otherFullName, found: _hasOtherMention),
                  ]),

                const SizedBox(height: 20),

                // ── 2. Λεπτομέρειες ──
                _Label('myDeals.step2Title'.tr()),
                const SizedBox(height: 6),
                _SubLabel('myDeals.step2Sub'.tr()),
                const SizedBox(height: 8),
                TextField(
                  controller: _detailsCtrl,
                  maxLines: 5,
                  maxLength: 500,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'myDeals.detailsHint'.tr(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── 3. Έναρξη ──
                _Label('myDeals.step3Title'.tr()),
                const SizedBox(height: 8),
                _DateTimeBox(
                  icon: Icons.event_available,
                  text: _startDate != null
                      ? _formatDateTime(_startDate, _startTime)
                      : 'myDeals.pickStartDate'.tr(),
                  hasValue: _startDate != null,
                  onTap: () => _pickDateTime(isStart: true),
                ),
                const SizedBox(height: 16),

                // ── 4. Λήξη ──
                _Label('myDeals.step4Title'.tr()),
                const SizedBox(height: 8),
                _DateTimeBox(
                  icon: Icons.event_busy,
                  text: _endDate != null
                      ? _formatDateTime(_endDate, _endTime)
                      : 'myDeals.pickEndDate'.tr(),
                  hasValue: _endDate != null,
                  onTap: () => _pickDateTime(isStart: false),
                ),

                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.background))
                      : Text('myDeals.sendProposal'.tr()),
                ),
                const SizedBox(height: 12),
                Text(
                  'myDeals.bothAgreeHint'.tr(),
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Auto-suggestion popup
          if (_showSuggestions && _titleFocus.hasFocus)
            Positioned(
              left: 16,
              right: 16,
              top: 290, // περίπου κάτω από το τίτλο
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: AppColors.surface,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _suggestions.map((name) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person,
                            color: AppColors.primary, size: 18),
                        title: Text(name,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        onTap: () => _insertMention(name),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Helper Widgets ──

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700));
}

class _SubLabel extends StatelessWidget {
  final String text;
  const _SubLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: AppColors.textHint, fontSize: 11));
}

class _MentionStatus extends StatelessWidget {
  final String name;
  final bool found;
  const _MentionStatus({required this.name, required this.found});

  @override
  Widget build(BuildContext context) {
    final color = found ? AppColors.offer : AppColors.danger;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(found ? Icons.check_circle : Icons.error_outline,
          color: color, size: 14),
      const SizedBox(width: 4),
      Text('@$name',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _DateTimeBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool hasValue;
  final VoidCallback onTap;
  const _DateTimeBox({
    required this.icon,
    required this.text,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hasValue ? AppColors.primary : AppColors.border,
                width: hasValue ? 1.5 : 0.5),
          ),
          child: Row(children: [
            Icon(icon,
                color: hasValue ? AppColors.primary : AppColors.textSecondary,
                size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color:
                          hasValue ? AppColors.textPrimary : AppColors.textHint,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textHint, size: 18),
          ]),
        ),
      );
}

class _HintBanner extends StatelessWidget {
  final String myName, otherName;
  const _HintBanner({required this.myName, required this.otherName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.deal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.deal.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.deal, size: 18),
          const SizedBox(width: 8),
          Text('myDeals.tip'.tr(),
              style: const TextStyle(
                  color: AppColors.deal,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text(
          'myDeals.tipBody'.tr(),
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 12, height: 1.4),
        ),
        if (myName.isNotEmpty && otherName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'myDeals.exampleFull'
                  .tr(namedArgs: {'my': myName, 'other': otherName}),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ]),
    );
  }
}
