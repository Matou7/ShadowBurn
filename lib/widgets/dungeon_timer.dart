// lib/widgets/dungeon_timer.dart

import 'dart:async';
import 'package:flutter/material.dart';

class DungeonTimer extends StatefulWidget {
  final DateTime expiresAt;
  final VoidCallback? onExpired;
  final TextStyle? style;

  const DungeonTimer({
    super.key,
    required this.expiresAt,
    this.onExpired,
    this.style,
  });

  @override
  State<DungeonTimer> createState() => _DungeonTimerState();
}

class _DungeonTimerState extends State<DungeonTimer> {
  late Timer _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateTime();
    });
  }

  void _calculateTime() {
    final now = DateTime.now();
    if (now.isAfter(widget.expiresAt)) {
      _timer.cancel();
      if (!mounted) return;
      setState(() {
        _timeLeft = Duration.zero;
      });
      if (widget.onExpired != null) {
        widget.onExpired!();
      }
    } else {
      if (!mounted) return;
      setState(() {
        _timeLeft = widget.expiresAt.difference(now);
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String hours = twoDigits(_timeLeft.inHours);
    String minutes = twoDigits(_timeLeft.inMinutes.remainder(60));
    String seconds = twoDigits(_timeLeft.inSeconds.remainder(60));

    Color timerColor = (widget.style?.color) ?? Colors.white;
    if (_timeLeft.inMinutes < 10) timerColor = Colors.redAccent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer, size: 16, color: timerColor),
        const SizedBox(width: 5),
        Text(
          "$hours:$minutes:$seconds",
          style: (widget.style ?? const TextStyle()).copyWith(
            color: timerColor,
            fontFamily: "monospace",
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}