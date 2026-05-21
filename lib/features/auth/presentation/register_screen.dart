import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/password_strength.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _passConfirm = TextEditingController();

  String _countryCode = '+30';
  bool _loading = false;
  bool _showPass = false;
  bool _showPassConfirm = false;
  String? _error;

  File? _profilePhoto;

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
    {'code': '+32', 'flag': '🇧🇪', 'name': 'Βέλγιο'},
    {'code': '+41', 'flag': '🇨🇭', 'name': 'Ελβετία'},
    {'code': '+43', 'flag': '🇦🇹', 'name': 'Αυστρία'},
    {'code': '+44', 'flag': '🇬🇧', 'name': 'Ηνωμένο Βασίλειο'},
    {'code': '+1', 'flag': '🇺🇸', 'name': 'ΗΠΑ'},
    {'code': '+1', 'flag': '🇨🇦', 'name': 'Καναδάς'},
    {'code': '+61', 'flag': '🇦🇺', 'name': 'Αυστραλία'},
  ];

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _passConfirm.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _profilePhoto = File(picked.path));
    }
  }

  Future<void> _continueToVerification() async {
    setState(() => _error = null);

    // 1) Validation
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = 'Συμπλήρωσε όνομα και επώνυμο.');
      return;
    }
    if (_email.text.trim().isEmpty || !_email.text.contains('@')) {
      setState(() => _error = 'Δώσε ένα έγκυρο email.');
      return;
    }
    if (_phone.text.trim().isEmpty || _phone.text.trim().length < 8) {
      setState(() => _error = 'Δώσε έγκυρο αριθμό κινητού.');
      return;
    }

    final passError = AuthRepository.validatePassword(_pass.text);
    if (passError != null) {
      setState(() => _error = passError);
      return;
    }

    if (_pass.text != _passConfirm.text) {
      setState(() => _error = 'Οι κωδικοί δεν ταιριάζουν.');
      return;
    }

    // 2) Έλεγχος αν υπάρχει ήδη χρήστης με αυτό το κινητό
    setState(() => _loading = true);
    try {
      final fullPhone = '$_countryCode${_phone.text.trim()}';
      final exists = await ref.read(authRepoProvider).phoneExists(fullPhone);
      if (exists) {
        setState(() {
          _error = 'Υπάρχει ήδη λογαριασμός με αυτό το κινητό.';
          _loading = false;
        });
        return;
      }

      // 3) Πάμε στην οθόνη OTP περνώντας τα στοιχεία ως extra
      if (!mounted) return;
      context.push('/phone-auth', extra: {
        'mode': 'register',
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'email': _email.text.trim(),
        'phone': fullPhone,
        'password': _pass.text,
        'profilePhotoPath': _profilePhoto?.path,
      });
    } catch (e) {
      setState(() => _error = AppStrings.errorGeneric);
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
      appBar: AppBar(title: const Text(AppStrings.signUp)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            // Photo picker (optional)
            GestureDetector(
              onTap: _pickPhoto,
              child: Stack(children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceVariant,
                    border: Border.all(color: AppColors.border, width: 1),
                    image: _profilePhoto != null
                        ? DecorationImage(
                            image: FileImage(_profilePhoto!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _profilePhoto == null
                      ? const Icon(Icons.person_outline,
                          color: AppColors.textSecondary, size: 40)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 16),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('Φωτογραφία (προαιρετικό)',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
            const SizedBox(height: 24),

            // Όνομα + Επώνυμο
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _first,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration:
                      const InputDecoration(hintText: AppStrings.firstName),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _last,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration:
                      const InputDecoration(hintText: AppStrings.lastName),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // Email
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: AppStrings.email,
                prefixIcon: Icon(Icons.email_outlined,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
            const SizedBox(height: 12),

            // Κινητό με country code
            Row(children: [
              GestureDetector(
                onTap: _showCountryPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                  controller: _phone,
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
            const SizedBox(height: 12),

            // Κωδικός
            TextField(
              controller: _pass,
              obscureText: !_showPass,
              onChanged: (_) => setState(() {}),
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
            PasswordStrengthIndicator(password: _pass.text),
            const SizedBox(height: 4),
            const Text(
              'Τουλάχιστον 8 χαρακτήρες, 1 κεφαλαίο, 1 πεζό, 1 αριθμό',
              style: TextStyle(color: AppColors.textHint, fontSize: 11),
            ),
            const SizedBox(height: 12),

            // Επιβεβαίωση κωδικού
            TextField(
              controller: _passConfirm,
              obscureText: !_showPassConfirm,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Επιβεβαίωση κωδικού',
                prefixIcon: const Icon(Icons.lock_outline,
                    color: AppColors.textSecondary, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showPassConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.textSecondary,
                      size: 20),
                  onPressed: () =>
                      setState(() => _showPassConfirm = !_showPassConfirm),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
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
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _loading ? null : _continueToVerification,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.background))
                  : const Text('Συνέχεια'),
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: () => context.pop(),
              child: const Text('${AppStrings.hasAccount} ${AppStrings.login}'),
            ),
          ]),
        ),
      ),
    );
  }
}
