import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:radiochat/chat_connection.dart';
import 'package:radiochat/chat_protocol.dart';
import 'package:radiochat/message_store.dart';

class AuditSocket implements ChatSocket {
  final controller = StreamController<String>();
  bool closed = false;

  @override
  Stream get frames => controller.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  void send(String frame) {}

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

void main() {
  test(
      'a different sender with the same id must not confirm my pending message',
      () {
    final store = MessageStore();
    final own = store.addOutgoing('shared1', 'Alice', 'My text');
    final outcome = store.ingest(
      parseIncomingFrame('Bob:shared1:Other text'),
      myName: 'Alice',
    );
    expect(outcome, IngestOutcome.addedNew);
    expect(own.status, MessageStatus.sending);
    expect(store.messages.length, 2);
  });

  test('late echo after changing my name must restore the original message',
      () {
    final store = MessageStore();
    final own = store.addOutgoing('late1', 'Alice', 'Hello');
    store.failAllPending();
    final outcome = store.ingest(
      parseIncomingFrame('hist:Alice:late1:Hello'),
      myName: 'Bob',
    );
    expect(outcome, IngestOutcome.echoConfirmed);
    expect(own.status, MessageStatus.delivered);
    expect(store.messages.length, 1);
  });

  test('renaming must not match a different sender against old own messages',
      () {
    final store = MessageStore();
    final own = store.addOutgoing('shared2', 'Alice', 'Old text');
    store.failAllPending();
    final outcome = store.ingest(
      parseIncomingFrame('Bob:shared2:New text'),
      myName: 'Bob',
    );
    expect(outcome, IngestOutcome.addedNew);
    expect(own.status, MessageStatus.failed);
  });

  test('new board history after reboot must not disappear on reused rx id', () {
    final store = MessageStore();
    store.ingest(parseIncomingFrame('Remote:r1:Before reboot'),
        myName: 'Alice');
    final outcome = store.ingest(
      parseIncomingFrame('hist:Remote:r1:After reboot'),
      myName: 'Alice',
    );
    expect(outcome, IngestOutcome.addedHistory);
    expect(store.messages.length, 2);
  });

  test('closing during onConnected must tear down and report failure',
      () async {
    final socket = AuditSocket();
    final connection = ChatConnection(socketFactory: () => socket);
    final entered = Completer<void>();
    final release = Completer<void>();
    var disconnected = 0;
    connection.onConnected = () async {
      entered.complete();
      await release.future;
    };
    connection.onDisconnected = () async {
      disconnected++;
    };
    final attempt = connection.connect();
    await entered.future;
    await socket.controller.close();
    release.complete();
    final success = await attempt;
    final wasClosed = socket.closed;
    final notifications = disconnected;
    await connection.disconnect();
    expect(success, isFalse);
    expect(wasClosed, isTrue);
    expect(notifications, 1);
  });
}
