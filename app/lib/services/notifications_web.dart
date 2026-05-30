// 웹 빌드용 no-op stub — dart:io / Firebase 미지원 플랫폼에서 사용

import 'api.dart';

/// 웹에서는 FCM 을 사용하지 않으므로 no-op.
Future<void> initNotifications(ApiService api) async {}
