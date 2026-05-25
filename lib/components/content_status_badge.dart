import 'package:flutter/material.dart';

class ContentStatusBadge extends StatelessWidget {
  final String status; // 'pending', 'approved', 'rejected'
  final bool showIcon;

  const ContentStatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
  });

  Map<String, dynamic> _getStatusStyle() {
    switch (status.toLowerCase()) {
      case 'pending':
        return {
          'backgroundColor': Colors.orange[100],
          'textColor': Colors.orange[800],
          'icon': Icons.schedule,
          'label': 'Awaiting Approval',
        };
      case 'approved':
        return {
          'backgroundColor': Colors.green[100],
          'textColor': Colors.green[800],
          'icon': Icons.check_circle,
          'label': 'Approved',
        };
      case 'rejected':
        return {
          'backgroundColor': Colors.red[100],
          'textColor': Colors.red[800],
          'icon': Icons.cancel,
          'label': 'Rejected',
        };
      default:
        return {
          'backgroundColor': Colors.grey[100],
          'textColor': Colors.grey[800],
          'icon': Icons.info,
          'label': status,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _getStatusStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style['backgroundColor'],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: style['textColor'].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              style['icon'],
              size: 14,
              color: style['textColor'],
            ),
            const SizedBox(width: 6),
          ],
          Text(
            style['label'],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: style['textColor'],
            ),
          ),
        ],
      ),
    );
  }
}
