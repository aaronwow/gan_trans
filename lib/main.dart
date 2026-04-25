import 'package:flutter/material.dart';
import 'settings.dart';
import 'chat_screen.dart';

final RouteObserver<PageRoute<void>> routeObserver =
    RouteObserver<PageRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(AiChatApp(settings: settings));
}

class AiChatApp extends StatelessWidget {
  final AppSettings settings;
  const AiChatApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      navigatorObservers: [routeObserver],
      home: ChatScreen(settings: settings),
    );
  }
}
