import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../theme/app_colors.dart';
import '../data/auth_repository.dart';
import 'login_screen.dart';

// ignore_for_file: deprecated_member_use

class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final AuthRepository _authRepository = AuthRepository();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  String? _tokenError;
  String? _passwordError;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _tokenError = null;
      _passwordError = null;
    });

    try {
      await _authRepository.resetPassword(
        email: widget.email,
        token: _tokenController.text.trim(),
        password: _passwordController.text,
        passwordConfirmation: _confirmController.text,
      );

      if (!mounted) return;

      AppFeedback.showSuccess(
        context,
        'Mot de passe réinitialisé avec succès !',
      );

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      final String? tokenErr = error.fieldErrors['token'];
      final String? passwordErr = error.fieldErrors['password'];

      if (tokenErr != null || passwordErr != null) {
        setState(() {
          _tokenError = tokenErr;
          _passwordError = passwordErr;
        });
        return;
      }

      AppFeedback.showError(context, error.message);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showError(context, 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateToken(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Veuillez entrer le code reçu par email';
    }
    if (value.trim().length != 6) {
      return 'Le code doit contenir 6 chiffres';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez entrer un nouveau mot de passe';
    }
    if (value.length < 8) {
      return 'Le mot de passe doit contenir au moins 8 caractères';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez confirmer votre mot de passe';
    }
    if (value != _passwordController.text) {
      return 'Les mots de passe ne correspondent pas';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Nouveau mot de passe',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double horizontalPadding = constraints.maxWidth > 600
                ? (constraints.maxWidth - 500) / 2
                : AppConstants.paddingLarge;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: AppConstants.paddingLarge,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppConstants.paddingLarge),
                decoration: const BoxDecoration(color: Colors.white),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppConstants.paddingMedium),
                      Container(
                        padding: const EdgeInsets.all(AppConstants.paddingMedium),
                        decoration: BoxDecoration(
                          color: AppColors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(
                            AppConstants.borderRadiusMedium,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.mark_email_read_outlined,
                              color: AppColors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Code envoyé à ${widget.email}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingXLarge),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Code de vérification',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: AppConstants.paddingSmall),
                          TextFormField(
                            controller: _tokenController,
                            validator: _validateToken,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            onChanged: (_) {
                              if (_tokenError != null) {
                                setState(() => _tokenError = null);
                              }
                            },
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textDark,
                            ),
                            decoration: InputDecoration(
                              hintText: '000000',
                              errorText: _tokenError,
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade400,
                              ),
                              prefixIcon: Icon(
                                Icons.pin_outlined,
                                color: Colors.grey.shade400,
                                size: 22,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.paddingMedium,
                                vertical: AppConstants.paddingMedium,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
                                borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
                                borderSide: const BorderSide(color: Colors.red, width: 1.5),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
                                borderSide: const BorderSide(color: Colors.red, width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      CustomTextField(
                        label: 'Nouveau mot de passe',
                        hint: AppConstants.passwordHint,
                        prefixIcon: Icons.lock_outline,
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        validator: _validatePassword,
                        errorText: _passwordError,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_passwordError != null) {
                            setState(() => _passwordError = null);
                          }
                        },
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      CustomTextField(
                        label: 'Confirmer le mot de passe',
                        hint: AppConstants.passwordHint,
                        prefixIcon: Icons.lock_outline,
                        controller: _confirmController,
                        obscureText: !_isConfirmVisible,
                        validator: _validateConfirm,
                        textInputAction: TextInputAction.done,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: () => setState(
                            () => _isConfirmVisible = !_isConfirmVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingXLarge),
                      GradientButton(
                        text: 'Réinitialiser le mot de passe',
                        icon: Icons.check_circle_outline,
                        isLoading: _isLoading,
                        onPressed: _handleReset,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
