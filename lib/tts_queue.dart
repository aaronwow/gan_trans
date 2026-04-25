import 'dart:async';

import 'package:flutter/foundation.dart';

class TtsQueue {
  Future<void> _chain = Future<void>.value();
  int _generation = 0;
  int _pending = 0;

  bool get hasPending => _pending > 0;

  void enqueue(Future<void> Function() task, {VoidCallback? onIdle}) {
    final prev = _chain;
    final generation = _generation;
    _pending++;
    _chain = () async {
      try {
        await prev;
      } catch (_) {}
      try {
        if (generation != _generation) return;
        await task();
        if (generation != _generation) return;
      } finally {
        _pending = (_pending - 1).clamp(0, 1 << 30);
        onIdle?.call();
      }
    }();
  }

  void cancel() {
    _generation++;
    _chain = Future<void>.value();
    _pending = 0;
  }
}
