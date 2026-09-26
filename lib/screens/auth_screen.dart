import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'main_navigation.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInEmail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerEmail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1628) : const Color(0xFFF5F0E8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_green, Color(0xFF2D6A4F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: _gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _green.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Center(
                  child:
                      Text('﷽', style: TextStyle(fontSize: 28, color: _gold)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Quran Kalima',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : _green)),
              const Text('کلمۂ قرآن',
                  style: TextStyle(fontSize: 16, color: _gold)),
              const SizedBox(height: 32),

              // Google sign in
              _GoogleButton(onTap: _signInGoogle, loading: _loading, isDark: isDark),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MainNavigation(),
                    ),
                  );
                },
                icon: const Icon(Icons.menu_book),
                label: const Text('Continue Without Login'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  foregroundColor: isDark ? Colors.white70 : _green,
                  side: BorderSide(color: isDark ? Colors.white30 : _green),
                ),
              ),

              const SizedBox(height: 16),

              // Divider
              Row(children: [
                Expanded(
                    child: Divider(
                        color: isDark ? Colors.white24 : Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey.shade500)),
                ),
                Expanded(
                    child: Divider(
                        color: isDark ? Colors.white24 : Colors.grey.shade300)),
              ]),
              const SizedBox(height: 16),

              // Email tabs
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                        color: _green.withValues(alpha: 0.08), blurRadius: 12),
                  ],
                ),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabs,
                      indicatorColor: _gold,
                      labelColor: isDark ? Colors.white : _green,
                      unselectedLabelColor: isDark ? Colors.white54 : Colors.grey,
                      indicator: BoxDecoration(
                        color: _gold.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                      ),
                      tabs: const [
                        Tab(text: 'Sign In'),
                        Tab(text: 'Register'),
                      ],
                    ),
                    SizedBox(
                      height: 280,
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _EmailForm(
                            emailCtrl: _emailCtrl,
                            passCtrl: _passCtrl,
                            obscure: _obscure,
                            onObscure: () =>
                                setState(() => _obscure = !_obscure),
                            buttonLabel: 'Sign In',
                            onSubmit: _signInEmail,
                            loading: _loading,
                            isDark: isDark,
                          ),
                          _EmailForm(
                            emailCtrl: _emailCtrl,
                            passCtrl: _passCtrl,
                            nameCtrl: _nameCtrl,
                            obscure: _obscure,
                            onObscure: () =>
                                setState(() => _obscure = !_obscure),
                            buttonLabel: 'Create Account',
                            onSubmit: _registerEmail,
                            loading: _loading,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(_error!,
                      style:
                          TextStyle(color: Colors.red.shade700, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 24),
              Text('By continuing you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  final bool isDark;
  const _GoogleButton({
    required this.onTap,
    required this.loading,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? Colors.white24 : Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/google.svg',
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => Icon(Icons.g_mobiledata,
                  size: 24, color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 12),
            Text('Continue with Google',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }
}

class _EmailForm extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final TextEditingController? nameCtrl;
  final bool obscure;
  final VoidCallback onObscure;
  final String buttonLabel;
  final VoidCallback onSubmit;
  final bool loading;
  final bool isDark;

  const _EmailForm({
    required this.emailCtrl,
    required this.passCtrl,
    this.nameCtrl,
    required this.obscure,
    required this.onObscure,
    required this.buttonLabel,
    required this.onSubmit,
    required this.loading,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.grey.shade500;
    final iconColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final fillColor = isDark ? const Color(0xFF0F1F14) : const Color(0xFFF5F0E8);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (nameCtrl != null)
            _field(nameCtrl!, 'Full Name', Icons.person, textColor, hintColor,
                iconColor, fillColor),
          if (nameCtrl != null) const SizedBox(height: 12),
          _field(emailCtrl, 'Email', Icons.email, textColor, hintColor,
              iconColor, fillColor),
          const SizedBox(height: 12),
          TextField(
            controller: passCtrl,
            obscureText: obscure,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: hintColor),
              prefixIcon: Icon(Icons.lock, color: iconColor),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off,
                    color: iconColor),
                onPressed: onObscure,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: fillColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(buttonLabel,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      Color textColor, Color hintColor, Color iconColor, Color fillColor) {
    return TextField(
      controller: ctrl,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(icon, color: iconColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: fillColor,
      ),
    );
  }
}
