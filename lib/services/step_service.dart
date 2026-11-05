// lib/services/step_service.dart

import 'dart:async';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/log.dart';

class StepEvent {
  final int delta;
  final bool live;
  const StepEvent(this.delta, this.live);
}

class StepService {
  StreamSubscription<StepCount>? _sub;
  int? _baseline;
  void Function(StepEvent event)? _onEvent;

  int? get baseline => _baseline;

  Future<void> configure({required int? baseline, required void Function(StepEvent event) onEvent}) async {
    _onEvent = onEvent;
    
    final prefs = await SharedPreferences.getInstance();
    final int? diskBaseline = prefs.getInt('shadow_step_baseline');

    if (baseline != null) {
      _baseline = baseline;
    } else if (diskBaseline != null && diskBaseline > 0) {
      _baseline = diskBaseline;
    }
  }

  void start() {
    if (_sub != null) return;
    _sub = Pedometer.stepCountStream.listen(
      _handle,
      onError: (Object e) => dlog("Pédomètre indisponible : $e"),
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> restart() async {
    await stop();
    start();
  }

  Future<void> _handle(StepCount e) async {
    final int raw = e.steps;

    if (_baseline == null || _baseline == 0) {
      _baseline = raw;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('shadow_step_baseline', raw);
      return;
    }

    if (raw < _baseline!) {
      _baseline = raw;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('shadow_step_baseline', raw);
      return;
    }

    final int delta = raw - _baseline!;
    if (delta <= 0) return;

    _baseline = raw;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shadow_step_baseline', raw);

    if (delta > 50000) {
      dlog("Saut de pas suspect ignoré : $delta");
      return;
    }

    _onEvent?.call(StepEvent(delta, true));
  }
}