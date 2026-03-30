import 'auth_api_service.dart';
import 'auth_local_storage.dart';

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => 'AuthException(message: $message)';
}

class AuthRepository {
  final AuthApiService _apiService;
  final AuthLocalStorage _localStorage;

  AuthRepository({
    AuthApiService? apiService,
    AuthLocalStorage? localStorage,
  })  : _apiService = apiService ?? AuthApiService(),
        _localStorage = localStorage ?? AuthLocalStorage();

  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthApiResult result = await _apiService.login(
        email: email,
        password: password,
      );

      await _localStorage.saveSession(
        token: result.token,
        user: result.user,
      );
    } on AuthApiException catch (error) {
      throw AuthException(error.message);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String matricule,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final AuthApiResult result = await _apiService.register(
        name: name,
        email: email,
        phone: phone,
        matricule: matricule,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );

      await _localStorage.saveSession(
        token: result.token,
        user: result.user,
      );
    } on AuthApiException catch (error) {
      throw AuthException(error.message);
    }
  }

  Future<bool> hasActiveSession() async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    final bool isValid = await _apiService.validateSession(token);
    if (!isValid) {
      await _localStorage.clearSession();
    }

    return isValid;
  }

  Future<void> logout() async {
    final String? token = await _localStorage.readToken();

    try {
      if (token != null && token.isNotEmpty) {
        await _apiService.logout(token);
      }
    } on AuthApiException {
      // In case of network issues, we still clear local session.
    } finally {
      await _localStorage.clearSession();
    }
  }

  Future<void> clearSession() => _localStorage.clearSession();
}
