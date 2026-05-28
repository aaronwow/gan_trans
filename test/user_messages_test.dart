import 'dart:async';
import 'dart:io';

import 'package:ai_chat/user_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps credential errors to actionable copy', () {
    expect(
      compactUserError(Exception('OpenAI API key is empty')),
      contains('缺少 API key'),
    );
  });

  test('maps timeout errors to retry copy', () {
    expect(
      compactUserError(TimeoutException('request timed out')),
      contains('请求超时'),
    );
  });

  test('maps auth and quota statuses', () {
    expect(compactUserError(Exception('401 Unauthorized')), contains('认证失败'));
    expect(compactUserError(Exception('403 Forbidden')), contains('没有权限'));
    expect(
      compactUserError(Exception('429 Too Many Requests')),
      contains('请求过于频繁'),
    );
  });

  test('maps network and speech recognition failures', () {
    expect(
      compactUserError(const SocketException('failed host lookup')),
      contains('网络连接失败'),
    );
    expect(
      compactUserError(Exception('code=20000003 no valid speech')),
      contains('没有识别到有效语音'),
    );
  });

  test('keeps raw details in expanded message', () {
    final text = expandedUserError(Exception('provider raw body'));

    expect(text, contains('操作失败'));
    expect(text, contains('详情：Exception: provider raw body'));
  });
}
