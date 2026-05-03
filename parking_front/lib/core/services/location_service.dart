import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:parking_front/core/constants/api_constants.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

class DrivingRoute {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;

  const DrivingRoute({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

class LocationService {
  /// Vérifie les permissions et retourne la position de l'utilisateur.
  static Future<LatLng?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      }

      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return null;
      }

      if (permission == LocationPermission.denied) {
        return null;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LatLng(lastKnown.latitude, lastKnown.longitude);
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));

      return LatLng(position.latitude, position.longitude);
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Calcule la distance en km entre deux points.
  static double distanceKm(LatLng from, LatLng to) {
    return const Distance().as(LengthUnit.Kilometer, from, to);
  }

  /// Récupère un itinéraire routier réel (voiture) via le backend,
  /// puis bascule sur OSRM direct si le serveur local n'arrive pas à le joindre.
  static Future<DrivingRoute?> getDrivingRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final List<Uri> candidates = <Uri>[
      Uri.parse(
        '${ApiConstants.baseUrl}/routing/driving?'
        'from_lat=${from.latitude}&from_lng=${from.longitude}'
        '&to_lat=${to.latitude}&to_lng=${to.longitude}',
      ),
      Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&alternatives=false&steps=false',
      ),
    ];

    final List<String> serviceNames = ['Backend Proxy', 'OSRM Direct'];

    for (int i = 0; i < candidates.length; i++) {
      final Uri uri = candidates[i];
      final String serviceName = serviceNames[i];
      
      developer.log('🔄 Tentative de calcul d\'itinéraire via $serviceName: $uri');
      print('🔄 Tentative de calcul d\'itinéraire via $serviceName: $uri');
      
      final DrivingRoute? route = await _fetchDrivingRoute(uri, from, to, serviceName);
      if (route != null) {
        developer.log('✅ Itinéraire obtenu via $serviceName: ${route.distanceKm.toStringAsFixed(1)} km, ${route.durationMinutes} min');
        print('✅ Itinéraire obtenu via $serviceName: ${route.distanceKm.toStringAsFixed(1)} km, ${route.durationMinutes} min');
        return route;
      }
    }

    developer.log('❌ Impossible de calculer l\'itinéraire: tous les services ont échoué');
    print('❌ Impossible de calculer l\'itinéraire: tous les services ont échoué');
    return null;
  }

  static Future<DrivingRoute?> _fetchDrivingRoute(
    Uri uri,
    LatLng from,
    LatLng to,
    String serviceName,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 15));

      developer.log('[$serviceName] Status code: ${response.statusCode}');
      print('[$serviceName] Status code: ${response.statusCode}');

      if (response.statusCode != HttpStatus.ok) {
        final errorMsg = '[$serviceName] Erreur HTTP ${response.statusCode}';
        developer.log('❌ $errorMsg');
        print('❌ $errorMsg');
        return null;
      }

      final raw = await utf8.decoder.bind(response).join();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      
      if (data['code'] != 'Ok') {
        final errorMsg = '[$serviceName] Code OSRM invalide: ${data['code']}';
        developer.log('❌ $errorMsg');
        print('❌ $errorMsg');
        return null;
      }

      final routes = (data['routes'] as List<dynamic>?) ?? const [];
      if (routes.isEmpty) {
        final errorMsg = '[$serviceName] Aucune route trouvée';
        developer.log('❌ $errorMsg');
        print('❌ $errorMsg');
        return null;
      }

      final first = routes.first as Map<String, dynamic>;
      final geometry = first['geometry'] as Map<String, dynamic>?;
      final coordinates =
          (geometry?['coordinates'] as List<dynamic>?) ?? const [];

      if (coordinates.isEmpty) {
        final errorMsg = '[$serviceName] Géométrie vide';
        developer.log('❌ $errorMsg');
        print('❌ $errorMsg');
        return null;
      }

      final points = coordinates.map((coord) {
        final c = coord as List<dynamic>;
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      }).toList();

      final distanceMeters = (first['distance'] as num?)?.toDouble() ??
          (distanceKm(from, to) * 1000);
      final durationSeconds = (first['duration'] as num?)?.toDouble() ?? 0;
      final durationMinutes = (durationSeconds / 60).round().clamp(1, 9999);

      return DrivingRoute(
        points: points,
        distanceKm: distanceMeters / 1000,
        durationMinutes: durationMinutes,
      );
    } on TimeoutException catch (e) {
      final errorMsg = '[$serviceName] Timeout après 15s: $e';
      developer.log('❌ $errorMsg');
      print('❌ $errorMsg');
      return null;
    } on SocketException catch (e) {
      final errorMsg = '[$serviceName] Erreur réseau: $e';
      developer.log('❌ $errorMsg');
      print('❌ $errorMsg');
      return null;
    } catch (e) {
      final errorMsg = '[$serviceName] Erreur: $e';
      developer.log('❌ $errorMsg');
      print('❌ $errorMsg');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
