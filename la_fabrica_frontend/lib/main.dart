import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/auth_screens.dart';
import 'screens/designer_dashboard.dart';
import 'screens/designer_inventory_screen.dart';
import 'screens/inventory_dashboard_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(const LaFabricaApp());
}

class LaFabricaApp extends StatelessWidget {
  const LaFabricaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Fabrica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff6f5f1),
        colorScheme: const ColorScheme.light(
          primary: Color(0xff171817),
          surface: Color(0xfff6f5f1),
        ),
        fontFamily: 'Arial',
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final path = settings.name ?? '/';

        switch (path) {
          case '/':
            return MaterialPageRoute(builder: (_) => const HomeScreen());

          case '/designer/login':
            return MaterialPageRoute(
              builder: (_) => const AuthScreen(role: 'designer', mode: AuthMode.login),
            );

          case '/designer/register':
            return MaterialPageRoute(
              builder: (_) => const AuthScreen(role: 'designer', mode: AuthMode.register),
            );

          case '/inventory/login':
            return MaterialPageRoute(
              builder: (_) => const AuthScreen(role: 'inventory', mode: AuthMode.login),
            );

          case '/inventory/register':
            return MaterialPageRoute(
              builder: (_) => const AuthScreen(role: 'inventory', mode: AuthMode.register),
            );

          case '/designer':
            return MaterialPageRoute(
              builder: (_) => const ProtectedRoute(
                requiredRole: 'designer',
                child: DesignerDashboard(),
              ),
            );

          case '/designer/inventory':
            return MaterialPageRoute(
              builder: (_) => const ProtectedRoute(
                requiredRole: 'designer',
                child: DesignerInventoryScreen(),
              ),
            );

          case '/inventory':
            return MaterialPageRoute(
              builder: (_) => const ProtectedRoute(
                requiredRole: 'inventory',
                child: InventoryDashboardScreen(),
              ),
            );

          default:
            return MaterialPageRoute(builder: (_) => const HomeScreen());
        }
      },
    );
  }
}

class ProtectedRoute extends StatefulWidget {
  const ProtectedRoute({
    super.key,
    required this.requiredRole,
    required this.child,
  });

  final String requiredRole;
  final Widget child;

  @override
  State<ProtectedRoute> createState() => _ProtectedRouteState();
}

class _ProtectedRouteState extends State<ProtectedRoute> {
  final ApiService _apiService = ApiService();
  bool _isChecking = true;
  bool _isAllowed = false;
  String? _redirectRoute;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await _apiService.getToken();

    if (token == null || token.isEmpty) {
      _redirectRoute = widget.requiredRole == 'designer' ? '/designer/login' : '/inventory/login';
      _isAllowed = false;
    } else {
      final user = await _apiService.getCurrentUser();
      if (user == null) {
        // MongoDB session is invalid or deleted -> clear local token & redirect
        await _apiService.logout();
        _redirectRoute = widget.requiredRole == 'designer' ? '/designer/login' : '/inventory/login';
        _isAllowed = false;
      } else {
        final role = user['role']?.toString();
        if (role != widget.requiredRole) {
          _redirectRoute = role == 'designer' ? '/designer' : '/inventory';
          _isAllowed = false;
        } else {
          _isAllowed = true;
        }
      }
    }

    if (mounted) {
      setState(() => _isChecking = false);
      if (!_isAllowed && _redirectRoute != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushNamedAndRemoveUntil(context, _redirectRoute!, (r) => false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xfff6f5f1),
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    if (!_isAllowed) {
      return const Scaffold(
        backgroundColor: Color(0xfff6f5f1),
        body: Center(child: Text('Redirecting to login...')),
      );
    }

    return widget.child;
  }
}
