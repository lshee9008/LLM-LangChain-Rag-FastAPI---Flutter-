import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';

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
      theme: ThemeData(
        // 첼시 대표 색상(로열 블루) 테마 설정
        primaryColor: const Color(0xFF034694),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF034694)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
