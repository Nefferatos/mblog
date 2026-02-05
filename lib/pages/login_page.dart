import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'blog_list_page.dart';
import '../services/auth_service.dart'; 

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final usernameController = TextEditingController();

  bool loading = false;
  bool isSignup = false;

  final AuthService authService = AuthService();

  // ---------------- LOGIN ----------------
  Future<void> login() async {
    setState(() => loading = true);
    try {
      final user = await authService.signIn(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) return;

      if (user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BlogListPage()),
        );
      }
    } on AuthException catch (e) {
      showError(e.message);
    } catch (e) {
      showError('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ---------------- SIGN UP ----------------
  Future<void> signUp() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final username = usernameController.text.trim();

    if (username.isEmpty) {
      showError("Username is required.");
      return;
    }

    setState(() => loading = true);
    try {
      // 1️⃣ Create user in Supabase Auth
      // The database trigger will automatically create the 'profiles' row 
      // using the 'displayName' (display_name) passed here.
      final user = await authService.signUp(
        email: email,
        password: password,
        displayName: username,
      );

      if (user == null) throw 'User creation failed';

      if (!mounted) return;

      // SUCCESS!
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created! Logging you in...')),
      );

      // Auto-switch to login mode
      setState(() {
        isSignup = false;
        passwordController.clear();
        usernameController.clear();
      });
      
    } on AuthException catch (e) {
      showError(e.message);
    } catch (e) {
      showError(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  // ---------------- UI DESIGN ----------------
  @override
  Widget build(BuildContext context) {
    const Color colorBlack = Color(0xFF1A1A1A);
    const Color colorGrey = Color(0xFF757575);
    const Color colorWhite = Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const FlutterLogo(size: 80),
              const SizedBox(height: 20),
              Text(
                isSignup ? 'SIGN UP' : 'SIGN IN',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: colorBlack),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorWhite,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    _buildTextField(
                      controller: emailController,
                      label: 'Email Address',
                      icon: Icons.email_outlined,
                    ),
                    if (isSignup) ...[
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: usernameController,
                        label: 'Username',
                        icon: Icons.person_outline,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: loading ? null : (isSignup ? signUp : login),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorBlack,
                          foregroundColor: colorWhite,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: loading
                            ? const CircularProgressIndicator(color: colorWhite)
                            : Text(isSignup ? 'CREATE ACCOUNT' : 'LOG IN'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              TextButton(
                onPressed: () => setState(() => isSignup = !isSignup),
                child: Text(
                  isSignup ? 'Already have an account? Sign In' : 'Don’t have an account? Sign Up',
                  style: const TextStyle(color: colorGrey, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF9F9F9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}