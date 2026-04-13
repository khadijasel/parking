import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../theme/app_colors.dart';
import '../../main/main_screen.dart';
import '../../parking/presentation/map_home_screen.dart';
import '../data/auth_repository.dart';
import 'register_screen.dart';

/// Écran de connexion SmartPark
class LoginScreen extends StatefulWidget {
  final Widget? postLoginRoute;

  const LoginScreen({super.key, this.postLoginRoute});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _matriculeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthRepository _authRepository = AuthRepository();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _matriculeLoginError;
  String? _emailLoginError;
  String? _passwordLoginError;

  @override
  void dispose() {
    _matriculeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordVisible = !_isPasswordVisible;
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _matriculeLoginError = null;
      _emailLoginError = null;
      _passwordLoginError = null;
    });

    try {
      await _authRepository.login(
        matricule: _matriculeController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      _goToMainScreen();
    } on AuthException catch (error) {
      if (_applyServerFieldErrors(error.fieldErrors)) {
        return;
      }

      if (_shouldShowInlineAuthError(error.message)) {
        if (_applyMessageFieldError(error.message)) {
          return;
        }

        setState(() {
          _passwordLoginError = error.message;
        });
      } else {
        _showError(error.message);
      }
    } catch (e) {
      debugPrint('Erreur de connexion: $e');
      _showError('Connexion impossible pour le moment. Réessayez.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _goToMainScreen() {
    final Widget nextScreen = widget.postLoginRoute ?? const MainScreen(isAuthenticated: true);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => nextScreen,
      ),
      (Route<dynamic> route) => false,
    );
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MapHomeScreen(),
      ),
    );
  }

  void _showError(String message) {
    AppFeedback.showError(context, message);
  }

  bool _applyServerFieldErrors(Map<String, String> fieldErrors) {
    if (fieldErrors.isEmpty) {
      return false;
    }

    final String? emailError = _pickFieldError(fieldErrors, <String>['email']);
    final String? matriculeError =
        _pickFieldError(fieldErrors, <String>['matricule']);
    final String? passwordError =
        _pickFieldError(fieldErrors, <String>['password']);

    if (emailError == null && passwordError == null && matriculeError == null) {
      return false;
    }

    setState(() {
      _matriculeLoginError = matriculeError;
      _emailLoginError = emailError;
      _passwordLoginError = passwordError;
    });

    return true;
  }

  String? _pickFieldError(
    Map<String, String> fieldErrors,
    List<String> candidateKeys,
  ) {
    for (final String key in candidateKeys) {
      final String? value = fieldErrors[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  bool _applyMessageFieldError(String message) {
    final String normalized = message.toLowerCase();

    if (normalized.contains('email')) {
      setState(() {
        _matriculeLoginError = null;
        _emailLoginError = message;
        _passwordLoginError = null;
      });
      return true;
    }

    if (normalized.contains('matricule')) {
      setState(() {
        _matriculeLoginError = message;
        _emailLoginError = null;
        _passwordLoginError = null;
      });
      return true;
    }

    if (normalized.contains('mot de passe') || normalized.contains('password')) {
      setState(() {
        _matriculeLoginError = null;
        _emailLoginError = null;
        _passwordLoginError = message;
      });
      return true;
    }

    return false;
  }

  bool _shouldShowInlineAuthError(String message) {
    final String normalized = message.toLowerCase();

    if (normalized.contains('impossible de contacter le serveur') ||
        normalized.contains('délai dépassé') ||
        normalized.contains('requête annulée') ||
        normalized.contains('certificat serveur invalide')) {
      return false;
    }

    return normalized.contains('invalid credentials') ||
        normalized.contains('provided credentials') ||
        normalized.contains('incorrect') ||
      normalized.contains('matricule') ||
        normalized.contains('password') ||
        normalized.contains('mot de passe') ||
        normalized.contains('email') ||
        normalized.contains('at least') ||
        normalized.contains('character');
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  void _handleForgotPassword() {
    // TODO: Naviguer vers l'écran de récupération de mot de passe
    debugPrint('Navigation vers récupération mot de passe');
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
                child: _buildLoginCard(),
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
        onPressed: _handleBack,
      ),
      centerTitle: true,
      title: const Text(
        'Connexion',
        style: TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingLarge),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const AppLogo(),
            const SizedBox(height: AppConstants.paddingXLarge),
            _buildFormFields(),
            const SizedBox(height: AppConstants.paddingMedium),
            _buildForgotPasswordLink(),
            const SizedBox(height: AppConstants.paddingLarge),
            _buildLoginButton(),
            const SizedBox(height: AppConstants.paddingLarge),
            _buildDivider(),
            const SizedBox(height: AppConstants.paddingLarge),
            _buildRegisterLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        CustomTextField(
          label: 'Matricule véhicule',
          hint: AppConstants.matriculeHint,
          prefixIcon: Icons.directions_car_outlined,
          controller: _matriculeController,
          validator: _validateMatricule,
          errorText: _matriculeLoginError,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_matriculeLoginError != null ||
                _emailLoginError != null ||
                _passwordLoginError != null) {
              setState(() {
                _matriculeLoginError = null;
                _emailLoginError = null;
                _passwordLoginError = null;
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
          errorText: _emailLoginError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_matriculeLoginError != null ||
                _emailLoginError != null ||
                _passwordLoginError != null) {
              setState(() {
                _matriculeLoginError = null;
                _emailLoginError = null;
                _passwordLoginError = null;
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
          errorText: _passwordLoginError,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_matriculeLoginError != null ||
                _emailLoginError != null ||
                _passwordLoginError != null) {
              setState(() {
                _matriculeLoginError = null;
                _emailLoginError = null;
                _passwordLoginError = null;
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
      ],
    );
  }

  Widget _buildForgotPasswordLink() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _handleForgotPassword,
        child: const Text(
          AppConstants.forgotPassword,
          style: TextStyle(
            color: AppColors.green,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return GradientButton(
      text: AppConstants.loginButton,
      icon: Icons.login,
      isLoading: _isLoading,
      onPressed: _handleLogin,
    );
  }

  Widget _buildDivider() {
    return const SizedBox.shrink();
  }

  Widget _buildRegisterLink() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          AppConstants.noAccount,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        TextButton(
          onPressed: _navigateToRegister,
          child: const Text(
            AppConstants.createAccount,
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
  String? _validateMatricule(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Veuillez entrer votre matricule';
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
    return null;
  }
}
