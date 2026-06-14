import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/deal_model.dart';
import '../providers/deal_provider.dart';

class MyDealsScreen extends ConsumerStatefulWidget {
  const MyDealsScreen({super.key});

  @override
  ConsumerState<MyDealsScreen> createState() => _MyDealsScreenState();
}

class _MyDealsScreenState extends ConsumerState<MyDealsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dealsAsync = ref.watch(myDealsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Τα Deals μου'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Εκκρεμή'),
            Tab(text: 'Ενεργά'),
            Tab(text: 'Ολοκληρωμένα'),
          ],
        ),
      ),
      body: dealsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Σφάλμα: $e',
                style: const TextStyle(color: AppColors.danger))),
        data: (allDeals) {
          final pending = allDeals
              .where((d) =>
                  d.status == DealStatus.pending ||
                  d.status == DealStatus.accepted)
              .toList();
          final active =
              allDeals.where((d) => d.status == DealStatus.active).toList();
          final completed = allDeals
              .where((d) =>
                  d.status == DealStatus.completed ||
                  d.status == DealStatus.cancelled)
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _DealsList(
                deals: pending,
                emptyTitle: 'Δεν έχεις εκκρεμή deals',
                emptySubtitle:
                    'Όταν στείλεις ή λάβεις μια πρόταση, θα εμφανίζεται εδώ.',
                tab: _DealTab.pending,
              ),
              _DealsList(
                deals: active,
                emptyTitle: 'Δεν έχεις ενεργά deals',
                emptySubtitle:
                    'Όταν συμφωνήσετε με κάποιον, το deal θα ξεκινήσει εδώ.',
                tab: _DealTab.active,
              ),
              _DealsList(
                deals: completed,
                emptyTitle: 'Δεν έχεις ολοκληρωμένα deals',
                emptySubtitle: 'Τα παλιά deals θα εμφανίζονται εδώ.',
                tab: _DealTab.completed,
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _DealTab { pending, active, completed }

class _DealsList extends StatelessWidget {
  final List<DealModel> deals;
  final String emptyTitle;
  final String emptySubtitle;
  final _DealTab tab;

  const _DealsList({
    required this.deals,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.tab,
  });

  @override
  Widget build(BuildContext context) {
    if (deals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                tab == _DealTab.pending
                    ? Icons.pending_outlined
                    : tab == _DealTab.active
                        ? Icons.handshake_outlined
                        : Icons.check_circle_outline,
                color: AppColors.textHint,
                size: 60),
            const SizedBox(height: 16),
            Text(emptyTitle,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(emptySubtitle,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: deals.length,
      itemBuilder: (_, i) => _DealCard(deal: deals[i], tab: tab),
    );
  }
}

class _DealCard extends ConsumerStatefulWidget {
  final DealModel deal;
  final _DealTab tab;
  const _DealCard({required this.deal, required this.tab});

  @override
  ConsumerState<_DealCard> createState() => _DealCardState();
}

class _DealCardState extends ConsumerState<_DealCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.tab == _DealTab.active && !widget.deal.isExpired) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return 'Έληξε';
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);
    if (days > 0) return '${days}μ ${hours}ω';
    if (hours > 0) return '${hours}ω ${minutes}λ';
    return '${minutes}λ';
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final deal = widget.deal;
    Color color;
    String statusLabel;
    IconData statusIcon;

    switch (widget.tab) {
      case _DealTab.pending:
        color = AppColors.deal;
        statusLabel = deal.status == DealStatus.accepted
            ? 'Έχει αποδεχτεί ο άλλος'
            : 'Εκκρεμεί';
        statusIcon = Icons.pending_outlined;
        break;
      case _DealTab.active:
        color = AppColors.offer;
        statusLabel = 'Ενεργό';
        statusIcon = Icons.handshake;
        break;
      case _DealTab.completed:
        color = deal.status == DealStatus.cancelled
            ? AppColors.danger
            : AppColors.primary;
        statusLabel =
            deal.status == DealStatus.cancelled ? 'Ακυρώθηκε' : 'Ολοκληρώθηκε';
        statusIcon = deal.status == DealStatus.cancelled
            ? Icons.cancel
            : Icons.check_circle;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Pending → άνοιγμα chat / deal review
          if (widget.tab == _DealTab.pending) {
            context.push('/deal-review/${deal.id}');
          } else {
            // Active/Completed → wall post (αν υπάρχει)
            _openWallPost(context, deal);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusLabel,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(deal.displayTitle,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (widget.tab == _DealTab.active &&
                    !deal.isExpired &&
                    deal.endDate != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_formatCountdown(deal.remaining),
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                if (widget.tab == _DealTab.completed && deal.endDate != null)
                  Text(_formatDate(deal.endDate!),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/chat/${deal.chatId}'),
                    icon: const Icon(Icons.chat_bubble_outline,
                        size: 14, color: AppColors.primary),
                    label: const Text('Chat',
                        style:
                            TextStyle(color: AppColors.primary, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Action button — αλλάζει ανάλογα με tab
                if (widget.tab == _DealTab.pending)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/deal-review/${deal.id}'),
                      icon: const Icon(Icons.visibility, size: 14),
                      label: const Text('Δες', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  )
                else if (widget.tab == _DealTab.completed &&
                    deal.status == DealStatus.completed)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/rate-deal/${deal.id}'),
                      icon: const Icon(Icons.star, size: 14),
                      label: const Text('Αξιολόγησε',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openWallPost(context, deal),
                      icon: const Icon(Icons.forum_outlined, size: 14),
                      label: const Text('Δες deal',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        side: BorderSide(color: color),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWallPost(BuildContext context, DealModel deal) async {
    final currentUid = ref.read(currentUserProvider)?.uid ?? '';
    final scaffold = ScaffoldMessenger.of(context);

    // Find wall post for this user + this deal
    final snap = await FirebaseFirestore.instance
        .collection('wallPosts')
        .where('dealId', isEqualTo: deal.id)
        .where('targetUid', isEqualTo: currentUid)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      scaffold.showSnackBar(
          const SnackBar(content: Text('Το wall post δεν βρέθηκε')));
      return;
    }

    if (context.mounted) {
      context.push('/wall-post/${snap.docs.first.id}');
    }
  }
}
