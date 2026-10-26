import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radiochat/chat_controller.dart';
import 'package:radiochat/screen_pro.dart';

class FocusController extends ChangeNotifier implements ChatController {
  bool connected = false;
  final sent = <String>[];
  Completer<bool>? pendingSend;

  @override
  VoidCallback? onMessageAdded;
  @override
  void Function(String)? onSnackBar;
  @override
  bool get isConnected => connected;
  @override
  ConnectionStatus get connectionStatus =>
      connected ? ConnectionStatus.connected : ConnectionStatus.disconnected;
  @override
  bool get isBusy => false;
  @override
  String get networkHint => '';
  @override
  String get currentWifiName => 'Test AP';
  @override
  String get deviceIp => '192.168.4.2';
  @override
  String get myName => 'Test';
  @override
  bool get soundEnabled => true;
  @override
  bool get notificationsDenied => false;
  @override
  int get maxMessageLength => 75;
  @override
  int get maxNameLength => 7;
  @override
  UnmodifiableListView<Message> get messages => UnmodifiableListView([]);
  @override
  Future<void> init() async {}
  @override
  void setForeground(bool value) {}
  @override
  Future<bool> sendMessage(String text) async {
    sent.add(text);
    return pendingSend == null ? true : await pendingSend!.future;
  }

  void setConnected(bool value) {
    connected = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FocusController controller;

  Future<void> mount(WidgetTester tester) async {
    controller = FocusController();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: ChatScreen(
        isLinux: false,
        controllerFactory: () => controller,
      ),
    ));
    await tester.pumpAndSettle();
  }

  TextField input(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  Future<void> connect(WidgetTester tester) async {
    controller.setConnected(true);
    await tester.pumpAndSettle();
  }

  Future<void> typeWithoutTap(WidgetTester tester, String text) async {
    expect(input(tester).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    // tester.enterText would request the keyboard again and mask a lost
    // input connection, just like the extra tap reported on Android.
    tester.testTextInput.enterText(text);
    await tester.pump();
    expect(input(tester).controller!.text, text);
  }

  testWidgets('keyboard send keeps accepting input while send is pending',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'first');
    controller.pendingSend = Completer<bool>();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await typeWithoutTap(tester, 'next draft');
    controller.pendingSend!.complete(true);
    await tester.pumpAndSettle();
    expect(controller.sent, ['first']);
    expect(input(tester).controller!.text, 'next draft');
    await typeWithoutTap(tester, 'next draft continued');
  });

  testWidgets('Android restores an open keyboard after resume', (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // Android hides the IME on Home without removing Flutter's field focus.
    tester.testTextInput.hide();
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(input(tester).controller!.text, 'draft');
    await typeWithoutTap(tester, 'draft continued');
  });

  testWidgets('resume does not reopen a keyboard hidden before leaving',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    tester.testTextInput.hide();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(input(tester).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(input(tester).controller!.text, 'draft');
  });

  testWidgets('resume does not reopen the keyboard after disconnection',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.testTextInput.hide();
    tester.view.viewInsets = FakeViewPadding.zero;
    controller.setConnected(false);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(input(tester).controller!.text, 'draft');
  });

  testWidgets('empty send action keeps the input focused', (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(controller.sent, isEmpty);
    await typeWithoutTap(tester, 'after empty send');
  });

  testWidgets('button and keyboard sends keep focus and clear sent text',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'first');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(input(tester).controller!.text, isEmpty);
    expect(input(tester).focusNode!.hasFocus, isTrue);
    await typeWithoutTap(tester, 'second');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(input(tester).controller!.text, isEmpty);
    expect(input(tester).focusNode!.hasFocus, isTrue);
    expect(controller.sent, ['first', 'second']);
    await typeWithoutTap(tester, 'third');
  });

  testWidgets('connection and resume do not steal focus from name dialog',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Изменить имя'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'Name');
    await connect(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(input(tester).focusNode!.hasFocus, isFalse);
    expect(editor.controller!.text, 'Name');
    expect(find.text('Изменить имя'), findsOneWidget);
    tester.testTextInput.enterText('Name2');
    await tester.pump();
    expect(editor.controller!.text, 'Name2');
  });

  testWidgets('controller updates do not focus an unfocused input',
      (tester) async {
    await mount(tester);
    await connect(tester);
    input(tester).focusNode!.unfocus();
    await tester.pumpAndSettle();
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(input(tester).focusNode!.hasFocus, isFalse);
  });

  testWidgets('connection does not request a mobile keyboard', (tester) async {
    await mount(tester);
    await connect(tester);
    expect(input(tester).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('failed keyboard send retains text and accepts further input',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'retry');
    controller.pendingSend = Completer<bool>();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    controller.pendingSend!.complete(false);
    await tester.pumpAndSettle();
    expect(input(tester).controller!.text, 'retry');
    await typeWithoutTap(tester, 'retry edited');
  });

  testWidgets('completed send does not take input from the name dialog',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'pending');
    controller.pendingSend = Completer<bool>();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.tap(find.byTooltip('Изменить имя'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'Name');
    controller.pendingSend!.complete(true);
    await tester.pumpAndSettle();
    expect(input(tester).focusNode!.hasFocus, isFalse);
    tester.testTextInput.enterText('Name2');
    await tester.pump();
    expect(editor.controller!.text, 'Name2');
  });

  testWidgets('reconnection allows typing after explicitly opening input',
      (tester) async {
    await mount(tester);
    await connect(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    controller.setConnected(false);
    await tester.pumpAndSettle();
    await connect(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(input(tester).controller!.text, 'draft');
    await typeWithoutTap(tester, 'draft continued');
  });

  testWidgets('send completing after screen disposal does not request focus',
      (tester) async {
    await mount(tester);
    await connect(tester);
    controller.pendingSend = Completer<bool>();
    await tester.enterText(find.byType(TextField), 'pending');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    controller.pendingSend!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
