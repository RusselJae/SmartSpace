import 'package:flutter/material.dart';

class AdminToolbarAction {
  const AdminToolbarAction({
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
}

class AdminToolbar extends StatelessWidget {
  const AdminToolbar({
    super.key,
    required this.title,
    required this.actions,
    this.trailing,
    this.showTitle = false,
  });

  final String title;
  final List<AdminToolbarAction> actions;
  final Widget? trailing;

  /// When false, the redundant title above search is hidden (page header already shows it).
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    // Skip rendering when there's nothing to show (no title, no actions, no trailing).
    if (!showTitle && actions.isEmpty && trailing == null) {
      return const SizedBox.shrink();
    }

    final TextStyle titleStyle =
        Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTitle || trailing != null)
              Row(
                children: [
                  if (showTitle) Expanded(child: Text(title, style: titleStyle)),
                  if (!showTitle && trailing != null) const Spacer(),
                  if (showTitle && trailing != null) const SizedBox(width: 12),
                  if (trailing != null) trailing!,
                ],
              ),
            if (showTitle || trailing != null) const SizedBox(height: 12),
            if (actions.isNotEmpty)
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: actions.map(_buildActionButton).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(AdminToolbarAction action) {
    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (action.icon != null) ...[
          Icon(action.icon, size: 16),
          const SizedBox(width: 6),
        ],
        Text(action.label),
      ],
    );
    if (action.primary) {
      return FilledButton(
        onPressed: action.onPressed,
        child: label,
      );
    }
    return OutlinedButton(
      onPressed: action.onPressed,
      child: label,
    );
  }
}


