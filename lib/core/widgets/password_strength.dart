import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../features/auth/data/auth_repository.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  const PasswordStrengthIndicator({super.key, required this.password});

  // ΜΙΑ πηγή αλήθειας: οι ΙΔΙΟΙ κανόνες με τον validator/κουμπί.
  List<PasswordRule> get _rules => AuthRepository.passwordRules(password);

  int get _score => _rules.where((r) => r.met).length;

  Color get _strengthColor {
    if (_score <= 1) return AppColors.danger;
    if (_score == 2) return AppColors.deal;
    if (_score == 3) return AppColors.deal;
    return AppColors.offer;
  }

  String get _strengthLabel {
    if (password.isEmpty) return '';
    if (_score <= 1) return 'pwstr.weak'.tr();
    if (_score == 2) return 'pwstr.medium'.tr();
    if (_score == 3) return 'pwstr.good'.tr();
    return 'pwstr.strong'.tr();
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(children: [
          ...List.generate(4, (i) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: i < _score ? _strengthColor : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )),
          const SizedBox(width: 8),
          Text(_strengthLabel,
              style: TextStyle(color: _strengthColor,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        ..._rules.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: r.met ? AppColors.primary : Colors.transparent,
                border: Border.all(
                    color: r.met ? AppColors.primary : AppColors.textHint,
                    width: 1.5),
                shape: BoxShape.circle,
              ),
              child: r.met
                  ? const Icon(Icons.check, color: AppColors.background, size: 10)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(r.label,
                style: TextStyle(
                    color: r.met ? AppColors.textPrimary : AppColors.textHint,
                    fontSize: 12)),
          ]),
        )),
      ],
    );
  }
}