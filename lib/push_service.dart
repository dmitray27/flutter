import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_rustore_push/flutter_rustore_push.dart';
import 'package:flutter_rustore_push/pigeons/rustore_push.dart' as push;

/// Сервис приема Push-уведомлений RuStore (например, о выходе новых версий).
class PushService {
  static final PushService _instance = PushService._internal();

  factory PushService() => _instance;

  PushService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Инициализирует RuStore Push SDK и подписывается на входящие сообщения.
  Future<void> init() async {
    if (!Platform.isAndroid || _initialized) return;

    try {
      debugPrint('RuStore Push: проверка доступности...');
      final available = await RustorePushClient.available();
      if (!available) {
        debugPrint('RuStore Push: недоступен на данном устройстве.');
        return;
      }

      await RustorePushClient.attachCallbacks(
        onNewToken: (String token) {
          debugPrint('RuStore Push Token: $token');
        },
        onMessageReceived: (push.Message message) {
          debugPrint('RuStore Push получен: ${message.messageId}');
          _handleMessage(message);
        },
        onError: (String err) {
          debugPrint('RuStore Push ошибка: $err');
        },
        onMessageOpenedApp: (push.Message? message) {
          debugPrint(
              'RuStore Push открыт пользователем: ${message?.messageId}');
        },
      );

      final token = await RustorePushClient.getToken();
      debugPrint('RuStore Push Token получен: $token');

      _initialized = true;
    } catch (e, stack) {
      debugPrint('RuStore Push: сбой инициализации ($e)');
      if (kDebugMode) {
        debugPrint('Stacktrace: $stack');
      }
    }
  }

  void _handleMessage(push.Message message) {
    try {
      final title = message.notification?.title ??
          message.data['title'] ??
          'Доступно обновление';
      final body = message.notification?.body ??
          message.data['body'] ??
          'Вышла новая версия приложения в RuStore.';

      _showSystemNotification(title, body);
    } catch (e) {
      debugPrint('Ошибка обработки входящего push: $e');
    }
  }

  Future<void> _showSystemNotification(String title, String body) async {
    try {
      const details = AndroidNotificationDetails(
        'app_updates',
        'Обновления приложения',
        channelDescription: 'Уведомления о новых версиях приложения в RuStore',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      await _localNotifications.show(
        2001,
        title,
        body,
        const NotificationDetails(android: details),
      );
    } catch (e) {
      debugPrint('Ошибка показа системного уведомления обновления: $e');
    }
  }
}
