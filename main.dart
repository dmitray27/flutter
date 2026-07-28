import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'screen_pro.dart';

// Условный импорт для window_manager
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация window_manager ТОЛЬКО для Linux
  if (Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(400, 800),
        center: true,
        minimumSize: Size(400, 800),
        maximumSize: Size(400, 800),
        titleBarStyle: TitleBarStyle.hidden,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

    } catch (e) {
      print('WindowManager error: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isLinux = Platform.isLinux;

    return MaterialApp(
      title: 'UV-82 Chat',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        // БЕЗ AppBar для Android - чистый ChatScreen
        appBar: null,

        body: Column(
          children: [
            // Панель заголовка ТОЛЬКО для Linux
            if (isLinux)
              Container(
                height: 32,
                color: Colors.grey[300],
                child: Row(
                  children: [
                    // Заголовок
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        child: const Text(
                          'UV-82 Chat',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    // Кнопки управления окном
                    IconButton(
                      icon: const Icon(Icons.minimize, size: 16),
                      onPressed: () => windowManager.minimize(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => windowManager.close(),
                    ),
                  ],
                ),
              ),

            // Ваш оригинальный ChatScreen на весь экран
            const Expanded(
              child: ChatScreen(),
            ),
          ],
        ),
      ),
    );
  }
}