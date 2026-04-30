import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class OsmSegment {
  final String highway;
  final bool isLit;
  final bool hasSidewalk;
  final bool footAllowed;
  final int maxSpeedKmh;
  final String surface;
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

  double get lengthMetres {
    double total = 0;
    for (int i = 0; i < nodes.length - 1; i++) {
      total += _haversineMetres(nodes[i], nodes[i + 1]);
    }
    return total;
  }

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

  Color get segmentColor {
    final score = infrastructureScore;
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.amber;
    if (score >= 30) return Colors.orange;
    return Colors.red;
  }

  static double _haversineMetres(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * asin(sqrt(h));
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

class OsmResult {
  final double infrastructureScore;
  final int totalSegments;
  final int litSegments;
  final int sidewalkSegments;
  final double avgSpeedLimit;
  final List<double> routePointScores;
  final int streetLampCount;
  final int activeFrontageCount;

  /// Distance-weighted lit percentage (0–100).
  /// Weighted by physical segment length so a long unlit road
  /// correctly outweighs a short lit alley.
  final double litDistancePct;

  const OsmResult({
    required this.infrastructureScore,
    required this.totalSegments,
    required this.litSegments,
    required this.sidewalkSegments,
    required this.avgSpeedLimit,
    required this.routePointScores,
    this.streetLampCount = 0,
    this.activeFrontageCount = 0,
    this.litDistancePct = 0,
  });

  static const empty = OsmResult(
    infrastructureScore: 50,
    totalSegments: 0,
    litSegments: 0,
    sidewalkSegments: 0,
    avgSpeedLimit: 0,
    routePointScores: [],
    streetLampCount: 0,
    activeFrontageCount: 0,
    litDistancePct: 0,
  );

  /// Summary uses distance-weighted lit% for accuracy.
  String get summary {
    if (totalSegments == 0) return 'No infrastructure data';
    final litPct = litDistancePct.round();
    return '$litPct% lit · '
        '${sidewalkSegments > 0 ? "pavement available" : "limited pavement"}';
  }

  /// Lighting label — always uses distance-weighted lit%.
  /// More reliable than lamp node count which is incomplete in OSM.
  String lampingLabel(double routeKm) {
    if (litDistancePct >= 80) return 'Well lit';
    if (litDistancePct >= 50) return 'Adequately lit';
    if (litDistancePct >= 20) return 'Dimly lit';
    return 'Poorly lit';
  }

  String get frontageLabel {
    if (activeFrontageCount >= 10) return 'Busy street';
    if (activeFrontageCount >= 5) return 'Some activity';
    if (activeFrontageCount >= 1) return 'Limited activity';
    return 'Quiet street';
  }
}

class OsmService {
  static const _overpassUrls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  static const double _maxRouteDistanceMetres = 30;

  static const _activeFrontageTypes = {
    'restaurant', 'cafe', 'bar', 'pub', 'fast_food',
    'shop', 'supermarket', 'convenience', 'pharmacy',
    'bank', 'post_office', 'library',
  };

  /// In-memory cache — keyed by rounded bounding box.
  /// OSM data changes weekly at most, so caching per session is safe.
  static final Map<String, OsmResult> _cache = {};

  static String _cacheKey(
    double minLat,
    double minLng,
    double maxLat,
    double maxLng,
  ) {
    return '${minLat.toStringAsFixed(3)}'
        '_${minLng.toStringAsFixed(3)}'
        '_${maxLat.toStringAsFixed(3)}'
        '_${maxLng.toStringAsFixed(3)}';
  }

  /// Queries Overpass with retry across mirror servers.
  /// Returns the first non-empty response or null if all fail.
  static Future<Map<String, dynamic>?> _queryOverpass(
      String query) async {
    for (int i = 0; i < _overpassUrls.length; i++) {
      final url = _overpassUrls[i];
      try {
        debugPrint('OsmService: trying $url (attempt ${i + 1})');

        final response = await http
            .post(
              Uri.parse(url),
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode != 200) {
          debugPrint('OsmService: HTTP ${response.statusCode} from $url');
          continue;
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = json['elements'] as List? ?? [];

        if (elements.isNotEmpty) {
          debugPrint('OsmService: ${elements.length} elements from $url');
          return json;
        }

        debugPrint('OsmService: empty response from $url');
      } catch (e) {
        debugPrint('OsmService: $url failed — $e');
      }

      if (i < _overpassUrls.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    debugPrint('OsmService: all mirrors failed or returned empty');
    return null;
  }

  static Future<OsmResult> getInfrastructureScore(
    List<LatLng> fullRoute,
  ) async {
    if (fullRoute.isEmpty) return OsmResult.empty;

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

    // ── Cache check ────────────────────────────────────────
    final cacheKey = _cacheKey(minLat, minLng, maxLat, maxLng);
    if (_cache.containsKey(cacheKey)) {
      debugPrint('OsmService: cache hit for $cacheKey');
      return _cache[cacheKey]!;
    }

    final query = '''
[out:json][timeout:25];
(
  way["highway"]
    ["highway"!~"motorway|motorway_link|trunk_link"]
    ($minLat,$minLng,$maxLat,$maxLng);
  node["highway"="street_lamp"]
    ($minLat,$minLng,$maxLat,$maxLng);
  node["amenity"~"restaurant|cafe|bar|pub|fast_food|pharmacy|bank|post_office|library"]
    ($minLat,$minLng,$maxLat,$maxLng);
  node["shop"]
    ($minLat,$minLng,$maxLat,$maxLng);
);
out tags geom;
''';

    try {
      final json = await _queryOverpass(query);

      if (json == null) {
        debugPrint('OsmService: returning empty — no data from any mirror');
        return OsmResult.empty;
      }

      final elements = json['elements'] as List? ?? [];

      // ── Parse elements ─────────────────────────────────────
      final List<OsmSegment> allSegments = [];
      int streetLampCount = 0;
      int activeFrontageCount = 0;

      for (final element in elements) {
        final type = element['type'] as String?;
        final tags = element['tags'] as Map<String, dynamic>? ?? {};

        if (type == 'way') {
          final geometry = element['geometry'] as List? ?? [];
          if (geometry.isEmpty) continue;
          final foot = tags['foot'] as String?;
          if (foot == 'no' || foot == 'private') continue;
          allSegments.add(OsmSegment.fromElement(element));
        } else if (type == 'node') {
          final lat = (element['lat'] as num?)?.toDouble();
          final lng = (element['lon'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          final nodeLatLng = LatLng(lat, lng);

          if (!_isNearRoute(nodeLatLng, fullRoute, maxDistance: 50)) {
            continue;
          }

          if (tags['highway'] == 'street_lamp') {
            streetLampCount++;
            continue;
          }

          final amenity = tags['amenity'] as String?;
          final shop = tags['shop'] as String?;
          if (amenity != null && _activeFrontageTypes.contains(amenity)) {
            activeFrontageCount++;
          } else if (shop != null) {
            activeFrontageCount++;
          }
        }
      }

      if (allSegments.isEmpty) {
        debugPrint('OsmService: no walkable segments found');
        return OsmResult.empty;
      }

      // ── Per-route-point scoring ────────────────────────────
      final List<double> routePointScores = [];
      for (final routePoint in fullRoute) {
        double bestScore = 50;
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

      // ── Near-route segments ────────────────────────────────
      final List<OsmSegment> nearSegments = allSegments.where((seg) {
        return seg.nodes.any((node) => _isNearRoute(node, fullRoute));
      }).toList();

      // ── Distance-weighted lit percentage ───────────────────
      double litMetres = 0;
      double totalMetres = 0;
      for (final seg in nearSegments) {
        final len = seg.lengthMetres;
        totalMetres += len;
        if (seg.isLit) litMetres += len;
      }
      final litDistancePct =
          totalMetres > 0 ? (litMetres / totalMetres * 100) : 0.0;

      // ── Distance-weighted infrastructure score ─────────────
      double weightedScoreSum = 0;
      double weightSum = 0;
      for (final seg in nearSegments) {
        final len = seg.lengthMetres.clamp(1.0, double.infinity);
        weightedScoreSum += seg.infrastructureScore * len;
        weightSum += len;
      }
      double avgScore =
          weightSum > 0 ? weightedScoreSum / weightSum : 50.0;

      // ── Lighting bonus — distance-weighted lit% only ───────
      if (litDistancePct >= 80) {
        avgScore += 5;
      } else if (litDistancePct >= 50) {
        avgScore += 2;
      } else if (litDistancePct < 20) {
        avgScore -= 5;
      }

      // ── Active frontage bonus ──────────────────────────────
      final routeKm = _estimateRouteKm(fullRoute);
      final frontagesPer100m =
          routeKm > 0 ? activeFrontageCount / (routeKm * 10) : 0.0;

      if (frontagesPer100m >= 3) {
        avgScore += 7;
      } else if (frontagesPer100m >= 1.5) {
        avgScore += 4;
      } else if (frontagesPer100m >= 0.5) {
        avgScore += 2;
      }

      avgScore = avgScore.clamp(0.0, 100.0);

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
        'OsmService: ${nearSegments.length} segments, '
        'score: ${avgScore.toStringAsFixed(1)}, '
        'lit: ${litDistancePct.toStringAsFixed(1)}% by distance '
        '($litCount/${nearSegments.length} segments), '
        '$streetLampCount lamps, '
        '$activeFrontageCount frontages '
        '(${frontagesPer100m.toStringAsFixed(1)}/100m)',
      );

      final result = OsmResult(
        infrastructureScore: avgScore,
        totalSegments: nearSegments.length,
        litSegments: litCount,
        sidewalkSegments: sidewalkCount,
        avgSpeedLimit: avgSpeed,
        routePointScores: routePointScores,
        streetLampCount: streetLampCount,
        activeFrontageCount: activeFrontageCount,
        litDistancePct: litDistancePct,
      );

      // ── Cache result ───────────────────────────────────────
      _cache[cacheKey] = result;
      debugPrint('OsmService: cached result for $cacheKey');

      return result;
    } catch (e) {
      debugPrint('OsmService error: $e');
      return OsmResult.empty;
    }
  }

  static double _estimateRouteKm(List<LatLng> points) {
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _distanceMetres(points[i], points[i + 1]);
    }
    return total / 1000;
  }

  static bool _isNearRoute(
    LatLng point,
    List<LatLng> route, {
    double maxDistance = 30,
  }) {
    for (final routePoint in route) {
      if (_distanceMetres(point, routePoint) <= maxDistance) {
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

  static Color scoreToColor(double score) {
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.amber;
    if (score >= 30) return Colors.orange;
    return Colors.red;
  }
}