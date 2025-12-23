import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;

class HelpTooltip extends StatelessWidget {
  const HelpTooltip({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      richMessage: TextSpan(
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
          height: 1.6,
        ),
        children: [
          // Status indicators
          TextSpan(
            text: 'Asset Status:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          WidgetSpan(
            child: Icon(Icons.check_circle, size: 16, color: Colors.green),
          ),
          TextSpan(
            text: ' Green',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
          TextSpan(text: ' - Downloaded\n'),
          WidgetSpan(
            child: Icon(Icons.circle_outlined, size: 16, color: Colors.white),
          ),
          TextSpan(
            text: ' White',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          TextSpan(text: ' - Not downloaded\n'),
          WidgetSpan(
            child: Icon(Icons.warning, size: 16, color: Colors.orange),
          ),
          TextSpan(
            text: ' Orange',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          TextSpan(text: ' - Temporary download failure\n'),
          WidgetSpan(
            child: Icon(Icons.error, size: 16, color: Colors.red),
          ),
          TextSpan(
            text: ' Red',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          TextSpan(text: ' - Permanent download failure\n'),
          TextSpan(
            text: '• Blue',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
          ),
          TextSpan(text: ' - Last selected URL\n'),
          WidgetSpan(
            child: Icon(Icons.backup, size: 16, color: Colors.blue),
          ),
          TextSpan(
            text: ' Blue Border',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          TextSpan(text: ' - Asset is backed up\n\n'),

          TextSpan(
            text: 'Note:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: '• Assets can be backed up even if not currently downloaded\n'
                 '• Backup state is preserved even if URLs become invalid\n'
                 '• Blue border indicates the asset exists in at least one backup\n\n',
          ),

          // Actions
          TextSpan(
            text: 'Actions:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: '• Click a URL to see options\n'),
          TextSpan(
              text:
                  '• Download button: Attempts to download all missing asset files\n'),
          TextSpan(
              text:
                  '• Retry Download: Attempts to re-download failed assets\n'),
          TextSpan(
              text:
                  '• Backup button: Creates a backup (even with missing asset files)\n'),
          TextSpan(text: '• Cancel button: Cancels downloads'),
        ],
      ),
      child: Icon(
        Icons.info_outline,
        size: 26,
      ),
    );
  }
}
