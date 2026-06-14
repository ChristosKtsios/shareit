import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../notifications/providers/notification_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _idx(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/feed')) return 1;
    if (loc.startsWith('/messages')) return 2;
    if (loc.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _idx(context);
    // FIX: unreadCountProvider είναι τώρα StreamProvider<int>, οπότε
    // παίρνουμε το int μέσω .valueOrNull (0 αν δεν έχει φορτώσει).
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab',
        onPressed: () => context.push('/listing/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        shape: const CircleBorder(),
        elevation: 0,
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        elevation: 0,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
                icon: Icons.map_outlined,
                activeIcon: Icons.map,
                label: AppStrings.navMap,
                index: 0,
                current: idx,
                onTap: () => context.go('/map')),
            _NavItem(
                icon: Icons.search_outlined,
                activeIcon: Icons.search,
                label: AppStrings.navFeed,
                index: 1,
                current: idx,
                onTap: () => context.go('/feed')),
            const SizedBox(width: 56),
            _NavItem(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: AppStrings.navMessages,
                index: 2,
                current: idx,
                onTap: () => context.go('/messages'),
                badge: unread),
            _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: AppStrings.navProfile,
                index: 3,
                current: idx,
                onTap: () => context.go('/profile')),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final int index, current;
  final VoidCallback onTap;
  final int badge;
  const _NavItem(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      required this.index,
      required this.current,
      required this.onTap,
      this.badge = 0});
  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(children: [
                Icon(active ? activeIcon : icon,
                    color: active ? AppColors.primary : AppColors.textSecondary,
                    size: 22),
                if (badge > 0)
                  Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                            color: AppColors.danger, shape: BoxShape.circle),
                        child: Center(
                            child: Text(badge > 9 ? '9+' : '$badge',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700))),
                      )),
              ]),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color:
                          active ? AppColors.primary : AppColors.textSecondary,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.normal)),
            ],
          )),
    );
  }
}
