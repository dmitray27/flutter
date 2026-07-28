import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:convert';
import 'dart:async';

class Message {
  final String from;
  final String text;
  final bool isMe;
  final DateTime timestamp;

  Message(this.from, this.text, this.isMe, {DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  String _myName = "User";
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _webSocketChannel;
  StreamSubscription? _webSocketSubscription;

  // Состояния подключения
  int _connectionState = 0; // 0: Нет WiFi, 1: Подключение, 2: Подключено, 3: Ошибка
  final String _currentWifiName = 'uv82-chat';
  String _lastError = '';
  bool _isConnecting = false;
  Timer? _connectionTimer;

  // Адреса
  final String _esp32Address = '192.168.4.1';
  String _deviceIp = '';

  @override
  void initState() {
    super.initState();
    _myName = "Tablet_${DateTime.now().millisecondsSinceEpoch % 1000}";
    _startConnectionMonitoring();
  }

  void _startConnectionMonitoring() {
    // Проверяем каждые 2 секунды
    _connectionTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkConnection();
    });

    // Первая проверка
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    try {
      final networkInfo = NetworkInfo();

      String? deviceIp = await networkInfo.getWifiIP();

      setState(() {
        _deviceIp = deviceIp ?? '';
      });

      // Проверяем, в сети ли ESP32
      bool isInEsp32Network = _deviceIp.startsWith('192.168.4.');

      if (!isInEsp32Network || _deviceIp.isEmpty) {
        if (_connectionState != 0) {
          _disconnect();
          setState(() {
            _connectionState = 0;
            _lastError = 'Подключитесь к WiFi ESP32';
          });
        }
        return;
      }

      // Если в сети ESP32, но не подключены
      if (_connectionState == 0 && !_isConnecting) {
        _connectToEsp32();
      }

    } catch (e) {
      print('Ошибка проверки: $e');
    }
  }

  Future<void> _connectToEsp32() async {
    if (_isConnecting) return;

    _isConnecting = true;
    setState(() {
      _connectionState = 1;
      _lastError = 'Подключение...';
    });

    print('Подключаюсь к ESP32...');

    try {
      // Закрываем старое соединение
      await _disconnect();

      // Проверяем доступность ESP32
      print('Проверяю ping ESP32...');
      final response = await http.get(
        Uri.parse('http://$_esp32Address/ping'),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        throw Exception('ESP32 не отвечает');
      }

      print('ESP32 доступен, подключаю WebSocket...');

      // Подключаем WebSocket
      _webSocketChannel = IOWebSocketChannel.connect(
        'ws://$_esp32Address:81',
        pingInterval: const Duration(seconds: 15),
      );

      // СНАЧАЛА настраиваем слушателя, ПОТОМ ждем
      _webSocketSubscription = _webSocketChannel!.stream.listen(
            (message) {
          print('📥 WebSocket: $message');
          _processIncomingMessage(message.toString());
        },
        onError: (error) {
          print('❌ WebSocket ошибка: $error');
          if (_connectionState != 0) {
            _handleConnectionError('WebSocket ошибка');
          }
        },
        onDone: () {
          print('🔌 WebSocket закрыт');
          if (_connectionState != 0) {
            _handleConnectionError('Соединение закрыто');
          }
        },
      );

      // Даем время на установку соединения
      await Future.delayed(const Duration(milliseconds: 500));

      // Успешное подключение
      setState(() {
        _connectionState = 2;
        _lastError = '';
      });

      print('✅ Успешно подключено к ESP32');

      // Отправляем имя
      _sendUserName();

      _showSnackBar('Подключено к ESP32');

    } catch (e) {
      print('❌ Ошибка подключения: $e');
      _handleConnectionError(e.toString());
    } finally {
      _isConnecting = false;
    }
  }

  void _sendUserName() {
    if (_webSocketChannel != null && _connectionState == 2) {
      try {
        _webSocketChannel!.sink.add('setName:$_myName');
        print('Отправлено имя: $_myName');
      } catch (e) {
        print('Ошибка отправки имени: $e');
      }
    }
  }

  void _processIncomingMessage(String message) {
    message = message.trim();
    if (message.isEmpty) return;

    print('Обработка сообщения: $message');

    if (message.startsWith('System:')) {
      // Системное сообщение показываем как уведомление
      String sysMsg = message.substring(7);
      if (sysMsg.contains('подключился') || sysMsg.contains('изменено')) {
        // Эти сообщения не показываем
        return;
      }
      _showSnackBar(sysMsg);
      return;
    }

    // Разбираем обычное сообщение
    final colonIndex = message.indexOf(':');
    if (colonIndex > 0 && colonIndex < message.length - 1) {
      final from = message.substring(0, colonIndex);
      final text = message.substring(colonIndex + 1).trim();

      if (from != _myName) {
        setState(() {
          _messages.add(Message(from, text, false));
        });
        _scrollToBottom();
      }
    }
  }

  void _handleConnectionError(String error) {
    print('Обработка ошибки подключения');

    setState(() {
      _connectionState = 3;
      _lastError = 'Потеряно соединение с ESP32';
    });

    // Автоматическое переподключение через 3 секунды
    Future.delayed(const Duration(seconds: 3), () {
      if (_deviceIp.startsWith('192.168.4.') && _connectionState == 3) {
        _connectToEsp32();
      }
    });
  }

  Future<void> _disconnect() async {
    // Отменяем подписку
    if (_webSocketSubscription != null) {
      await _webSocketSubscription!.cancel();
      _webSocketSubscription = null;
    }

    // Закрываем канал
    if (_webSocketChannel != null) {
      try {
        await _webSocketChannel!.sink.close();
      } catch (e) {
        print('Ошибка при закрытии: $e');
      }
      _webSocketChannel = null;
    }

    if (_connectionState != 0) {
      setState(() {
        _connectionState = 0;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _connectionState != 2) return;

    // Добавляем в UI
    setState(() {
      _messages.add(Message(_myName, text, true));
    });

    _textController.clear();
    _scrollToBottom();

    // Отправляем на ESP32
    try {
      print('Отправляю сообщение: $text');

      final response = await http.post(
        Uri.parse('http://$_esp32Address/send'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'from=${Uri.encodeComponent(_myName)}&text=${Uri.encodeComponent(text)}',
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        _showSnackBar('Ошибка отправки');
      }
    } catch (e) {
      print('Ошибка отправки: $e');
      _showSnackBar('Не удалось отправить');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    String statusText = '';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.wifi_off;

    switch (_connectionState) {
      case 0:
        statusText = _lastError.isNotEmpty ? _lastError : 'Нет подключения';
        statusColor = Colors.red;
        statusIcon = Icons.wifi_off;
        break;
      case 1:
        statusText = 'Подключение к ESP32...';
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_find;
        break;
      case 2:
        statusText = 'Подключено к ESP32';
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        break;
      case 3:
        statusText = _lastError;
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('UV-82 Чат'),
        backgroundColor: Colors.green[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _disconnect();
              _connectToEsp32();
            },
            tooltip: 'Переподключиться',
          ),
        ],
      ),
      body: Column(
        children: [
          // Статус бар
          Container(
            padding: const EdgeInsets.all(12),
            color: statusColor.withOpacity(0.1),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                      Text('WiFi: $_currentWifiName • IP: $_deviceIp', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Список сообщений
          Expanded(
            child: _messages.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _connectionState == 2 ? Icons.chat_bubble_outline : statusIcon,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _connectionState == 2
                        ? 'Нет сообщений\nОтправьте первое сообщение'
                        : 'Подключитесь к ESP32',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.from,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: msg.isMe ? Colors.green[900] : Colors.blue[700],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: msg.isMe ? Colors.green[100] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(msg.text),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Поле ввода
          if (_connectionState == 2)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Введите сообщение...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _sendMessage,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    _disconnect();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}