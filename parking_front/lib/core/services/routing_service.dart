import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  /// Appelle l'API OSRM (gratuite) pour obtenir l'itinéraire en voiture.
  /// Retourne une liste de points [LatLng] représentant le chemin.
  static Future<List<LatLng>> getRoute(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      return [];
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;

    if (routes == null || routes.isEmpty) {
      return [];
    }

    final geometry = routes[0]['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;

    // GeoJSON utilise [lng, lat] — on convertit en LatLng(lat, lng)
    return coordinates.map<LatLng>((coord) {
      final c = coord as List<dynamic>;
      return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
    }).toList();
  }

  /// Extrait la durée estimée (en minutes) et la distance (en km).
  static Future<Map<String, double>?> getRouteInfo(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=false',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;

    if (routes == null || routes.isEmpty) return null;

    final route = routes[0] as Map<String, dynamic>;
    return {
      'duration': (route['duration'] as num).toDouble() / 60, // minutes
      'distance': (route['distance'] as num).toDouble() / 1000, // km
    };
  }
}
