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
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, size: 28, color: Colors.white),
            const SizedBox(height: 18),
            Text(metric.title, style: titleStyle),
            const SizedBox(height: 8),
            Text(metric.value, style: valueStyle),
            const SizedBox(height: 4),
            Text(metric.deltaLabel, style: titleStyle.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}


