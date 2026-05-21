import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';

enum _LoginMode { email, phone }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  _LoginMode _mode = _LoginMode.email;
  String _countryCode = '+30';
  bool _loading = false;
  bool _showPass = false;
  String? _error;

  final List<Map<String, String>> _countries = [
    {'code': '+30', 'flag': '🇬🇷', 'name': 'Ελλάδα'},
    {'code': '+357', 'flag': '🇨🇾', 'name': 'Κύπρος'},
    {'code': '+46', 'flag': '🇸🇪', 'name': 'Σουηδία'},
    {'code': '+47', 'flag': '🇳🇴', 'name': 'Νορβηγία'},
    {'code': '+45', 'flag': '🇩🇰', 'name': 'Δανία'},
    {'code': '+358', 'flag': '🇫🇮', 'name': 'Φινλανδία'},
    {'code': '+49', 'flag': '🇩🇪', 'name': 'Γερμανία'},
    {'code': '+33', 'flag': '🇫🇷', 'name': 'Γαλλία'},
    {'code': '+39', 'flag': '🇮🇹', 'name': 'Ιταλία'},
    {'code': '+34', 'flag': '🇪🇸', 'name': 'Ισπανία'},
    {'code': '+31', 'flag': '🇳🇱', 'name': 'Ολλανδία'},
    {'code': '+44', 'flag': '🇬🇧', 'name': 'Ηνωμένο Βασίλειο'},
    {'code': '+1', 'flag': '🇺🇸', 'name': 'ΗΠΑ'},
  ];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Validation πρώτα — έλεγξε τα πεδία πριν στείλεις στο Firebase
    if (_mode == _LoginMode.email) {
      if (_emailCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Συμπλήρωσε το email σου.');
        return;
      }
      if (!_emailCtrl.text.contains('@')) {
        setState(() => _error = 'Μη έγκυρη μορφή email.');
        return;
      }
    } else {
      if (_phoneCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Συμπλήρωσε τον αριθμό κινητού.');
        return;
      }
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Συμπλήρωσε τον κωδικό σου.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_mode == _LoginMode.email) {
        await ref.read(authRepoProvider).loginWithEmail(
              _emailCtrl.text.trim(),
              _passwordCtrl.text,
            );
      } else {
        final fullPhone = '$_countryCode${_phoneCtrl.text.trim()}';
        await ref.read(authRepoProvider).loginWithPhone(
              fullPhone,
              _passwordCtrl.text,
            );
      }
      if (mounted) context.go('/map');
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
          case 'no-email':
            _error = _mode == _LoginMode.email
                ? 'Δεν υπάρχει λογαριασμός με αυτό το email.'
                : 'Δεν υπάρχει λογαριασμός με αυτό το κινητό.';
            break;
          case 'wrong-password':
            _error = 'Λάθος κωδικός. Δοκίμασε ξανά.';
            break;
          case 'invalid-credential':
            // Firebase v22+ επιστρέφει αυτό αντί για user-not-found/wrong-password
            _error = _mode == _LoginMode.email
                ? 'Λάθος email ή κωδικός.'
                : 'Λάθος κινητό ή κωδικός.';
            break;
          case 'invalid-email':
            _error = 'Μη έγκυρη μορφή email.';
            break;
          case 'user-disabled':
            _error = 'Ο λογαριασμός είναι απενεργοποιημένος.';
            break;
          case 'too-many-requests':
            _error = 'Πολλές αποτυχημένες προσπάθειες. Δοκίμασε αργότερα.';
            break;
          case 'network-request-failed':
            _error = 'Πρόβλημα σύνδεσης. Έλεγξε το internet.';
            break;
          default:
            _error = e.message ?? AppStrings.errorGeneric;
        }
      });
    } catch (e) {
      setState(() => _error = 'Κάτι πήγε στραβά. Δοκίμασε ξανά.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
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
      if (mounted) context.go('/map');
    } catch (e) {
      setState(() => _error = 'Πρόβλημα με τη σύνδεση Google.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithFacebook() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FacebookAuth.instance.login();
      if (result.status != LoginStatus.success) {
        setState(() {
          _loading = false;
          _error = 'Η σύνδεση με Facebook ακυρώθηκε.';
        });
        return;
      }
      final credential =
          FacebookAuthProvider.credential(result.accessToken!.tokenString);
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) context.go('/map');
    } catch (e) {
      setState(() => _error = 'Πρόβλημα με τη σύνδεση Facebook.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ListView.builder(
        itemCount: _countries.length,
        itemBuilder: (_, i) {
          final c = _countries[i];
          return ListTile(
            leading: Text(c['flag']!, style: const TextStyle(fontSize: 24)),
            title: Text(c['name']!,
                style: const TextStyle(color: AppColors.textPrimary)),
            trailing: Text(c['code']!,
                style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () {
              setState(() => _countryCode = c['code']!);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text(AppStrings.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontSize: 36,
                      letterSpacing: -1)),
              const SizedBox(height: 8),
              const Text('Ανταλλαγές κοντά σου',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 15)),
              const SizedBox(height: 32),

              // Tab selector
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _mode = _LoginMode.email;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == _LoginMode.email
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _mode == _LoginMode.email
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _mode = _LoginMode.phone;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == _LoginMode.phone
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Κινητό',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _mode == _LoginMode.phone
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Email / Phone field
              if (_mode == _LoginMode.email) ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: AppStrings.email,
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ),
              ] else ...[
                Row(children: [
                  GestureDetector(
                    onTap: _showCountryPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Row(children: [
                        Text(_countryCode,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down,
                            color: AppColors.textSecondary, size: 18),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '6901234567',
                        prefixIcon: Icon(Icons.phone_outlined,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPass,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: AppStrings.password,
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppColors.textSecondary, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary,
                        size: 20),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: const Text('Ξέχασα τον κωδικό',
                      style: TextStyle(color: AppColors.primary, fontSize: 13)),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.danger, fontSize: 13))),
                  ]),
                ),
              ],
              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : const Text(AppStrings.login),
              ),
              const SizedBox(height: 24),

              const Row(children: [
                Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ή συνέχισε με',
                      style:
                          TextStyle(color: AppColors.textHint, fontSize: 12)),
                ),
                Expanded(child: Divider(color: AppColors.border)),
              ]),
              const SizedBox(height: 20),

              _SocialButton(
                icon: Icons.g_mobiledata,
                label: 'Σύνδεση με Google',
                color: const Color(0xFFDB4437),
                onTap: _loading ? null : _loginWithGoogle,
              ),
              const SizedBox(height: 12),
              _SocialButton(
                icon: Icons.facebook,
                label: 'Σύνδεση με Facebook',
                color: const Color(0xFF1877F2),
                onTap: _loading ? null : _loginWithFacebook,
              ),
              const SizedBox(height: 24),

              Center(
                child: TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text(
                      '${AppStrings.noAccount} ${AppStrings.signUp}'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
