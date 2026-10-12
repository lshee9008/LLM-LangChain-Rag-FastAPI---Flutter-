import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';
import 'theme/blues_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chelsea FC Blues Bot',
      debugShowCheckedModeBanner: false,
      theme: bluesTheme(),
      home: const AuthGate(),
    );
  }
}
