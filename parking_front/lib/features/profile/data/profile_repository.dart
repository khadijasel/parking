import '../../auth/data/auth_local_storage.dart';
import 'profile_api_service.dart';

class ProfileException implements Exception {
  final String message;

  const ProfileException(this.message);

  @override
  String toString() => 'ProfileException(message: $message)';
}

class ProfileRepository {
  final ProfileApiService _apiService;
  final AuthLocalStorage _localStorage;

  ProfileRepository({
    ProfileApiService? apiService,
    AuthLocalStorage? localStorage,
  })  : _apiService = apiService ?? ProfileApiService(),
        _localStorage = localStorage ?? AuthLocalStorage();

  Future<Map<String, dynamic>> fetchProfile() async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ProfileException('Session invalide. Veuillez vous reconnecter.');
    }

    try {
      final Map<String, dynamic> user = await _apiService.fetchProfile(token: token);
      await _localStorage.updateUser(user);
      return user;
    } on ProfileApiException catch (error) {
      throw ProfileException(error.message);
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? matricule,
    String? city,
    String? address,
    String? latitude,
    String? longitude,
    String? avatarDataUrl,
  }) async {
    final String? token = await _localStorage.readToken();
    if (token == null || token.isEmpty) {
      throw const ProfileException('Session invalide. Veuillez vous reconnecter.');
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name?.trim(),
      'email': email?.trim(),
      'phone': phone?.trim(),
      'matricule': matricule?.trim(),
      'city': city?.trim(),
      'address': address?.trim(),
      'latitude': (latitude == null || latitude.trim().isEmpty)
          ? null
          : double.tryParse(latitude.trim()),
      'longitude': (longitude == null || longitude.trim().isEmpty)
          ? null
          : double.tryParse(longitude.trim()),
      'avatar_data_url': avatarDataUrl,
    };

    payload.removeWhere((String key, dynamic value) => value == null);

    try {
      final Map<String, dynamic> updated = await _apiService.updateProfile(
        token: token,
        payload: payload,
      );

      await _localStorage.updateUser(updated);
      return updated;
    } on ProfileApiException catch (error) {
      throw ProfileException(error.message);
    }
  }
}
