import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

/// Ρυθμίσεις push ειδοποιήσεων ανά κατηγορία. Οι επιλογές αποθηκεύονται στο
/// PRIVATE doc (users/{uid}/private/data) ως
/// `notifPrefs: { chat, deals, friends, social, listings }` και τις ελέγχει το
/// Cloud Function `sendToUser` πριν στείλει push — αν μια κατηγορία είναι
/// κλειστή, δεν στέλνεται. (Private doc: απλοί κανόνες owner-only, και το
/// sendToUser ήδη το διαβάζει.)
///
/// Προεπιλογή: όλα ανοιχτά (απουσία κλειδιού = true), ώστε οι υπάρχοντες χρήστες
/// να μη χάσουν ειδοποιήσεις.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  static const _categories = <({String key, String icon, IconData iconData})>[
    (key: 'chat', icon: '', iconData: Icons.chat_bubble_outline),
    (key: 'deals', icon: '', iconData: Icons.handshake_outlined),
    (key: 'friends', icon: '', iconData: Icons.group_add_outlined),
    (key: 'social', icon: '', iconData: Icons.comment_outlined),
    (key: 'listings', icon: '', iconData: Icons.hourglass_bottom),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;

    return Scaffold(
      appBar: AppBar(title: Text('notifsettings.title'.tr())),
      body: uid == null
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('private')
                  .doc('data')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary));
                }
                final data = snap.data!.data() as Map<String, dynamic>?;
                final prefs =
                    (data?['notifPrefs'] as Map<String, dynamic>?) ?? const {};

                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('notifsettings.subtitle'.tr(),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ),
                    for (final c in _categories)
                      SwitchListTile(
                        secondary: Icon(c.iconData,
                            color: AppColors.textSecondary, size: 22),
                        title: Text('notifsettings.${c.key}'.tr(),
                            style:
                                const TextStyle(color: AppColors.textPrimary)),
                        subtitle: Text('notifsettings.${c.key}Sub'.tr(),
                            style: const TextStyle(
                                color: AppColors.textHint, fontSize: 12)),
                        activeThumbColor: AppColors.primary,
                        // Απουσία κλειδιού = ενεργό (προεπιλογή on).
                        value: prefs[c.key] as bool? ?? true,
                        onChanged: (v) => FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('private')
                            .doc('data')
                            .set({
                          'notifPrefs': {c.key: v}
                        }, SetOptions(merge: true)),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
