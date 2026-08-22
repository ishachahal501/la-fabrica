import 'package:flutter/material.dart';
import 'auth_screens.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScreen(role: 'designer', mode: AuthMode.login);
  }
}