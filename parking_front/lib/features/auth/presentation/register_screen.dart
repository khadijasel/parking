import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _matriculeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final AuthRepository _authRepository = AuthRepository();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _matriculeController.dispose();
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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authRepository.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        matricule: _matriculeController.text.trim(),
        password: _passwordController.text,
        passwordConfirmation: _confirmPasswordController.text,
      );

      if (!mounted) return;
      _goToMainScreen();
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (e) {
      debugPrint('Erreur d\'inscription: $e');
      _showError('Inscription impossible pour le moment. Réessayez.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppConstants.paddingMedium),
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
          label: 'Téléphone',
          hint: 'Ex: 0550123456',
          prefixIcon: Icons.phone_outlined,
          controller: _phoneController,
          validator: _validatePhone,
          keyboardType: TextInputType.phone,
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
          textInputAction: TextInputAction.next,
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
          textInputAction: TextInputAction.done,
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
      isLoading: _isLoading,
      onPressed: _handleRegister,
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
