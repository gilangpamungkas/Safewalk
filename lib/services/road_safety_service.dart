import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Individual collision data point from DfT road safety data.
class CollisionPoint {
  final double lat;
  final double lng;
  final String severity;
  final int casualties;
  final String date;
  final String speedLimit;
  final String light;
  final String weather;

  const CollisionPoint({
    required this.lat,
    required this.lng,
    required this.severity,
    required this.casualties,
    required this.date,
    required this.speedLimit,
    required this.light,
    required this.weather,
  });

  LatLng get location => LatLng(lat, lng);

  bool get isFatal => severity == 'Fatal';

  /// Severity weight for safety score calculation.
  /// Fatal = 5x, Serious = 2x
  double get severityWeight => isFatal ? 5.0 : 2.0;

  /// Human readable label for the marker tooltip.
  String get label => '$severity collision · $date';

  String get snippet =>
      '$casualties casualty · $light · $weather';

  factory CollisionPoint.fromJson(Map<String, dynamic> json) {
    return CollisionPoint(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      severity: json['severity'] as String? ?? 'Serious',
      casualties: (json['casualties'] as num?)?.toInt() ?? 1,
      date: json['date'] as String? ?? '',
      speedLimit: json['speed_limit'] as String? ?? '',
      light: json['light'] as String? ?? 'Unknown',
      weather: json['weather'] as String? ?? 'Unknown',
    );
  }
}

/// Result returned by [RoadSafetyService.getCollisionsAlongRoute].
class CollisionResult {
  final int totalCollisions;
  final int fatalCollisions;
  final int seriousCollisions;
  final List<CollisionPoint> collisionPoints;
  final double collisionScore; // weighted score for safety calculation

  const CollisionResult({
    required this.totalCollisions,
    required this.fatalCollisions,
    required this.seriousCollisions,
    required this.collisionPoints,
    required this.collisionScore,
  });

  /// Empty result when no collisions found.
  static const empty = CollisionResult(
    totalCollisions: 0,
    fatalCollisions: 0,
    seriousCollisions: 0,
    collisionPoints: [],
    collisionScore: 0,
  );

  String get summary {
    if (totalCollisions == 0) return 'No recorded collisions on route';
    return '$totalCollisions collisions on route '
        '($fatalCollisions fatal, $seriousCollisions serious)';
  }
}

class RoadSafetyService {
  /// Singleton — load asset once and reuse.
  static List<CollisionPoint>? _cachedCollisions;

  /// Max distance in metres a collision can be from route to be counted.
  static const double _maxRouteDistanceMetres = 50;

  /// Loads the bundled London collision JSON asset.
  /// Cached after first load so subsequent calls are instant.
  static Future<List<CollisionPoint>> _loadCollisions() async {
    if (_cachedCollisions != null) return _cachedCollisions!;

    try {
      final jsonString = await rootBundle
          .loadString('assets/london_collisions.json');
      final List data = jsonDecode(jsonString);
      _cachedCollisions = data
          .map((e) => CollisionPoint.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint(
        'RoadSafetyService: loaded ${_cachedCollisions!.length} collisions',
      );
      return _cachedCollisions!;
    } catch (e) {
      debugPrint('RoadSafetyService: failed to load asset — $e');
      return [];
    }
  }

  /// Returns all collisions within [_maxRouteDistanceMetres] of [fullRoute].
  static Future<CollisionResult> getCollisionsAlongRoute(
    List<LatLng> fullRoute,
  ) async {
    final allCollisions = await _loadCollisions();
    if (allCollisions.isEmpty) return CollisionResult.empty;

    // Build a bounding box around the route for fast pre-filtering
    // before doing expensive distance calculations
    double minLat = fullRoute.first.latitude;
    double maxLat = fullRoute.first.latitude;
    double minLng = fullRoute.first.longitude;
    double maxLng = fullRoute.first.longitude;

    for (final p in fullRoute) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Add ~0.001 degree padding (~100m) around bounding box
    const pad = 0.001;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    // Pre-filter by bounding box first (fast)
    final candidates = allCollisions.where((c) =>
        c.lat >= minLat &&
        c.lat <= maxLat &&
        c.lng >= minLng &&
        c.lng <= maxLng).toList();

    debugPrint(
      'RoadSafetyService: ${candidates.length} candidates in bounding box',
    );

    // Then filter by actual distance to route (precise)
    final List<CollisionPoint> onRoute = [];
    int fatalCount = 0;
    int seriousCount = 0;
    double score = 0;

    for (final collision in candidates) {
      if (_isNearRoute(collision.location, fullRoute)) {
        onRoute.add(collision);
        if (collision.isFatal) {
          fatalCount++;
        } else {
          seriousCount++;
        }
        score += collision.severityWeight;
      }
    }

    debugPrint(
      'RoadSafetyService: ${onRoute.length} collisions on route '
      '($fatalCount fatal, $seriousCount serious) '
      'score: ${score.toStringAsFixed(1)}',
    );

    return CollisionResult(
      totalCollisions: onRoute.length,
      fatalCollisions: fatalCount,
      seriousCollisions: seriousCount,
      collisionPoints: onRoute,
      collisionScore: score,
    );
  }

  /// Returns true if [point] is within [_maxRouteDistanceMetres]
  /// of any point on [route].
  static bool _isNearRoute(LatLng point, List<LatLng> route) {
    for (final routePoint in route) {
      if (_distanceMetres(point, routePoint) <= _maxRouteDistanceMetres) {
        return true;
      }
    }
    return false;
  }

  /// Haversine distance in metres between two coordinates.
  static double _distanceMetres(LatLng a, LatLng b) {
    const r = 6371000.0;
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