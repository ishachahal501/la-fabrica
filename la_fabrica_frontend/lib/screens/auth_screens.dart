import 'package:flutter/material.dart';
import '../services/api_service.dart';

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.role,
    required this.mode,
  });

  final String role; // 'designer' or 'inventory'
  final AuthMode mode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _inviteCodeController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) return;

    if (widget.mode == AuthMode.register &&
        _passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() => _isLoading = true);

    Map<String, dynamic> res;
    if (widget.mode == AuthMode.register) {
      res = await _apiService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: widget.role,
        inviteCode: widget.role == 'inventory' ? _inviteCodeController.text.trim() : null,
      );
    } else {
      res = await _apiService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        expectedRole: widget.role,
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    final statusCode = res['statusCode'] ?? 200;
    if (statusCode >= 200 && statusCode < 300 && res['token'] != null) {
      // Redirect based on role
      final targetRoute = widget.role == 'designer' ? '/designer' : '/inventory';
      Navigator.pushNamedAndRemoveUntil(context, targetRoute, (route) => false);
    } else {
      setState(() {
        _errorMessage = res['message'] ?? 'Authentication failed. Please check details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesigner = widget.role == 'designer';
    final isRegister = widget.mode == AuthMode.register;
    final roleTitle = isDesigner ? 'DESIGNER PORTAL' : 'INVENTORY MANAGEMENT';
    final title = isRegister ? 'Create Account' : 'Welcome Back';

    return Scaffold(
      backgroundColor: const Color(0xfff6f5f1),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with La Fabrica Branding
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
                    child: const Row(
                      children: [
                        Text('LA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -1, color: Color(0xff171817))),
                        SizedBox(width: 5),
                        Text('FÁBRICA', style: TextStyle(fontWeight: FontWeight.w300, fontSize: 24, letterSpacing: -1, color: Color(0xff171817))),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/'),
                    icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xff171817)),
                    label: const Text('Back to Home', style: TextStyle(color: Color(0xff171817), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xffe2e0d8)),

            // Form Content
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xffe2e0d8)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDesigner ? const Color(0xffd9ee57) : const Color(0xff171817),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    roleTitle,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color: isDesigner ? Colors.black : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                color: Color(0xff171817),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isRegister
                                  ? 'Enter your details to register as ${widget.role}.'
                                  : 'Sign in to access your ${widget.role} dashboard.',
                              style: const TextStyle(fontSize: 14, color: Color(0xff74756f)),
                            ),
                            const SizedBox(height: 28),

                            if (_errorMessage != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xfffdf2f2),
                                  border: Border.all(color: const Color(0xfff8b4b4)),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Color(0xffc81e1e), fontSize: 13),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            if (isRegister) ...[
                              const Text('FULL NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. Ayush Goyal',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                  isDense: true,
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                              ),
                              const SizedBox(height: 20),
                            ],

                            const Text('EMAIL ADDRESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'name@domain.com',
                                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                isDense: true,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Please enter email';
                                if (!v.contains('@') || !v.contains('.')) return 'Please enter valid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            if (isRegister && !isDesigner) ...[
                              const Text('DESIGNER INVITATION CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _inviteCodeController,
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. INV-A1B2C3',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                  isDense: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'An invitation code from your designer is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                            ],

                            const Text('PASSWORD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: '••••••••',
                                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                isDense: true,
                              ),
                              validator: (v) => (v == null || v.length < 8) ? 'Password must be at least 8 characters' : null,
                            ),
                            const SizedBox(height: 20),

                            if (isRegister) ...[
                              const Text('CONFIRM PASSWORD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: '••••••••',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                  isDense: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Please confirm password';
                                  if (v != _passwordController.text) return 'Passwords do not match';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                            ],

                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff171817),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                onPressed: _isLoading ? null : _submit,
                                child: _isLoading
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(isRegister ? 'Register Account' : 'Sign In  →', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 24),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isRegister ? 'Already have an account? ' : "Don't have an account? ",
                                  style: const TextStyle(fontSize: 13, color: Color(0xff74756f)),
                                ),
                                InkWell(
                                  onTap: () {
                                    final route = isRegister
                                        ? '/${widget.role}/login'
                                        : '/${widget.role}/register';
                                    Navigator.pushReplacementNamed(context, route);
                                  },
                                  borderRadius: BorderRadius.circular(2),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      isRegister ? 'Sign In' : 'Create Account',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xff171817),
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
