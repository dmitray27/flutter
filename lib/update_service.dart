import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';

/// Сервис неблокирующей проверки и гибкого (flexible) обновления
/// приложения через RuStore In-App Update SDK.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();

  factory UpdateService() => _instance;

  UpdateService._internal();

  /// Проверяет наличие обновлений в RuStore и запускает фоновое скачивание.
  Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) return;

    try {
      debugPrint('RuStore Update: проверка наличия обновлений...');
      final info = await RustoreUpdateClient.info();
      debugPrint(
          'RuStore Update info: availability=${info.updateAvailability}, code=${info.availableVersionCode}');

      if (info.updateAvailability == UPDATE_AVAILABILITY_AVAILABLE) {
        debugPrint(
            'RuStore Update: доступна новая версия (${info.availableVersionCode}), запускаем гибкое скачивание...');
        await RustoreUpdateClient.download();
        debugPrint(
            'RuStore Update: скачивание завершено, применяем обновление...');
        await RustoreUpdateClient.completeUpdateFlexible();
      } else {
        debugPrint('RuStore Update: нет доступных обновлений.');
      }
    } catch (e, stack) {
      // В debug/sideload сборках RuStore SDK возвращает ошибку или "нет обновлений" — это нормально
      debugPrint('RuStore Update: сбой проверки или обновление недоступно ($e)');
      if (kDebugMode) {
        debugPrint('Stacktrace: $stack');
      }
    }
  }
}
