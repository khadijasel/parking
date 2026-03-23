import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../theme/app_colors.dart';
import 'register_screen.dart';

/// Écran de connexion SmartPark
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _matriculeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

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

    setState(() => _isLoading = true);

    try {
      // TODO: Implémenter la logique d'authentification via le service
      await Future.delayed(const Duration(seconds: 2));

      // TODO: Naviguer vers l'écran principal après connexion réussie
    } catch (e) {
      // TODO: Gérer les erreurs avec un SnackBar ou Dialog
      debugPrint('Erreur de connexion: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        onPressed: () => Navigator.maybePop(context),
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
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        CustomTextField(
          label: 'Email',
          hint: AppConstants.emailHint,
          prefixIcon: Icons.email_outlined,
          controller: _emailController,
          validator: _validateEmail,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppConstants.paddingMedium),
        CustomTextField(
          label: 'Mot de passe',
          hint: AppConstants.passwordHint,
          prefixIcon: Icons.lock_outline,
          controller: _passwordController,
          obscureText: !_isPasswordVisible,
          validator: _validatePassword,
          textInputAction: TextInputAction.done,
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
    if (value == null || value.isEmpty) {
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
    if (value.length < 6) {
      return 'Le mot de passe doit contenir au moins 6 caractères';
    }
    return null;
  }
}
