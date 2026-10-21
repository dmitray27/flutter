import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:radiochat/chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingNotifications extends Fake
    implements FlutterLocalNotificationsPlugin {
  InitializationSettings? settings;
  final shown = <NotificationDetails?>[];
  bool? initializeResult = true;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    settings = initializationSettings;
    return initializeResult;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shown.add(notificationDetails);
  }
}

class RecordingAudio extends Fake implements AudioPlayer {
  int plays = 0;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
  }
}

class NotificationSocket implements ChatSocket {
  final controller = StreamController<String>();

  @override
  Stream get frames => controller.stream;

  @override
  Future<void> get ready async {}

  @override
  void send(String frame) {}

  @override
  Future<void> close() => controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatController controller;
  late RecordingNotifications notifications;
  late RecordingAudio audio;
  late NotificationSocket socket;

  setUp(() {
    SharedPreferences.setMockInitialValues({'user_name': 'Test'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/network_info'),
      (call) async => '192.168.4.2',
    );
    notifications = RecordingNotifications();
    audio = RecordingAudio();
    socket = NotificationSocket();
    controller = ChatController(
      httpClient: MockClient((request) async => http.Response(
          request.url.path == '/info'
              ? '{"ssid":"AFSK-TRX-TEST","ip":"192.168.4.1"}'
              : 'pong',
          200)),
      socketFactory: () => socket,
      notifications: notifications,
      notificationPlayer: audio,
    );
  });

  tearDown(() async {
    await controller.exit();
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/network_info'), null);
  });

  Future<void> start() async {
    await controller.init();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isConnected, isTrue);
  }

  Future<void> receive(String id) async {
    socket.controller.add('Remote:$id:RFRemote: hello');
    await Future<void>.delayed(Duration.zero);
  }

  test('initializes Linux and Android notification settings', () async {
    await start();
    expect(notifications.settings?.android, isNotNull);
    expect(notifications.settings?.linux?.defaultActionName, isNotEmpty);
    expect(notifications.settings?.linux?.defaultSuppressSound, isTrue);
  });

  test('Linux background reception shows notification and plays sound once',
      () async {
    await start();
    controller.setForeground(false);
    await receive('r1');
    expect(controller.messages, hasLength(1));
    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single?.linux?.suppressSound, isTrue);
    expect(audio.plays, 1);
    await receive('r1');
    expect(notifications.shown, hasLength(1));
    expect(audio.plays, 1);
  }, skip: !Platform.isLinux);

  test('Linux foreground reception plays sound without a popup', () async {
    await start();
    await receive('r2');
    expect(audio.plays, 1);
    expect(notifications.shown, isEmpty);
  }, skip: !Platform.isLinux);

  test('muted Linux background reception still shows a silent notification',
      () async {
    SharedPreferences.setMockInitialValues(
        {'user_name': 'Test', 'sound_enabled': false});
    await start();
    controller.setForeground(false);
    await receive('r3');
    expect(audio.plays, 0);
    expect(notifications.shown.single?.linux?.suppressSound, isTrue);
  }, skip: !Platform.isLinux);

  test('unsuccessful initialization does not attempt to show notifications',
      () async {
    notifications.initializeResult = false;
    await start();
    controller.setForeground(false);
    await receive('r4');
    expect(notifications.shown, isEmpty);
    expect(audio.plays, 1);
  }, skip: !Platform.isLinux);
}
