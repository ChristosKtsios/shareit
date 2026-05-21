import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';

class UserAvatar extends StatelessWidget {
  final String initials;
  final String? avatarUrl;
  final double radius;
  final bool showVerified;
  const UserAvatar({super.key, required this.initials, this.avatarUrl,
      this.radius = 20, this.showVerified = false});

  @override
  Widget build(BuildContext context) {
    Widget av = avatarUrl != null && avatarUrl!.isNotEmpty
        ? CircleAvatar(radius: radius, backgroundImage: CachedNetworkImageProvider(avatarUrl!))
        : CircleAvatar(radius: radius, backgroundColor: AppColors.primarySurface,
            child: Text(initials.toUpperCase(),
                style: TextStyle(color: AppColors.primary,
                    fontSize: radius * 0.6, fontWeight: FontWeight.w600)));
    if (!showVerified) return av;
    return Stack(children: [
      av,
      Positioned(right: 0, bottom: 0, child: Container(
        width: radius * 0.7, height: radius * 0.7,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Icon(Icons.check, color: AppColors.background, size: radius * 0.45),
      )),
    ]);
  }
}
