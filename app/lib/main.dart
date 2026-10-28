import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/online.dart';
import 'core/palette.dart';
import 'core/storage.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Storage.init();
  if (kIsWeb) {
    final code = Uri.base.queryParameters['room']?.trim().toUpperCase();
    if (code != null && RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) pendingJoinCode = code;
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Palette.bg3,
  ));
  runApp(const StarLudoApp());
}

class StarLudoApp extends StatelessWidget {
  const StarLudoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Star Ludo Royale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Bundled fonts: same look on every device, and no font downloads on the web.
        fontFamily: 'Fredoka',
        fontFamilyFallback: const ['NotoColorEmoji', 'NotoSansSymbols2', 'NotoSansSymbols'],
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bg3,
        colorScheme: ColorScheme.fromSeed(seedColor: Palette.gold2, brightness: Brightness.dark),
      ),
      home: const SplashScreen(),
    );
  }
}
