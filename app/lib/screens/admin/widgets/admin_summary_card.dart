import 'package:flutter/material.dart';

class AdminSummaryMetric {
  const AdminSummaryMetric({
    required this.title,
    required this.value,
    required this.deltaLabel,
    required this.icon,
    required this.background,
  });

  final String title;
  final String value;
  final String deltaLabel;
  final IconData icon;
  final Color background;
}

class AdminSummaryCard extends StatelessWidget {
  const AdminSummaryCard({super.key, required this.metric});

  final AdminSummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.white.withAlpha(210));
    final TextStyle valueStyle = Theme.of(context).textTheme.headlineSmall!.copyWith(color: Colors.white);
    return Card(
      color: metric.background,
      // Use clipBehavior to prevent overflow rendering issues
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          // Use mainAxisSize.min to prevent expansion
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(metric.icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    metric.title,
                    style: titleStyle.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              metric.value,
              style: valueStyle.copyWith(fontSize: 26, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              metric.deltaLabel,
              style: titleStyle.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}


