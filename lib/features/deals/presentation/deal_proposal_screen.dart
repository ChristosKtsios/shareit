import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
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
  ConsumerState<DealProposalScreen> createState() =>
      _DealProposalScreenState();
}

class _DealProposalScreenState extends ConsumerState<DealProposalScreen> {
  final _reasonCtrl   = TextEditingController();
  final _iGiveCtrl    = TextEditingController();
  final _iReceiveCtrl = TextEditingController();
  final _amountCtrl   = TextEditingController();

  DateTime? _deliveryDate;
  TimeOfDay? _deliveryTime;
  bool _withPayment = false;
  bool _loading     = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _iGiveCtrl.dispose();
    _iReceiveCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _deliveryDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _deliveryTime = time);
  }

  DateTime? get _deliveryDateTime {
    if (_deliveryDate == null || _deliveryTime == null) return null;
    return DateTime(
      _deliveryDate!.year, _deliveryDate!.month, _deliveryDate!.day,
      _deliveryTime!.hour, _deliveryTime!.minute,
    );
  }

  bool get _isValid =>
      _reasonCtrl.text.trim().isNotEmpty &&
      _iGiveCtrl.text.trim().isNotEmpty &&
      _iReceiveCtrl.text.trim().isNotEmpty &&
      _deliveryDateTime != null &&
      (!_withPayment || _amountCtrl.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Συμπλήρωσε όλα τα πεδία.')));
      return;
    }

    setState(() => _loading = true);
    try {
      final uid  = ref.read(currentUserProvider)!.uid;
      final repo = ref.read(dealRepoProvider);

      String dealId = widget.existingDealId ?? '';

      // Αν δεν υπάρχει deal ακόμα, δημιούργησε
      if (dealId.isEmpty) {
        dealId = await repo.create(
          chatId:       widget.chatId,
          listingId:    widget.listingId,
          listingTitle: widget.listingTitle,
          user1Uid:     uid,
          user2Uid:     widget.otherUserUid,
        );
      }

      // Στείλε πρόταση
      final proposal = DealProposal(
        userId:      uid,
        reason:      _reasonCtrl.text.trim(),
        iGive:       _iGiveCtrl.text.trim(),
        iReceive:    _iReceiveCtrl.text.trim(),
        deliveryAt:  _deliveryDateTime!,
        withPayment: _withPayment,
        amount: _withPayment
            ? double.tryParse(_amountCtrl.text.trim())
            : null,
      );

      await repo.sendProposal(
          dealId: dealId, userId: uid, proposal: proposal);

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Η πρότασή σου στάλθηκε! '
                  'Περίμενε την αποδοχή του άλλου χρήστη.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Πρόταση Deal')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Listing title
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
                  Expanded(child: Text(widget.listingTitle,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 24),

              // Λόγος ανταλλαγής
              const _Label('Λόγος ανταλλαγής'),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                    hintText: 'π.χ. Χρειάζομαι τρυπάνι για επισκευή...'),
              ),
              const SizedBox(height: 16),

              // Εγώ δίνω
              const _Label('Εγώ δίνω'),
              const SizedBox(height: 8),
              TextField(
                controller: _iGiveCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                    hintText: 'π.χ. Βιβλία αγγλικών'),
              ),
              const SizedBox(height: 16),

              // Παίρνω
              const _Label('Παίρνω'),
              const SizedBox(height: 8),
              TextField(
                controller: _iReceiveCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                    hintText: 'π.χ. Ηλεκτρικό τρυπάνι'),
              ),
              const SizedBox(height: 16),

              // Ημερομηνία & ώρα παράδοσης
              const _Label('Ημερομηνία & ώρα παράδοσης'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _pickDate,
                  child: _DateTimeBox(
                    icon: Icons.calendar_today_outlined,
                    text: _deliveryDate != null
                        ? '${_deliveryDate!.day}/${_deliveryDate!.month}/${_deliveryDate!.year}'
                        : 'Ημερομηνία',
                    hasValue: _deliveryDate != null,
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: _pickTime,
                  child: _DateTimeBox(
                    icon: Icons.access_time,
                    text: _deliveryTime != null
                        ? '${_deliveryTime!.hour.toString().padLeft(2, '0')}:${_deliveryTime!.minute.toString().padLeft(2, '0')}'
                        : 'Ώρα',
                    hasValue: _deliveryTime != null,
                  ),
                )),
              ]),
              const SizedBox(height: 20),

              // Με πληρωμή toggle
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.euro_outlined,
                        color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Με πληρωμή',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500))),
                    Switch(
                      value: _withPayment,
                      onChanged: (v) => setState(() => _withPayment = v),
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: AppColors.primarySurface,
                    ),
                  ]),

                  // Ποσό — εμφανίζεται μόνο αν withPayment = true
                  if (_withPayment) ...[
                    const Divider(height: 20),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Ποσό (€)',
                        prefixIcon: Icon(Icons.euro,
                            color: AppColors.textSecondary, size: 18),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 32),

              // Submit
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background))
                    : const Text('Αποστολή πρότασης'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500));
}

class _DateTimeBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool hasValue;
  const _DateTimeBox({
    required this.icon,
    required this.text,
    required this.hasValue,
  });

  @override
  Widget build(BuildContext context) => Container(
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
          size: 16),
      const SizedBox(width: 8),
      Text(text,
          style: TextStyle(
              color: hasValue
                  ? AppColors.textPrimary : AppColors.textHint,
              fontSize: 14)),
    ]),
  );
}