import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RouteService {
  /// Fetches walking polyline points between [origin] and [destination].
  /// Returns an empty list if the route could not be fetched.
  static Future<List<LatLng>> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';
    final polylinePoints = PolylinePoints(apiKey: apiKey);

    final request = PolylineRequest(
      origin: PointLatLng(origin.latitude, origin.longitude),
      destination: PointLatLng(destination.latitude, destination.longitude),
      mode: TravelMode.walking,
    );

    try {
      final result = await polylinePoints.getRouteBetweenCoordinates(
        request: request,
      );

      if (result.points.isNotEmpty) {
        return result.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
      } else {
        debugPrint('No route points returned: ${result.errorMessage}');
        return [];
      }
    } catch (e) {
      debugPrint('RouteService error: $e');
      return [];
    }
  }

  /// Geocodes a plain-text [label] into a [LatLng].
  /// Returns null if geocoding fails.
  static Future<LatLng?> geocodeLabel(String label) async {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(label)}&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json['status'] == 'OK') {
        final loc = json['results'][0]['geometry']['location'];
        return LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
      } else {
        debugPrint("Geocode error for '$label': ${json['status']}");
        return null;
      }
    } catch (e) {
      debugPrint('RouteService.geocodeLabel error: $e');
      return null;
    }
  }

  /// Returns evenly sampled points from [points], taking one every [step] indices.
  static List<LatLng> sampleRoutePoints(List<LatLng> points, {int step = 5}) {
    final sampled = <LatLng>[];
    for (int i = 0; i < points.length; i += step) {
      sampled.add(points[i]);
    }
    if (sampled.isEmpty || sampled.last != points.last) {
      sampled.add(points.last);
    }
    return sampled;
  }

  /// Computes [LatLngBounds] that fit all [points].
  static LatLngBounds boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
