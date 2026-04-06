import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Pedestrian infrastructure assessment for a single OSM way.
class OsmSegment {
  final String highway;
  final bool isLit;
  final bool hasSidewalk;
  final bool footAllowed;
  final int maxSpeedKmh;
  final String surface;

  /// Geometry nodes of this OSM way — used for segment matching.
  final List<LatLng> nodes;

  const OsmSegment({
    required this.highway,
    required this.isLit,
    required this.hasSidewalk,
    required this.footAllowed,
    required this.maxSpeedKmh,
    required this.surface,
    required this.nodes,
  });

  /// Infrastructure safety score (0–100, higher = safer).
  double get infrastructureScore {
    double score = 50;

    switch (highway) {
      case 'footway':
      case 'pedestrian':
      case 'path':
        score = 90;
        break;
      case 'cycleway':
        score = 75;
        break;
      case 'living_street':
        score = 70;
        break;
      case 'residential':
        score = 60;
        break;
      case 'tertiary':
      case 'unclassified':
        score = 50;
        break;
      case 'secondary':
        score = 40;
        break;
      case 'primary':
        score = 30;
        break;
      case 'trunk':
      case 'motorway':
        score = 10;
        break;
      default:
        score = 50;
    }

    if (isLit) {
      score += 10;
    } else {
      score -= 15;
    }

    if (hasSidewalk) {
      score += 10;
    } else if (highway != 'footway' &&
        highway != 'pedestrian' &&
        highway != 'path') {
      score -= 10;
    }

    if (maxSpeedKmh > 0) {
      if (maxSpeedKmh <= 20) score += 5;
      else if (maxSpeedKmh <= 30) score += 0;
      else if (maxSpeedKmh <= 40) score -= 5;
      else if (maxSpeedKmh <= 60) score -= 10;
      else score -= 20;
    }

    switch (surface) {
      case 'asphalt':
      case 'concrete':
      case 'paving_stones':
        score += 2;
        break;
      case 'gravel':
      case 'dirt':
      case 'grass':
        score -= 5;
        break;
    }

    return score.clamp(0.0, 100.0);
  }

  /// Colour for polyline rendering based on infrastructure score.
  Color get segmentColor {
    final score = infrastructureScore;
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.amber;
    if (score >= 30) return Colors.orange;
    return Colors.red;
  }

  factory OsmSegment.fromElement(Map<String, dynamic> element) {
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    final geometry = element['geometry'] as List? ?? [];

    final highway = tags['highway'] as String? ?? 'unclassified';

    final litTag = tags['lit'] as String?;
    final isLit = litTag == 'yes' || litTag == '24/7';

    final sidewalk = tags['sidewalk'] as String? ??
        tags['sidewalk:both'] as String? ?? '';
    final hasSidewalk = sidewalk == 'yes' ||
        sidewalk == 'both' ||
        sidewalk == 'left' ||
        sidewalk == 'right' ||
        tags.containsKey('sidewalk:left') ||
        tags.containsKey('sidewalk:right');

    final foot = tags['foot'] as String?;
    final footAllowed = foot != 'no' && foot != 'private';

    int maxSpeedKmh = 0;
    final maxspeed = tags['maxspeed'] as String?;
    if (maxspeed != null) {
      if (maxspeed.contains('mph')) {
        final mph =
            int.tryParse(maxspeed.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        maxSpeedKmh = (mph * 1.60934).round();
      } else {
        maxSpeedKmh =
            int.tryParse(maxspeed.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }
    }

    final surface = tags['surface'] as String? ?? '';

    // Parse geometry nodes
    final nodes = geometry.map<LatLng>((node) {
      return LatLng(
        (node['lat'] as num).toDouble(),
        (node['lon'] as num).toDouble(),
      );
    }).toList();

    return OsmSegment(
      highway: highway,
      isLit: isLit,
      hasSidewalk: hasSidewalk,
      footAllowed: footAllowed,
      maxSpeedKmh: maxSpeedKmh,
      surface: surface,
      nodes: nodes,
    );
  }
}

/// Result returned by [OsmService].
class OsmResult {
  final double infrastructureScore;
  final int totalSegments;
  final int litSegments;
  final int sidewalkSegments;
  final double avgSpeedLimit;

  /// Per route-point infrastructure scores for polyline colouring.
  /// One score per point in the route (except the last).
  final List<double> routePointScores;

  const OsmResult({
    required this.infrastructureScore,
    required this.totalSegments,
    required this.litSegments,
    required this.sidewalkSegments,
    required this.avgSpeedLimit,
    required this.routePointScores,
  });

  static const empty = OsmResult(
    infrastructureScore: 50,
    totalSegments: 0,
    litSegments: 0,
    sidewalkSegments: 0,
    avgSpeedLimit: 0,
    routePointScores: [],
  );

  String get summary {
    if (totalSegments == 0) return 'No infrastructure data';
    final litPct = (litSegments / totalSegments * 100).round();
    return '$litPct% lit · '
        '${sidewalkSegments > 0 ? "pavement available" : "no pavement data"}';
  }
}

class OsmService {
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const double _maxRouteDistanceMetres = 30;

  static Future<OsmResult> getInfrastructureScore(
    List<LatLng> fullRoute,
  ) async {
    if (fullRoute.isEmpty) return OsmResult.empty;

    // Build bounding box
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

    const pad = 0.001;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final query = '''
[out:json][timeout:15];
way["highway"]
  ["highway"!~"motorway|motorway_link|trunk_link"]
  ($minLat,$minLng,$maxLat,$maxLng);
out tags geom;
''';

    try {
      final response = await http.post(
        Uri.parse(_overpassUrl),
        body: {'data': query},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        debugPrint('OsmService: HTTP ${response.statusCode}');
        return OsmResult.empty;
      }

      final json = jsonDecode(response.body);
      final elements = json['elements'] as List? ?? [];

      if (elements.isEmpty) {
        debugPrint('OsmService: no elements returned');
        return OsmResult.empty;
      }

      // Parse all OSM ways with geometry
      final List<OsmSegment> allSegments = [];
      for (final element in elements) {
        if (element['type'] != 'way') continue;
        final tags = element['tags'] as Map<String, dynamic>? ?? {};
        final geometry = element['geometry'] as List? ?? [];
        if (geometry.isEmpty) continue;

        final foot = tags['foot'] as String?;
        if (foot == 'no' || foot == 'private') continue;

        allSegments.add(OsmSegment.fromElement(element));
      }

      if (allSegments.isEmpty) {
        debugPrint('OsmService: no walkable segments found');
        return OsmResult.empty;
      }

      // ── Per-route-point scoring ────────────────────────────
      // For each route point, find the nearest OSM way and use
      // its infrastructure score to colour that segment.
      final List<double> routePointScores = [];

      for (final routePoint in fullRoute) {
        double bestScore = 50; // default neutral
        double bestDist = double.infinity;

        for (final segment in allSegments) {
          for (final node in segment.nodes) {
            final dist = _distanceMetres(routePoint, node);
            if (dist < bestDist) {
              bestDist = dist;
              bestScore = segment.infrastructureScore;
            }
          }
        }

        routePointScores.add(bestScore);
      }

      // ── Aggregate score ────────────────────────────────────
      // Filter to only segments actually near the route
      final List<OsmSegment> nearSegments = allSegments.where((segment) {
        return segment.nodes.any(
          (node) => _isNearRoute(node, fullRoute),
        );
      }).toList();

      final avgScore = nearSegments.isEmpty
          ? 50.0
          : nearSegments
                  .map((s) => s.infrastructureScore)
                  .reduce((a, b) => a + b) /
              nearSegments.length;

      final litCount = nearSegments.where((s) => s.isLit).length;
      final sidewalkCount =
          nearSegments.where((s) => s.hasSidewalk).length;

      final speedSegments =
          nearSegments.where((s) => s.maxSpeedKmh > 0).toList();
      final avgSpeed = speedSegments.isEmpty
          ? 0.0
          : speedSegments
                  .map((s) => s.maxSpeedKmh.toDouble())
                  .reduce((a, b) => a + b) /
              speedSegments.length;

      debugPrint(
        'OsmService: ${nearSegments.length} near-route segments, '
        'avg score: ${avgScore.toStringAsFixed(1)}, '
        '$litCount lit, $sidewalkCount with sidewalk, '
        'avg speed: ${avgSpeed.toStringAsFixed(0)} km/h',
      );

      return OsmResult(
        infrastructureScore: avgScore,
        totalSegments: nearSegments.length,
        litSegments: litCount,
        sidewalkSegments: sidewalkCount,
        avgSpeedLimit: avgSpeed,
        routePointScores: routePointScores,
      );
    } catch (e) {
      debugPrint('OsmService error: $e');
      return OsmResult.empty;
    }
  }

  static bool _isNearRoute(LatLng point, List<LatLng> route) {
    for (final routePoint in route) {
      if (_distanceMetres(point, routePoint) <= _maxRouteDistanceMetres) {
        return true;
      }
    }
    return false;
  }

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

  /// Converts an infrastructure score to a polyline colour.
  static Color scoreToColor(double score) {
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.amber;
    if (score >= 30) return Colors.orange;
    return Colors.red;
  }
}