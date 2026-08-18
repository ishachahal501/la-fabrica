import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(LaFabricaApp());
}

class LaFabricaApp extends StatelessWidget {
  const LaFabricaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Fabrica',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: LoginScreen(), // In a real app, check for token on startup
      routes: {
        '/login': (context) => LoginScreen(),
        '/dashboard': (context) => DashboardScreen(),
      },
    );
  }
}