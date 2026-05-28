class UserFacingError {
  final String summary;
  final String detail;

  const UserFacingError({required this.summary, required this.detail});
}

UserFacingError describeUserError(Object? error, {String fallback = '操作失败'}) {
  if (error == null) {
    return UserFacingError(summary: fallback, detail: '');
  }

  final detail = error.toString();
  final lower = detail.toLowerCase();

  String summary;
  if (lower.contains('cancelled') || lower.contains('canceled')) {
    summary = '已取消';
  } else if (lower.contains('permission denied')) {
    summary = '权限不足，请检查麦克风或系统权限。';
  } else if (lower.contains('api key') ||
      lower.contains('missing api key') ||
      lower.contains('key is empty') ||
      lower.contains('key is not set')) {
    summary = '缺少 API key，请到 Settings 填写 provider 凭证。';
  } else if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('timeoutexception')) {
    summary = '请求超时，请稍后重试或调高超时时间。';
  } else if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection closed') ||
      lower.contains('failed host lookup')) {
    summary = '网络连接失败，请检查网络后重试。';
  } else if (detail.contains('401')) {
    summary = '认证失败，请检查 API key 是否正确。';
  } else if (detail.contains('403')) {
    summary = '当前账号没有权限使用这个模型或 provider。';
  } else if (detail.contains('429')) {
    summary = '请求过于频繁或额度不足，请稍后重试。';
  } else if (_containsServerStatus(detail)) {
    summary = 'provider 服务暂时不可用，请稍后重试。';
  } else if (detail.contains('20000003') ||
      lower.contains('no valid speech') ||
      lower.contains('returned no transcript')) {
    summary = '没有识别到有效语音，请靠近麦克风再试一次。';
  } else {
    summary = fallback;
  }

  return UserFacingError(summary: summary, detail: detail);
}

String compactUserError(Object? error, {String fallback = '操作失败'}) {
  return describeUserError(error, fallback: fallback).summary;
}

String expandedUserError(Object? error, {String fallback = '操作失败'}) {
  final described = describeUserError(error, fallback: fallback);
  if (described.detail.isEmpty || described.detail == described.summary) {
    return described.summary;
  }
  return '${described.summary}\n\n详情：${described.detail}';
}

bool _containsServerStatus(String detail) {
  for (final code in ['500', '502', '503', '504']) {
    if (detail.contains(code)) return true;
  }
  return false;
}
