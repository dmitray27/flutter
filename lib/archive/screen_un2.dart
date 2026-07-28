import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // SharedPreferences для сохранения имени
  late SharedPreferences _prefs;

  // Состояния подключения
  int _connectionState = 0; // 0: Нет WiFi, 1: Подключение, 2: Подключено, 3: Ошибка
  final String _currentWifiName = 'uv82-chat';
  String _lastError = '';
  bool _isConnecting = false;
  Timer? _connectionTimer;

  // Адреса
  String _esp32Address = '192.168.4.1';
  String _deviceIp = '';

  @override
  void initState() {
    super.initState();
    _initPreferences();
  }

  Future<void> _initPreferences() async {
    _prefs = await SharedPreferences.getInstance();

    // Загружаем сохраненное имя, если есть
    final savedName = _prefs.getString('user_name');
    if (savedName != null && savedName.isNotEmpty) {
      _myName = savedName;
    } else {
      // Генерируем новое имя и сохраняем
      _myName = "Tablet_${DateTime.now().millisecondsSinceEpoch % 1000}";
      await _prefs.setString('user_name', _myName);
    }

    setState(() {});

    // Запускаем мониторинг подключения
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

    print('Подключаюсь к ESP32 на $_esp32Address...');

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

      // Настраиваем слушателя
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

      // Пробуем стандартный адрес если текущий не работает
      if (_esp32Address != '192.168.4.1') {
        print('Пробую стандартный адрес 192.168.4.1');
        _esp32Address = '192.168.4.1';
        _connectToEsp32();
        return;
      }

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

  void _showChangeNameDialog() {
    final nameController = TextEditingController(text: _myName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Изменить имя'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Ваше имя в чате',
                  border: OutlineInputBorder(),
                  hintText: 'Введите новое имя',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              Text(
                'Текущее имя: $_myName',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty && newName != _myName) {
                  // Сохраняем в SharedPreferences
                  await _prefs.setString('user_name', newName);

                  setState(() {
                    _myName = newName;
                  });

                  // Отправляем новое имя на ESP32 если подключены
                  if (_connectionState == 2) {
                    _sendUserName();
                  }

                  Navigator.pop(context);
                  _showSnackBar('Имя изменено на: $newName');
                } else if (newName.isEmpty) {
                  _showSnackBar('Имя не может быть пустым');
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  String _getConnectionStateText() {
    switch (_connectionState) {
      case 0: return 'Нет подключения';
      case 1: return 'Подключение...';
      case 2: return 'Подключено';
      case 3: return 'Ошибка';
      default: return 'Неизвестно';
    }
  }

  Color _getConnectionStateColor() {
    switch (_connectionState) {
      case 0: return Colors.red;
      case 1: return Colors.orange;
      case 2: return Colors.green;
      case 3: return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getConnectionStateIcon() {
    switch (_connectionState) {
      case 0: return Icons.wifi_off;
      case 1: return Icons.wifi_find;
      case 2: return Icons.wifi;
      case 3: return Icons.error;
      default: return Icons.wifi_off;
    }
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
          // Единственная кнопка изменения имени (карандаш/ручка)
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showChangeNameDialog,
            tooltip: 'Изменить имя',
          ),
          // Кнопка переподключения
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
                      if (_connectionState == 2)
                        Text(
                          'Ваше имя: $_myName',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ),
                if (_connectionState == 3)
                  TextButton(
                    onPressed: _connectToEsp32,
                    child: const Text('Повторить'),
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