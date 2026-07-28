import 'package:flutter/material.dart';
import 'screen_un2_2.dart'; // ← подключаем экран чата
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация window_manager
  await windowManager.ensureInitialized();

  // Установка размеров окна
  const WindowOptions windowOptions = WindowOptions(
    size: Size(400,600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  // Ожидание готовности и показ окна
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Устанавливаем фиксированный размер окна
    await windowManager.setMinimumSize(const Size(400, 600));
    await windowManager.setMaximumSize(const Size(400, 600));
    await windowManager.setSize(const Size(400,600));
    await windowManager.setResizable(false);
    
    await windowManager.show();
    await windowManager.focus();
    
    // Корректируем размер еще раз после показа
    await windowManager.setSize(const Size(400,600));
    
    // Добавляем слушатель изменений размера окна
    windowManager.addListener(WindowSizeListener());
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UV-82 Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ChatScreen(), // ← указываем ChatScreen как главный экран
    );
  }
}

class WindowSizeListener extends WindowListener {
  @override
  void onWindowResize() {
    // Принудительно устанавливаем размер окна 400x600 при любом изменении размера
    windowManager.setSize(const Size(400, 600));
    //windowManager.setMinimumSize(const Size(400, 600));
    //windowManager.setMaximumSize(const Size(400, 600));
    
    // Дополнительная проверка через небольшую задержку
    Future.delayed(const Duration(milliseconds: 10), () {
      windowManager.setSize(const Size(400, 600));
    });
  }
  
  @override
  void onWindowMove() {
    // Также проверяем размер при перемещении окна
    windowManager.setSize(const Size(400, 600));
    
    // Дополнительная проверка через небольшую задержку
    Future.delayed(const Duration(milliseconds: 10), () {
      windowManager.setSize(const Size(400, 600));
    });
  }
  
  @override
  void onWindowFocus() {
    // Проверяем размер при получении фокуса
    windowManager.setSize(const Size(400, 600));
  }
  
  @override
  void onWindowBlur() {
    // Проверяем размер при потере фокуса
    windowManager.setSize(const Size(400, 600));
  }
}
