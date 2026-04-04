import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Individual crime data point.
class CrimePoint {
  final String id;
  final String category;
  final String street;
  final LatLng location;
  final bool isViolent;

  const CrimePoint({
    required this.id,
    required this.category,
    required this.street,
    required this.location,
    required this.isViolent,
  });
}

/// Result model returned by [PoliceService.getCrimesAlongRoute].
class CrimeResult {
  final int totalCrimes;
  final int violentCrimes;
  final int sampledPoints;
  final List<CrimePoint> crimePoints;
  final double routeDistanceKm;

  const CrimeResult({
    required this.totalCrimes,
    required this.violentCrimes,
    required this.sampledPoints,
    required this.crimePoints,
    required this.routeDistanceKm,
  });

  /// Crimes per km — normalises score for route length
  double get crimeDensity =>
      routeDistanceKm > 0 ? totalCrimes / routeDistanceKm : 0;

  double get violentDensity =>
      routeDistanceKm > 0 ? violentCrimes / routeDistanceKm : 0;

  String get safetyLabel {
    if (violentDensity >= 3 || crimeDensity >= 15) return '⚠️ High Risk Area';
    if (violentDensity >= 1 || crimeDensity >= 5) return '⚡ Moderate Risk';
    return '✅ Relatively Safe';
  }

  Color get safetyColor {
    if (violentDensity >= 3 || crimeDensity >= 15) return Colors.red;
    if (violentDensity >= 1 || crimeDensity >= 5) return Colors.orange;
    return Colors.green;
  }

  String get summary =>
      '$totalCrimes crimes on route ($violentCrimes violent)';
}

class PoliceService {
  static const _baseUrl = 'https://data.police.uk/api';

  /// Max distance in metres a crime can be from the route to be counted.
  static const double _maxRouteDistanceMetres = 80;

  static Future<CrimeResult> getCrimesAlongRoute(
    List<LatLng> sampledPoints, {
    required List<LatLng> fullRoute,
    required double routeDistanceKm,
  }) async {
    final Set<String> seenIds = {};
    final List<CrimePoint> crimePoints = [];
    int totalCrimes = 0;
    int violentCrimes = 0;

    const dateStr = '2024-10';

    for (final point in sampledPoints) {
      try {
        final uri = Uri.parse(
          '$_baseUrl/crimes-street/all-crime'
          '?date=$dateStr'
          '&lat=${point.latitude}'
          '&lng=${point.longitude}',
        );

        final response = await http.get(uri);
        if (response.statusCode != 200) continue;

        final List crimes = jsonDecode(response.body);

        for (final crime in crimes) {
          final id = crime['persistent_id'] as String? ??
              crime['id'].toString();

          if (seenIds.contains(id)) continue;

          final lat = double.tryParse(
                crime['location']?['latitude'] as String? ?? '',
              ) ??
              point.latitude;
          final lng = double.tryParse(
                crime['location']?['longitude'] as String? ?? '',
              ) ??
              point.longitude;

          final crimeLatLng = LatLng(lat, lng);

          // ✅ Only count crimes that are close to the actual route
          if (!_isNearRoute(crimeLatLng, fullRoute)) continue;

          seenIds.add(id);

          final category = crime['category'] as String? ?? 'unknown';
          final street = crime['location']?['street']?['name'] as String? ??
              'Unknown street';
          final isViolent =
              category == 'violent-crime' || category == 'robbery';

          crimePoints.add(CrimePoint(
            id: id,
            category: _formatCategory(category),
            street: street,
            location: crimeLatLng,
            isViolent: isViolent,
          ));

          totalCrimes++;
          if (isViolent) violentCrimes++;
        }

        debugPrint(
          'PoliceService: ${point.latitude},${point.longitude} '
          '→ $totalCrimes on-route crimes so far',
        );
      } catch (e) {
        debugPrint('PoliceService error at $point: $e');
      }
    }

    debugPrint(
      'PoliceService: final → $totalCrimes on-route crimes, '
      '$violentCrimes violent, ${routeDistanceKm.toStringAsFixed(2)} km',
    );

    return CrimeResult(
      totalCrimes: totalCrimes,
      violentCrimes: violentCrimes,
      sampledPoints: sampledPoints.length,
      crimePoints: crimePoints,
      routeDistanceKm: routeDistanceKm,
    );
  }

  /// Returns true if [point] is within [_maxRouteDistanceMetres] of
  /// any segment of [route].
  static bool _isNearRoute(LatLng point, List<LatLng> route) {
    for (final routePoint in route) {
      if (_distanceMetres(point, routePoint) <= _maxRouteDistanceMetres) {
        return true;
      }
    }
    return false;
  }

  /// Calculates distance in metres between two coordinates
  /// using the Haversine formula.
  static double _distanceMetres(LatLng a, LatLng b) {
    const r = 6371000.0; // Earth radius in metres
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

  /// Converts API category slug to a readable label.
  static String _formatCategory(String category) {
    return category
        .split('-')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}