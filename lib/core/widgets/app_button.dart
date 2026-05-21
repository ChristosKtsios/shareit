import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  const AppButton({super.key, required this.label,
      this.onPressed, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: loading ? null : onPressed,
    child: loading
        ? const SizedBox(height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
        : icon != null
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18), const SizedBox(width: 8), Text(label)])
            : Text(label),
  );
}
