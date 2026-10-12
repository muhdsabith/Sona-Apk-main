import 'package:flutter/material.dart';
import 'olam_theme.dart';

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color = lavender,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(30),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: cream,
                      fontWeight: FontWeight.w800,
                      fontSize: 23,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(icon, color: cream, size: 36),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF33263B), height: 1.4),
            ),
            const SizedBox(height: 18),
            const CircleAvatar(
              backgroundColor: cream,
              radius: 22,
              child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}
