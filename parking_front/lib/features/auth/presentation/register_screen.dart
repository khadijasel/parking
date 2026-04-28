import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../theme/app_colors.dart';
import '../../main/main_screen.dart';
import '../data/auth_repository.dart';

/// Écran d'inscription SmartPark
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final AuthRepository _authRepository = AuthRepository();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>['email', 'profile'],
    serverClientId:
        _googleServerClientId.isEmpty ? null : _googleServerClientId,
  );

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _nameInlineError;
  String? _emailInlineError;
  String? _phoneInlineError;
  String? _passwordInlineError;
  String? _confirmPasswordInlineError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordVisible = !_isPasswordVisible;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
    });
  }

  Future<void> _handleRegister() async {
    if (_isGoogleLoading) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _nameInlineError = null;
      _emailInlineError = null;
      _phoneInlineError = null;
      _passwordInlineError = null;
      _confirmPasswordInlineError = null;
    });

    try {
      await _authRepository.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        passwordConfirmation: _confirmPasswordController.text,
      );

      if (!mounted) return;
      _goToMainScreen();
    } on AuthException catch (error) {
      if (error.fieldErrors.isNotEmpty) {
        _applyFieldErrors(error.fieldErrors);
      } else {
        _showError(error.message);
      }
    } catch (e) {
      debugPrint('Erreur d\'inscription: $e');
      _showError('Inscription impossible pour le moment. Réessayez.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleAuth() async {
    if (_isLoading || _isGoogleLoading) return;

    setState(() {
      _isGoogleLoading = true;
      _nameInlineError = null;
      _emailInlineError = null;
      _phoneInlineError = null;
      _passwordInlineError = null;
      _confirmPasswordInlineError = null;
    });

    try {
      final GoogleSignInAccount? account = await _signInWithAccountPicker();

      if (account == null) {
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String idToken = (auth.idToken ?? '').trim();
      final String accessToken = (auth.accessToken ?? '').trim();

      if (idToken.isEmpty && accessToken.isEmpty) {
        _showError(
          'Impossible de recuperer les jetons Google. Verifiez votre configuration Google Sign-In.',
        );
        return;
      }

      await _authRepository.loginWithGoogle(
        idToken: idToken.isEmpty ? null : idToken,
        accessToken: accessToken.isEmpty ? null : accessToken,
      );

      if (!mounted) return;
      _goToMainScreen();
    } on AuthException catch (error) {
      _showError(error.message);
    } on PlatformException catch (error) {
      debugPrint('Erreur inscription Google [${error.code}]: ${error.message}');

      if (_isGoogleSignInCanceled(error)) {
        return;
      }

      _showError(_mapGooglePlatformError(error));
    } catch (e) {
      debugPrint('Erreur inscription Google: $e');
      _showError('Inscription Google impossible pour le moment.');
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Future<GoogleSignInAccount?> _signInWithAccountPicker() async {
    try {
      await _googleSignIn.signOut();
    } catch (error) {
      debugPrint('Google signOut ignored: $error');
    }

    return _googleSignIn.signIn();
  }

  void _goToMainScreen() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const MainScreen(isAuthenticated: true),
      ),
      (Route<dynamic> route) => false,
    );
  }

  void _showError(String message) {
    AppFeedback.showError(context, message);
  }

  bool _isGoogleSignInCanceled(PlatformException error) {
    final String code = error.code.toLowerCase();
    return code.contains('cancel');
  }

  String _mapGooglePlatformError(PlatformException error) {
    final String code = error.code.toLowerCase();
    final String message = (error.message ?? '').toLowerCase();

    if (code.contains('network') || message.contains('network')) {
      return 'Connexion internet requise pour continuer avec Google.';
    }

    final bool isConfigurationError =
        code == '10' ||
            code.contains('sign_in_failed') ||
            message.contains('developer_error') ||
            message.contains('12500');

    if (isConfigurationError) {
      return 'Configuration Google invalide (package Android, SHA-1 ou client OAuth).';
    }

    return 'Inscription Google impossible pour le moment.';
  }

  void _applyFieldErrors(Map<String, String> fieldErrors) {
    final String? passwordError = fieldErrors['password'];
    final String? confirmError = fieldErrors['password_confirmation'];
    final bool passwordLooksLikeConfirmIssue =
        (passwordError ?? '').toLowerCase().contains('confirm');

    setState(() {
      _nameInlineError = fieldErrors['name'];
      _emailInlineError = fieldErrors['email'];
      _phoneInlineError = fieldErrors['phone'];
      _passwordInlineError = passwordError;
      _confirmPasswordInlineError = confirmError ??
          (passwordLooksLikeConfirmIssue ? passwordError : null);
    });
  }

  void _navigateToLogin() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth > 600
                  ? (constraints.maxWidth - 500) / 2
                  : AppConstants.paddingLarge;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: AppConstants.paddingLarge,
                ),
                child: _buildRegisterCard(),
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
        onPressed: () => Navigator.maybePop(context),
      ),
      centerTitle: true,
      title: const Text(
        'Inscription',
        style: TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRegisterCard() {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingLarge),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const AppLogo(showTagline: false),
            const SizedBox(height: AppConstants.paddingMedium),
            const Text(
              'Créez votre compte SmartPark',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: AppConstants.paddingXLarge),
            _buildFormFields(),
            const SizedBox(height: AppConstants.paddingLarge),
            _buildRegisterButton(),
            const SizedBox(height: AppConstants.paddingMedium),
            _buildGoogleButton(),
            const SizedBox(height: AppConstants.paddingLarge),
            _buildDivider(),
            const SizedBox(height: AppConstants.paddingLarge),
            _buildLoginLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        CustomTextField(
          label: 'Nom complet',
          hint: 'Votre nom',
          prefixIcon: Icons.person_outline,
          controller: _nameController,
          validator: _validateName,
          errorText: _nameInlineError,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_nameInlineError != null) {
              setState(() {
                _nameInlineError = null;
              });
            }
          },
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        CustomTextField(
          label: 'Email',
          hint: AppConstants.emailHint,
          prefixIcon: Icons.email_outlined,
          controller: _emailController,
          validator: _validateEmail,
          errorText: _emailInlineError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_emailInlineError != null) {
              setState(() {
                _emailInlineError = null;
              });
            }
          },
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        CustomTextField(
          label: 'Téléphone',
          hint: 'Ex: 0550123456',
          prefixIcon: Icons.phone_outlined,
          controller: _phoneController,
          validator: _validatePhone,
          errorText: _phoneInlineError,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_phoneInlineError != null) {
              setState(() {
                _phoneInlineError = null;
              });
            }
          },
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        CustomTextField(
          label: 'Mot de passe',
          hint: AppConstants.passwordHint,
          prefixIcon: Icons.lock_outline,
          controller: _passwordController,
          obscureText: !_isPasswordVisible,
          validator: _validatePassword,
          errorText: _passwordInlineError,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_passwordInlineError != null ||
                _confirmPasswordInlineError != null) {
              setState(() {
                _passwordInlineError = null;
                _confirmPasswordInlineError = null;
              });
            }
          },
          suffixIcon: IconButton(
            icon: Icon(
              _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey.shade400,
            ),
            onPressed: _togglePasswordVisibility,
          ),
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        CustomTextField(
          label: 'Confirmer mot de passe',
          hint: AppConstants.passwordHint,
          prefixIcon: Icons.lock_outline,
          controller: _confirmPasswordController,
          obscureText: !_isConfirmPasswordVisible,
          validator: _validateConfirmPassword,
          errorText: _confirmPasswordInlineError,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_confirmPasswordInlineError != null) {
              setState(() {
                _confirmPasswordInlineError = null;
              });
            }
          },
          suffixIcon: IconButton(
            icon: Icon(
              _isConfirmPasswordVisible
                  ? Icons.visibility_off
                  : Icons.visibility,
              color: Colors.grey.shade400,
            ),
            onPressed: _toggleConfirmPasswordVisibility,
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterButton() {
    return GradientButton(
      text: AppConstants.registerButton,
      icon: Icons.person_add,
      isLoading: _isLoading || _isGoogleLoading,
      onPressed: _handleRegister,
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: (_isLoading || _isGoogleLoading) ? null : _handleGoogleAuth,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(AppConstants.borderRadiusXLarge),
          ),
          backgroundColor: Colors.white,
        ),
        icon: _isGoogleLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.g_mobiledata, size: 28, color: Colors.black87),
        label: Text(
          _isGoogleLoading
              ? 'Inscription Google...'
              : 'Continuer avec Google',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const SizedBox.shrink();
  }

  Widget _buildLoginLink() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          AppConstants.alreadyHaveAccount,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        TextButton(
          onPressed: _navigateToLogin,
          child: const Text(
            AppConstants.loginButton,
            style: TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // Validators
  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez entrer votre nom';
    }
    if (value.length < 2) {
      return 'Le nom doit contenir au moins 2 caractères';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez entrer votre email';
    }
    final RegExp emailRegex = RegExp(AppConstants.emailPattern);
    if (!emailRegex.hasMatch(value)) {
      return 'Veuillez entrer un email valide';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez entrer votre mot de passe';
    }
    if (value.length < 8) {
      return 'Le mot de passe doit contenir au moins 8 caractères';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez entrer votre numéro de téléphone';
    }

    if (value.length < 8) {
      return 'Veuillez entrer un numéro valide';
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez confirmer votre mot de passe';
    }
    if (value != _passwordController.text) {
      return 'Les mots de passe ne correspondent pas';
    }
    return null;
  }
}
