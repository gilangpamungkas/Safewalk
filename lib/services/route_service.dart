import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// A single route alternative with metadata.
class RouteAlternative {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
  final String summary;
  final int index;

  const RouteAlternative({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    required this.summary,
    required this.index,
  });
}

class RouteService {
  /// Fetches walking polyline points between [origin] and [destination].
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

  /// Fetches up to 3 walking route alternatives from Google Directions API.
  static Future<List<RouteAlternative>> getWalkingRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=walking'
      '&alternatives=true'
      '&key=$apiKey',
    );

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('RouteService alternatives: HTTP ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body);
      if (json['status'] != 'OK') {
        debugPrint('RouteService alternatives: ${json['status']}');
        return [];
      }

      final routes = json['routes'] as List;
      final alternatives = <RouteAlternative>[];

      for (int i = 0; i < routes.length; i++) {
        final route = routes[i];

        // Decode polyline
        final encodedPolyline =
            route['overview_polyline']['points'] as String;
        final decoded = PolylinePoints.decodePolyline(encodedPolyline);
        final points = decoded
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        if (points.isEmpty) continue;

        // Distance and duration from first leg
        final leg = route['legs'][0];
        final distanceM =
            (leg['distance']['value'] as num).toDouble();
        final durationS =
            (leg['duration']['value'] as num).toInt();

        // Summary
        String summary = route['summary'] as String? ?? '';
        if (summary.isEmpty) {
          final steps = leg['steps'] as List;
          if (steps.isNotEmpty) {
            summary = steps.first['html_instructions'] as String? ?? '';
            summary = summary.replaceAll(RegExp(r'<[^>]*>'), '');
            if (summary.length > 40) {
              summary = '${summary.substring(0, 40)}...';
            }
          }
        }
        if (summary.isEmpty) summary = 'Route ${i + 1}';

        alternatives.add(RouteAlternative(
          points: points,
          distanceKm: distanceM / 1000,
          durationMinutes: (durationS / 60).ceil(),
          summary: summary,
          index: i,
        ));
      }

      debugPrint(
        'RouteService: ${alternatives.length} alternatives found',
      );
      return alternatives;
    } catch (e) {
      debugPrint('RouteService.getWalkingRouteAlternatives error: $e');
      return [];
    }
  }

  /// Geocodes a plain-text [label] into a [LatLng].
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

  /// Returns evenly sampled points from [points].
  static List<LatLng> sampleRoutePoints(
    List<LatLng> points, {
    int step = 5,
  }) {
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

  /// Calculates total route distance in km using the Haversine formula.
  static double calculateRouteDistanceKm(List<LatLng> points) {
    double totalKm = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalKm += _haversineKm(points[i], points[i + 1]);
    }
    return totalKm;
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(a.latitude)) *
            cos(_toRad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * asin(sqrt(h));
  }

  static double _toRad(double deg) => deg * pi / 180;
}