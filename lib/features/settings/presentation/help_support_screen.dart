import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const String _supportEmail = 'support@shareit.app';

  static List<Map<String, String>> get _faqs => [
        {'q': 'help.faqQ1'.tr(), 'a': 'help.faqA1'.tr()},
        {'q': 'help.faqQ2'.tr(), 'a': 'help.faqA2'.tr()},
        {'q': 'help.faqQ3'.tr(), 'a': 'help.faqA3'.tr()},
        {'q': 'help.faqQ4'.tr(), 'a': 'help.faqA4'.tr()},
        {'q': 'help.faqQ5'.tr(), 'a': 'help.faqA5'.tr()},
        {'q': 'help.faqQ6'.tr(), 'a': 'help.faqA6'.tr()},
        {'q': 'help.faqQ7'.tr(), 'a': 'help.faqA7'.tr()},
        {'q': 'help.faqQ8'.tr(), 'a': 'help.faqA8'.tr()},
        {'q': 'help.faqQ9'.tr(), 'a': 'help.faqA9'.tr()},
        {'q': 'help.faqQ10'.tr(), 'a': 'help.faqA10'.tr()},
      ];

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${'help.emailSubject'.tr()}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.help'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(children: [
              const Icon(Icons.support_agent, color: AppColors.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('help.hereForYou'.tr(),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'help.headerSub'.tr(),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // FAQ Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('help.faqTitle'.tr(),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          ..._faqs
              .map((faq) => _FaqTile(question: faq['q']!, answer: faq['a']!)),

          const SizedBox(height: 24),

          // Contact Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('help.contact'.tr(),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.email_outlined,
                    color: AppColors.primary, size: 22),
                title: Text('help.sendEmail'.tr(),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                subtitle: const Text(_supportEmail,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.open_in_new,
                    color: AppColors.textHint, size: 16),
                onTap: _sendEmail,
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Response time note
          Center(
            child: Text(
              'help.responseTime'.tr(),
              style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textSecondary,
          title: Text(question,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(answer,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
