import 'dart:async';

import 'package:ai_chat/tts_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancel prevents queued tasks from running', () async {
    final queue = TtsQueue();
    final gate = Completer<void>();
    var ranSecond = false;

    queue.enqueue(() => gate.future);
    queue.enqueue(() async {
      ranSecond = true;
    });

    queue.cancel();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ranSecond, isFalse);
    expect(queue.hasPending, isFalse);
  });
}
