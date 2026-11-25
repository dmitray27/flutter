import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'app_color.dart';
import 'chat_controller.dart';
import 'info_dialog.dart';
import 'svg_icon.dart';
import 'update_service.dart';

class ChatScreen extends StatefulWidget {
  final bool isLinux;
  final ChatController Function()? controllerFactory;

  const ChatScreen({
    super.key,
    required this.isLinux,
    this.controllerFactory,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatController _controller;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  late AppLifecycleState _appLifecycleState;
  bool _restoreKeyboardOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

    _controller = (widget.controllerFactory?.call() ?? ChatController())
      ..onMessageAdded = _scrollToBottom
      ..onSnackBar = _showSnackBar
      ..addListener(_onControllerChanged)
      ..init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService().checkForUpdate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('App lifecycle: $state');
    if (_appLifecycleState == AppLifecycleState.resumed &&
        state != AppLifecycleState.resumed) {
      _restoreKeyboardOnResume = !widget.isLinux &&
          Theme.of(context).platform == TargetPlatform.android &&
          _inputFocusNode.hasFocus &&
          View.of(context).viewInsets.bottom > 0;
    }
    _appLifecycleState = state;
    _controller.setForeground(state == AppLifecycleState.resumed);

    if (state == AppLifecycleState.resumed && _restoreKeyboardOnResume) {
      _restoreKeyboardOnResume = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _appLifecycleState != AppLifecycleState.resumed ||
            !_controller.isConnected ||
            !_inputFocusNode.hasFocus ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        // Android can hide the IME on Home while Flutter keeps field focus.
        // requestFocus() on that same node does nothing; show the current
        // text-input client again, only if its keyboard was open on departure.
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.onMessageAdded = null;
    _controller.onSnackBar = null;
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _textController.dispose();
    _nameController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ============================
  // UI helpers
  // ============================

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildStatusIcon(Message msg, ColorScheme scheme) {
    switch (msg.status) {
      case MessageStatus.sending:
        return Icon(
          Icons.schedule,
          size: 12,
          color: scheme.onSurfaceVariant,
        );
      case MessageStatus.delivered:
        return Icon(
          Icons.done,
          size: 12,
          color: scheme.onSurfaceVariant,
        );
      case MessageStatus.failed:
        return Tooltip(
          message: 'УПТС-РК1 не подтвердил приём',
          child: Icon(
            Icons.error_outline,
            size: 12,
            color: scheme.error,
          ),
        );
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
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
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ============================
  // Actions
  // ============================

  Future<void> _send() async {
    if (!_controller.isConnected) return;

    // Keep typing after a send-button tap. Do this before awaiting so a late
    // completion cannot take focus from another field or a disposed screen.
    _inputFocusNode.requestFocus();
    final draft = _textController.text;
    final text = draft.trim();
    if (text.isEmpty) return;

    final sent = await _controller.sendMessage(text);
    if (!mounted) return;
    if (sent && _textController.text == draft) _textController.clear();
  }

  Future<void> _showChangeNameDialog() async {
    _nameController.text = _controller.myName;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Изменить имя'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                maxLength: _controller.maxNameLength,
                decoration: const InputDecoration(
                  labelText: 'Ваше имя в чате',
                  border: OutlineInputBorder(),
                  hintText: 'Введите новое имя',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              Text(
                'Текущее имя: ${_controller.myName}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
                final newName = _nameController.text.trim();
                final error = await _controller.setName(newName);
                if (error != null) {
                  _showSnackBar(error);
                  return;
                }
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  /// Системный «Назад» на Android: спрашиваем, что делать, вместо того
  /// чтобы молча закрыть Activity и оборвать соединение при живом сервисе.
  Future<void> _onBackPressed() async {
    final action = await showDialog<_BackAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Выйти из радиочата?'),
          content: const Text(
            '«Выйти» — приложение закроется, соединение с УПТС-РК1 '
            'разорвётся, уведомление «Радиочат» будет снято, новые '
            'сообщения приходить не будут.\n\n'
            '«Свернуть» — приложение уйдёт в фон, связь с УПТС-РК1 '
            'сохранится, о новых сообщениях будут приходить уведомления.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _BackAction.cancel),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _BackAction.minimize),
              child: const Text('Свернуть'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _BackAction.exit),
              child: const Text('Выйти'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case _BackAction.minimize:
        await _controller.moveToBackground();
        break;
      case _BackAction.exit:
        await _exit();
        break;
      case _BackAction.cancel:
      case null:
        break;
    }
  }

  Future<void> _confirmExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Выйти из радиочата?'),
          content: const Text(
            'Соединение с УПТС-РК1 будет закрыто, уведомления сняты, '
            'новые сообщения приходить не будут.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Выйти'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    debugPrint('App exit: dialog confirmed');
    await _exit();
  }

  Future<void> _exit() async {
    final closedByPlatform = await _controller.exit();
    if (closedByPlatform) return;

    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    } else {
      debugPrint('App exit: closing desktop window');
      await windowManager.close();
    }
  }

  // ============================
  // Build
  // ============================

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColor = AppColor.current.value;
    final isConnected = _controller.isConnected;
    final messages = _controller.messages;

    String statusText = '';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.wifi_off;

    switch (_controller.connectionStatus) {
      case ConnectionStatus.disconnected:
        statusText = _controller.networkHint.isNotEmpty
            ? _controller.networkHint
            : 'Нет подключения';
        statusColor = Colors.red;
        statusIcon = Icons.wifi_off;
        break;
      case ConnectionStatus.connecting:
        statusText = 'Подключение к УПТС-РК1...';
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_find;
        break;
      case ConnectionStatus.connected:
        statusText = 'Подключено к УПТС-РК1';
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        break;
      case ConnectionStatus.error:
        statusText = _controller.connectionError;
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
    }

    final body = Column(
      children: [
        if (widget.isLinux)
          Container(
            height: 32,
            color: scheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      padding: const EdgeInsets.only(left: 12),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Radiochat Core',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(Icons.minimize, size: 16),
                  onPressed: () => windowManager.minimize(),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
        Expanded(
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              titleSpacing: 0,
              leading: InfoButton(color: appColor.onBar.withValues(alpha: 0.6)),
              title: SizedBox(
                width: double.infinity,
                child: Text(
                  'Радиочат',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: appColor.onBar),
                ),
              ),
              backgroundColor: appColor.barColor,
              actions: [
                IconButton(
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 36),
                  icon: SvgIcon(
                    _controller.soundEnabled ? 'bell' : 'bell-off',
                    size: 20,
                    color: appColor.onBar.withValues(alpha: 0.7),
                  ),
                  onPressed: _controller.toggleSound,
                  tooltip: _controller.soundEnabled
                      ? 'Выключить звук'
                      : 'Включить звук',
                  color: appColor.onBar.withValues(alpha: 0.7),
                ),
                IconButton(
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 36),
                  icon: SvgIcon(
                    'theme',
                    size: 20,
                    color: appColor.onBar.withValues(alpha: 0.7),
                  ),
                  onPressed: () => showColorDialog(context),
                  tooltip: 'Цвет приложения',
                  color: appColor.onBar.withValues(alpha: 0.7),
                ),
                IconButton(
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 36),
                  icon: SvgIcon(
                    'rename',
                    size: 20,
                    color: appColor.onBar.withValues(alpha: 0.7),
                  ),
                  onPressed: _showChangeNameDialog,
                  tooltip: 'Изменить имя',
                  color: appColor.onBar.withValues(alpha: 0.7),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    visualDensity:
                        const VisualDensity(horizontal: -4, vertical: -4),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 36),
                    icon: SvgIcon(
                      'exit',
                      size: 20,
                      color: appColor.onBar.withValues(alpha: 0.7),
                    ),
                    onPressed: _confirmExit,
                    tooltip: 'Выйти',
                    color: appColor.onBar.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: statusColor.withAlpha(26),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'WiFi: ${_controller.currentWifiName} • IP: ${_controller.deviceIp}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (isConnected)
                              Text(
                                'Ваше имя: ${_controller.myName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            if (_controller.notificationsDenied)
                              Text(
                                'Уведомления запрещены: в фоне сообщения не видны',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_controller.connectionStatus ==
                              ConnectionStatus.error ||
                          _controller.connectionStatus ==
                              ConnectionStatus.disconnected)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: statusColor,
                            side: BorderSide(color: statusColor),
                          ),
                          onPressed: _controller.isBusy
                              ? null
                              : () => _controller.reconnect(),
                          child: _controller.isBusy
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: statusColor,
                                  ),
                                )
                              : const Text('Подключить'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isConnected
                                    ? Icons.chat_bubble_outline
                                    : statusIcon,
                                size: 64,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isConnected
                                    ? 'Нет сообщений\nОтправьте первое сообщение'
                                    : 'Подключитесь к УПТС-РК1',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[messages.length - 1 - index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              alignment: msg.isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: msg.isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.from,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: msg.isMe
                                          ? scheme.primary
                                          : scheme.tertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.75,
                                    ),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: msg.isMe
                                          ? scheme.primaryContainer
                                          : scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          msg.text,
                                          style: TextStyle(
                                            color: msg.isMe
                                                ? scheme.onPrimaryContainer
                                                : scheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTime(msg.timestamp),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (msg.isMe) ...[
                                              const SizedBox(width: 4),
                                              _buildStatusIcon(msg, scheme),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _inputFocusNode,
                          enabled: isConnected,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: _controller.maxMessageLength,
                          buildCounter: (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) {
                            return Text(
                              '$currentLength/$maxLength',
                              style: const TextStyle(fontSize: 11),
                            );
                          },
                          textInputAction: TextInputAction.send,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText: isConnected
                                ? 'Введите сообщение...'
                                : 'Нет связи с УПТС-РК1',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.send, size: 20),
                              onPressed: isConnected ? _send : null,
                            ),
                          ),
                          // A chat send is not the end of editing. The default
                          // send action unfocuses the field before onSubmitted.
                          onEditingComplete: _textController.clearComposing,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: body,
    );
  }
}

enum _BackAction { cancel, minimize, exit }
