/// Constantes globales de l'application
class AppConstants {
  AppConstants._();

  // App info
  static const String appName = 'SmartPark';
  static const String appTagline =
      'Accédez à votre espace stationnement urbain';

  // Validation patterns
  static const String emailPattern = r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$';
  static const String matriculePattern = r'^\d{1,5}-[A-Za-z]-\d{1,2}$';

  // Input hints
  static const String matriculeHint = 'Ex: 1234-A-15';
  static const String emailHint = 'votre@email.com';
  static const String passwordHint = '••••••••';

  // Messages
  static const String forgotPassword = 'Mot de passe oublié ?';
  static const String noAccount = 'Pas encore de compte ?';
  static const String createAccount = 'Créer un compte';
  static const String alreadyHaveAccount = 'Déjà un compte ?';
  static const String loginButton = 'Se connecter';
  static const String registerButton = "S'inscrire";

  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border radius
  static const double borderRadiusSmall = 12.0;
  static const double borderRadiusMedium = 16.0;
  static const double borderRadiusLarge = 24.0;
  static const double borderRadiusXLarge = 32.0;
}
