import 'package:dio/dio.dart';

import '../constants/api_constants.dart';

/// Client HTTP Dio partage par toute l'application.
///
/// Pourquoi : auparavant chaque service API (`auth`, `reservation`, `payment`,
/// `profile`, `parking`, `availability`) instanciait son propre `Dio`, soit
/// autant de pools de connexions HTTP distincts recrees a chaque navigation.
/// Un client unique reutilise les connexions keep-alive entre tous les ecrans,
/// ce qui reduit nettement la latence percue au clic sur un bouton.
///
/// Les timeouts etaient aussi incoherents (30s sur certains services) : une
/// requete bloquee gelait l'interface jusqu'a 30s. On uniformise a 12s.
class AppHttpClient {
  AppHttpClient._();

  static final Dio instance = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      headers: const <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
    ),
  );
}
