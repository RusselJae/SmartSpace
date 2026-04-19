import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminAnalyticsColors {
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE5E7EB);
  static const Color muted = Color(0xFF6B7280);
  static const Color primary = Color(0xFF4F46E5);
  static const Color secondary = Color(0xFFA5B4FC);
  static const Color positive = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color negative = Color(0xFFDC2626);
  static const Color neutralTrack = Color(0xFFF1F5F9);
}

/// Shared layout tokens so spacing/typography remain visually consistent across tabs.
class _AdminUiTokens {
  static const double radius = 12;
  static const double borderWidth = 1;
  static const double cardPadding = 16;
  static const double cardInnerGap = 6;
  static const double groupGap = 12;
  static const double sectionPadding = 20;
  static const double kpiValueSize = 31;
  static const double kpiValueSizeCompact = 33;
}

class AdminKpiItem {
  const AdminKpiItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accent,
    this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color accent;
  final IconData? icon;
}

class AdminKpiGrid extends StatelessWidget {
  const AdminKpiGrid({
    super.key,
    required this.items,
    this.maxColumns = 4,
  });

  final List<AdminKpiItem> items;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1280
            ? maxColumns
            : constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns.clamp(1, maxColumns),
            crossAxisSpacing: _AdminUiTokens.groupGap,
            mainAxisSpacing: _AdminUiTokens.groupGap,
            childAspectRatio: 2.55,
          ),
          itemBuilder: (context, index) => _AdminKpiCard(item: items[index]),
        );
      },
    );
  }
}

/// Reference-style KPI strip:
/// - Desktop: one row, 4 cards, no gaps (joined look with dividers).
/// - Smaller screens: gracefully wraps into grid for readability.
class AdminKpiStripRow extends StatelessWidget {
  const AdminKpiStripRow({
    super.key,
    required this.items,
  });

  final List<AdminKpiItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980 && items.length >= 4) {
          final rowItems = items.take(4).toList(growable: false);
          return Container(
            decoration: BoxDecoration(
              color: AdminAnalyticsColors.surface,
              borderRadius: BorderRadius.circular(_AdminUiTokens.radius),
              border: Border.all(color: AdminAnalyticsColors.border, width: _AdminUiTokens.borderWidth),
            ),
            child: Row(
              children: [
                for (var i = 0; i < rowItems.length; i++) ...[
                  Expanded(child: _AdminKpiCard(item: rowItems[i], compact: true, showBorder: false)),
                  if (i != rowItems.length - 1)
                    const SizedBox(
                      height: 126,
                      child: VerticalDivider(width: 1, thickness: 1, color: AdminAnalyticsColors.border),
                    ),
                ],
              ],
            ),
          );
        }
        return AdminKpiGrid(items: items, maxColumns: 4);
      },
    );
  }
}

class _AdminKpiCard extends StatelessWidget {
  const _AdminKpiCard({
    required this.item,
    this.compact = false,
    this.showBorder = true,
  });

  final AdminKpiItem item;
  final bool compact;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AdminAnalyticsColors.surface,
        borderRadius: BorderRadius.circular(_AdminUiTokens.radius),
        border: showBorder ? Border.all(color: AdminAnalyticsColors.border, width: _AdminUiTokens.borderWidth) : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _AdminUiTokens.cardPadding, vertical: compact ? 16 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AdminAnalyticsColors.muted,
                          fontSize: compact ? 14 : 13,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                  ),
                ),
                if (item.icon != null)
                  Container(
                    width: compact ? 28 : 26,
                    height: compact ? 28 : 26,
                    decoration: BoxDecoration(
                      color: item.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, size: compact ? 16 : 15, color: item.accent),
                  ),
              ],
            ),
            const SizedBox(height: _AdminUiTokens.cardInnerGap),
            Text(
              item.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: compact ? _AdminUiTokens.kpiValueSizeCompact : _AdminUiTokens.kpiValueSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.35,
                    height: 1.08,
                  ),
            ),
            if (compact)
              const SizedBox(height: 10)
            else
              const Spacer(),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AdminAnalyticsColors.muted,
                    fontSize: compact ? 12.5 : 12,
                    height: 1.2,
                  ),
            ),
            if (!compact) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: 0.76,
                  minHeight: 4,
                  backgroundColor: AdminAnalyticsColors.neutralTrack,
                  valueColor: AlwaysStoppedAnimation<Color>(item.accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminSeriesPoint {
  const AdminSeriesPoint({required this.x, required this.y});

  final DateTime x;
  final double y;
}

class AdminDualSeriesChartCard extends StatelessWidget {
  const AdminDualSeriesChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.primary,
    required this.secondary,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final String secondaryLabel;
  final List<AdminSeriesPoint> primary;
  final List<AdminSeriesPoint> secondary;

  @override
  Widget build(BuildContext context) {
    final monthFormat = DateFormat('MMM');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_AdminUiTokens.sectionPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AdminAnalyticsColors.muted)),
                    ],
                  ),
                ),
                _LegendDot(color: AdminAnalyticsColors.primary, label: primaryLabel),
                const SizedBox(width: 10),
                _LegendDot(color: AdminAnalyticsColors.secondary, label: secondaryLabel),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _DualChartPainter(primary: primary, secondary: secondary),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            if (primary.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final point in primary)
                    if (point.x.month.isOdd)
                      Text(monthFormat.format(point.x), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DualChartPainter extends CustomPainter {
  _DualChartPainter({required this.primary, required this.secondary});

  final List<AdminSeriesPoint> primary;
  final List<AdminSeriesPoint> secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (primary.length < 2 || secondary.length < 2) return;
    final maxPrimary = primary.fold<double>(1, (max, p) => p.y > max ? p.y : max);
    final maxSecondary = secondary.fold<double>(1, (max, p) => p.y > max ? p.y : max);

    final grid = Paint()
      ..color = AdminAnalyticsColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Path buildPath(List<AdminSeriesPoint> src, double maxY) {
      final path = Path();
      for (var i = 0; i < src.length; i++) {
        final x = size.width * i / (src.length - 1);
        final y = size.height - ((src[i].y / maxY) * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    final pPath = buildPath(primary, maxPrimary);
    final sPath = buildPath(secondary, maxSecondary);

    final pPaint = Paint()
      ..color = AdminAnalyticsColors.primary
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;
    final sPaint = Paint()
      ..color = AdminAnalyticsColors.secondary
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(sPath, sPaint);
    canvas.drawPath(pPath, pPaint);
  }

  @override
  bool shouldRepaint(covariant _DualChartPainter oldDelegate) {
    return oldDelegate.primary != primary || oldDelegate.secondary != secondary;
  }
}

/// Granularity for the unified admin trend chart (Overview).
enum AdminTrendGranularity {
  /// Monday–Sunday buckets (current calendar week on dashboard; selected week on sales).
  weekly,
  monthly,
  yearly,
}

enum AdminTrendSelectorPlacement {
  top,
  bottom,
}

/// Single-series trend with Weekly / Monthly / Yearly control (Apple-style segmented control).
class AdminUnifiedTrendChartCard extends StatelessWidget {
  const AdminUnifiedTrendChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.seriesLabel,
    required this.points,
    required this.granularity,
    required this.onGranularityChanged,
    this.valueFormatter,
    /// Overrides default x labels derived from [granularity] (e.g. sales “weeks in month”).
    this.xAxisLabelFormatter,
    this.showGranularitySelector = true,
    this.selectorPlacement = AdminTrendSelectorPlacement.top,
  });

  final String title;
  final String subtitle;
  final String seriesLabel;
  final List<AdminSeriesPoint> points;
  final AdminTrendGranularity granularity;
  final ValueChanged<AdminTrendGranularity> onGranularityChanged;
  final String Function(double y)? valueFormatter;
  /// When non-null, each point’s `x` is formatted with this instead of [_xLabel].
  final String Function(DateTime x)? xAxisLabelFormatter;
  final bool showGranularitySelector;
  final AdminTrendSelectorPlacement selectorPlacement;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Stack title + segmented control on narrow widths so the picker never clips.
            // Apple HIG: controls stay tappable and readable at any size.
            final bool stackControls = constraints.maxWidth < 520;
            final granularityPicker = SegmentedButton<AdminTrendGranularity>(
              segments: const [
                ButtonSegment(value: AdminTrendGranularity.weekly, label: Text('Weekly')),
                ButtonSegment(value: AdminTrendGranularity.monthly, label: Text('Monthly')),
                ButtonSegment(value: AdminTrendGranularity.yearly, label: Text('Yearly')),
              ],
              selected: {granularity},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                onGranularityChanged(s.first);
              },
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stackControls) ...[
                  Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AdminAnalyticsColors.muted)),
                  if (showGranularitySelector && selectorPlacement == AdminTrendSelectorPlacement.top) ...[
                    const SizedBox(height: 12),
                    Center(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: granularityPicker)),
                  ],
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AdminAnalyticsColors.muted)),
                          ],
                        ),
                      ),
                      if (showGranularitySelector && selectorPlacement == AdminTrendSelectorPlacement.top) granularityPicker,
                    ],
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: AdminAnalyticsColors.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(seriesLabel, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 228,
                  child: Row(
                    children: [
                      // Left-side amount axis (requested) to improve read-at-a-glance values.
                      SizedBox(
                        width: 68,
                        child: _TrendYAxisLabels(
                          points: points,
                          valueFormatter: valueFormatter,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CustomPaint(
                          painter: _SingleSeriesChartPainter(
                            points: points,
                            lineColor: AdminAnalyticsColors.primary,
                            fillColor: AdminAnalyticsColors.primary.withValues(alpha: 0.08),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
                if (points.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  // X labels are aligned to each point index so days/months/years
                  // sit directly under their corresponding points.
                  Row(
                    children: [
                      const SizedBox(width: 78),
                      Expanded(
                        child: Row(
                          children: [
                            for (final p in points)
                              Expanded(
                                child: Text(
                                  (xAxisLabelFormatter ?? (DateTime x) => _xLabel(x, granularity))(p.x),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF70778A),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (showGranularitySelector && selectorPlacement == AdminTrendSelectorPlacement.bottom) ...[
                  const SizedBox(height: 10),
                  Center(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: granularityPicker)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _xLabel(DateTime x, AdminTrendGranularity g) {
    switch (g) {
      case AdminTrendGranularity.weekly:
        return DateFormat.E().format(x.toLocal());
      case AdminTrendGranularity.monthly:
        return DateFormat.MMM().format(x.toLocal());
      case AdminTrendGranularity.yearly:
        return DateFormat.y().format(x.toLocal());
    }
  }
}

class _SingleSeriesChartPainter extends CustomPainter {
  _SingleSeriesChartPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
  });

  final List<AdminSeriesPoint> points;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxY = points.fold<double>(1, (m, p) => p.y > m ? p.y : m);

    final grid = Paint()
      ..color = const Color(0xFFECEFF5)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (points.length == 1) {
      final x = size.width / 2;
      final y = size.height - ((points[0].y / maxY) * size.height);
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = lineColor);
      return;
    }

    final line = Path();
    final area = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height - ((points[i].y / maxY) * size.height);
      if (i == 0) {
        line.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area.lineTo(size.width, size.height);
    area.close();

    canvas.drawPath(area, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );

    final dot = Paint()..color = lineColor;
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height - ((points[i].y / maxY) * size.height);
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SingleSeriesChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _TrendYAxisLabels extends StatelessWidget {
  const _TrendYAxisLabels({
    required this.points,
    this.valueFormatter,
  });

  final List<AdminSeriesPoint> points;
  final String Function(double y)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<double>(1, (m, p) => p.y > m ? p.y : m);
    String format(double v) {
      if (valueFormatter != null) return valueFormatter!(v);
      if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
      return v.toStringAsFixed(0);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(format(maxY), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AdminAnalyticsColors.muted, fontWeight: FontWeight.w600)),
        Text(format(maxY * 0.75), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AdminAnalyticsColors.muted, fontWeight: FontWeight.w600)),
        Text(format(maxY * 0.50), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AdminAnalyticsColors.muted, fontWeight: FontWeight.w600)),
        Text(format(maxY * 0.25), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AdminAnalyticsColors.muted, fontWeight: FontWeight.w600)),
        Text(format(0), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AdminAnalyticsColors.muted, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class AdminInsightEntry {
  const AdminInsightEntry({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;
}

class AdminInsightColumn {
  const AdminInsightColumn({
    required this.title,
    required this.entries,
    this.segmentLabels = const [],
    this.activeSegment = 0,
    this.onSegmentSelected,
    this.onOpenPanel,
    this.openLabel = 'Open',
  });

  final String title;
  final List<AdminInsightEntry> entries;
  final List<String> segmentLabels;
  final int activeSegment;
  final ValueChanged<int>? onSegmentSelected;
  final VoidCallback? onOpenPanel;
  final String openLabel;
}

/// Bottom analytics area style copied from the provided reference:
/// three side-by-side columns with optional segmented chips and progress rows.
class AdminInsightPanelRow extends StatelessWidget {
  const AdminInsightPanelRow({
    super.key,
    required this.columns,
  });

  final List<AdminInsightColumn> columns;

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980 && columns.length >= 3) {
          final cards = columns.take(3).toList(growable: false);
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_AdminUiTokens.radius),
              border: Border.all(color: AdminAnalyticsColors.border, width: _AdminUiTokens.borderWidth),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  Expanded(child: _AdminInsightColumnCard(column: cards[i], showBorder: false)),
                  if (i != cards.length - 1)
                    const SizedBox(
                      height: 312,
                      child: VerticalDivider(width: 1, thickness: 1, color: AdminAnalyticsColors.border),
                    ),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              _AdminInsightColumnCard(column: columns[i]),
              if (i != columns.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AdminInsightColumnCard extends StatelessWidget {
  const _AdminInsightColumnCard({
    required this.column,
    this.showBorder = true,
  });

  final AdminInsightColumn column;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showBorder ? Border.all(color: AdminAnalyticsColors.border, width: _AdminUiTokens.borderWidth) : null,
        borderRadius: BorderRadius.circular(_AdminUiTokens.radius),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  column.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                ),
              ),
              if (column.onOpenPanel != null)
                IconButton(
                  onPressed: column.onOpenPanel,
                  tooltip: column.openLabel.trim().isEmpty
                      ? 'Open'
                      : column.openLabel,
                  icon: const Icon(Icons.open_in_new, size: 16),
                ),
            ],
          ),
          if (column.segmentLabels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AdminAnalyticsColors.border),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < column.segmentLabels.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: column.onSegmentSelected == null ? null : () => column.onSegmentSelected!(i),
                        borderRadius: BorderRadius.circular(8.5),
                        child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: i == column.activeSegment ? const Color(0xFFECEBFE) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8.5),
                        ),
                        child: Text(
                          column.segmentLabels[i],
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontSize: 12.5,
                                fontWeight: i == column.activeSegment ? FontWeight.w600 : FontWeight.w500,
                              ),
                        ),
                      ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (column.entries.isEmpty)
            Text('No data yet.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AdminAnalyticsColors.muted))
          else
            ...column.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  height: 1.2,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          e.value,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: e.progress.clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: AdminAnalyticsColors.neutralTrack,
                      valueColor: const AlwaysStoppedAnimation<Color>(AdminAnalyticsColors.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

