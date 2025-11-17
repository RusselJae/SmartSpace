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
  const AdminToolbar({super.key, required this.title, required this.actions, this.trailing});

  final String title;
  final List<AdminToolbarAction> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: titleStyle)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
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


