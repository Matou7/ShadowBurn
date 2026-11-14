// lib/widgets/system_dialog.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';

class SystemDialog extends StatelessWidget {
  final String title;
  final String message;
  final Widget? content;
  final List<Widget>? actions;
  final Color color;
  final bool isWarning;

  const SystemDialog({
    super.key,
    this.title = "NOTIFICATION",
    this.message = "",
    this.content,
    this.actions,
    this.color = const Color(0xFF00E5FF),
    this.isWarning = false,
  });

  static void show(BuildContext context, {
    String title = "NOTIFICATION",
    String message = "",
    Widget? content,
    List<Widget>? actions,
    Color color = const Color(0xFF00E5FF),
    bool isWarning = false,
    bool autoClose = false,
  }) {
    if (!kIsWeb) {
      try {
        AudioService.playSystemNotification();
      } catch (_) {}
    }

    showDialog(
      context: context,
      barrierDismissible: !isWarning,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return SystemDialog(
          title: title,
          message: message,
          content: content,
          actions: actions,
          color: isWarning ? const Color(0xFFFF0000) : color,
          isWarning: isWarning,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;
    
    // Hauteur max disponible pour que le dialogue reste centré et visible au-dessus du clavier
    final maxDialogHeight = screenHeight - keyboardHeight - 50;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight > 220 ? maxDialogHeight : 220,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.6),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 5)
                ],
              ),
              child: Container(
                color: const Color(0xFF050505),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // En-tête du dialogue
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.2), Colors.transparent],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter
                        ),
                        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 2),
                            ),
                            child: Icon(
                              isWarning ? Icons.priority_high : Icons.notifications,
                              color: color, size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: color.withValues(alpha: 0.7)),
                                color: Colors.black,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  title.toUpperCase(),
                                  style: GoogleFonts.orbitron(
                                    color: color,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    shadows: [Shadow(color: color, blurRadius: 15)]
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Contenu défilable si les champs dépassent
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.isNotEmpty)
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.rajdhani(
                                  color: Colors.white,
                                  fontSize: 16,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (content != null) ...[
                              if (message.isNotEmpty) const SizedBox(height: 15),
                              content!,
                            ],
                          ],
                        ),
                      ),
                    ),
                    // Actions en bas
                    if (actions != null && actions!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border(top: BorderSide(color: color.withValues(alpha: 0.3))),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 8,
                          children: actions!.map((w) => ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: w,
                            ),
                          )).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(top: -2, left: -2, child: _Corner(color: color)),
            Positioned(top: -2, right: -2, child: RotatedBox(quarterTurns: 1, child: _Corner(color: color))),
            Positioned(bottom: -2, left: -2, child: RotatedBox(quarterTurns: 3, child: _Corner(color: color))),
            Positioned(bottom: -2, right: -2, child: RotatedBox(quarterTurns: 2, child: _Corner(color: color))),
          ],
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final Color color;
  const _Corner({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: 4),
          left: BorderSide(color: color, width: 4),
        )
      ),
    );
  }
}