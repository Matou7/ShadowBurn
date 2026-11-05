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

    showGeneralDialog(
      context: context,
      barrierDismissible: !isWarning,
      barrierLabel: "Fermer",
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return SystemDialog(
          title: title,
          message: message,
          content: content,
          actions: actions,
          color: isWarning ? const Color(0xFFFF0000) : color,
          isWarning: isWarning,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ),
          alignment: Alignment.center,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Évite que le clavier Android ne masque les boutons (ex: saisie Admin)
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(15),
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
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
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
                              color: color, size: 20,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 15),
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                    shadows: [Shadow(color: color, blurRadius: 15)]
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(25, 30, 25, 30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.isNotEmpty)
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.rajdhani(
                                  color: Colors.white,
                                  fontSize: 18,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (content != null) ...[
                              if (message.isNotEmpty) const SizedBox(height: 20),
                              content!,
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border(top: BorderSide(color: color.withValues(alpha: 0.3))),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 15,
                          runSpacing: 10,
                          children: actions!.map((w) => ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
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