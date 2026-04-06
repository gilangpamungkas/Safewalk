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
  final String month;

  const CrimePoint({
    required this.id,
    required this.category,
    required this.street,
    required this.location,
    required this.isViolent,
    required this.month,
  });

  String get monthLabel {
    try {
      final parts = month.split('-');
      final year = parts[0];
      final monthNum = int.parse(parts[1]);
      const monthNames = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${monthNames[monthNum]} $year';
    } catch (_) {
      return month;
    }
  }
}

/// Raw crime result — score calculation moved to CombinedSafetyScore.
class CrimeResult {
  final int totalCrimes;
  final int violentCrimes;
  final int sampledPoints;
  final List<CrimePoint> crimePoints;
  final double routeDistanceKm;
  final double weightedScore;

  const CrimeResult({
    required this.totalCrimes,
    required this.violentCrimes,
    required this.sampledPoints,
    required this.crimePoints,
    required this.routeDistanceKm,
    required this.weightedScore,
  });

  String get summary =>
      '$totalCrimes crimes on route ($violentCrimes high-concern)';
}

class PoliceService {
  static const _baseUrl = 'https://data.police.uk/api';
  static const double _maxRouteDistanceMetres = 50;
  static const int _maxSamplePoints = 4;

  /// Pedestrian-relevant crime categories with weights.
  /// Only crimes that directly affect personal safety while walking.
  ///
  /// Weight 3.0 — immediate physical threat
  /// Weight 2.0 — high concern, likely to affect pedestrians
  /// Weight 1.0 — moderate concern, environmental indicator
  /// Not listed — irrelevant to pedestrian safety (burglary, vehicle crime etc)
  static const Map<String, double> _categoryWeights = {
    'violent-crime':          3.0, // assault, GBH
    'robbery':                3.0, // mugging, street robbery
    'possession-of-weapons':  3.0, // knife/weapon carrying
    'public-order':           2.0, // fighting, harassment, intimidation
    'theft-from-the-person':  2.0, // pickpocketing, bag snatching
    'drugs':                  1.0, // dealing hotspots = environmental risk
    'criminal-damage-arson':  1.0, // vandalism = area indicator
  };

  static List<String> _getQueryDates() {
    final now = DateTime.now();
    final dates = <String>[];
    for (int i = 4; i <= 6; i++) {
      final date = DateTime(now.year, now.month - i);
      dates.add(
        '${date.year}-${date.month.toString().padLeft(2, '0')}',
      );
    }
    return dates;
  }

  static double _recencyWeight(String month) {
    try {
      final parts = month.split('-');
      final crimeDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      final monthsAgo = DateTime.now().difference(crimeDate).inDays / 30;
      if (monthsAgo <= 3) return 1.0;
      if (monthsAgo <= 6) return 0.7;
      if (monthsAgo <= 12) return 0.4;
      return 0.2;
    } catch (_) {
      return 0.5;
    }
  }

  static List<LatLng> _limitSamplePoints(List<LatLng> points) {
    if (points.length <= _maxSamplePoints) return points;
    final step = (points.length / _maxSamplePoints).floor();
    final limited = <LatLng>[];
    for (int i = 0; i < points.length; i += step) {
      limited.add(points[i]);
      if (limited.length >= _maxSamplePoints) break;
    }
    if (limited.last != points.last) limited.add(points.last);
    return limited;
  }

  static Future<CrimeResult> getCrimesAlongRoute(
    List<LatLng> sampledPoints, {
    required List<LatLng> fullRoute,
    required double routeDistanceKm,
  }) async {
    final Set<String> seenIds = {};
    final List<CrimePoint> crimePoints = [];
    int totalCrimes = 0;
    int violentCrimes = 0;
    double weightedScore = 0;
    int skippedNoId = 0;
    int skippedDuplicate = 0;
    int skippedOffRoute = 0;
    int skippedIrrelevant = 0;

    final limitedPoints = _limitSamplePoints(sampledPoints);
    final queryDates = _getQueryDates();

    debugPrint(
      'PoliceService: ${limitedPoints.length} points × '
      '${queryDates.length} dates = '
      '${limitedPoints.length * queryDates.length} queries',
    );

    for (final dateStr in queryDates) {
      for (final point in limitedPoints) {
        try {
          final uri = Uri.parse(
            '$_baseUrl/crimes-street/all-crime'
            '?date=$dateStr'
            '&lat=${point.latitude}'
            '&lng=${point.longitude}',
          );

          final response = await http.get(uri).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('PoliceService: timeout at $point ($dateStr)');
              return http.Response('[]', 200);
            },
          );

          if (response.statusCode != 200) continue;

          final List crimes = jsonDecode(response.body);

          for (final crime in crimes) {
            // 1. Skip crimes with no stable persistent_id
            final id = crime['persistent_id'] as String?;
            if (id == null || id.isEmpty) {
              skippedNoId++;
              continue;
            }

            // 2. Get category early so we can filter irrelevant crimes
            //    BEFORE doing expensive route distance check
            final category = crime['category'] as String? ?? 'unknown';
            final categoryWeight = _categoryWeights[category];

            // Skip crimes not relevant to pedestrian safety
            if (categoryWeight == null) {
              skippedIrrelevant++;
              continue;
            }

            // 3. Mark as seen IMMEDIATELY before route check
            if (seenIds.contains(id)) {
              skippedDuplicate++;
              continue;
            }
            seenIds.add(id);

            // 4. Get crime coordinates
            final lat = double.tryParse(
                  crime['location']?['latitude'] as String? ?? '',
                ) ??
                point.latitude;
            final lng = double.tryParse(
                  crime['location']?['longitude'] as String? ?? '',
                ) ??
                point.longitude;

            final crimeLatLng = LatLng(lat, lng);

            // 5. Only count crimes within 50m of the actual route
            if (!_isNearRoute(crimeLatLng, fullRoute)) {
              skippedOffRoute++;
              continue;
            }

            final street =
                crime['location']?['street']?['name'] as String? ??
                    'Unknown street';
            final crimeMonth = crime['month'] as String? ?? dateStr;

            // High-concern = weight >= 2.0
            final isViolent = categoryWeight >= 2.0;

            crimePoints.add(CrimePoint(
              id: id,
              category: _formatCategory(category),
              street: street,
              location: crimeLatLng,
              isViolent: isViolent,
              month: crimeMonth,
            ));

            totalCrimes++;
            if (isViolent) violentCrimes++;

            // Score = category weight × recency weight
            final recency = _recencyWeight(crimeMonth);
            weightedScore += categoryWeight * recency;
          }
        } catch (e) {
          debugPrint('PoliceService error at $point ($dateStr): $e');
        }
      }
    }

    // Log all unique categories found for calibration
    final categories = crimePoints
        .map((c) => c.category)
        .toSet()
        .toList()..sort();
    debugPrint('Categories on route: $categories');

    debugPrint(
      'PoliceService: $totalCrimes on route, '
      '$skippedIrrelevant irrelevant, '
      '$skippedNoId no-id, '
      '$skippedDuplicate duplicates, '
      '$skippedOffRoute off-route, '
      '$violentCrimes high-concern, '
      'score: ${weightedScore.toStringAsFixed(1)}, '
      '${routeDistanceKm.toStringAsFixed(2)} km',
    );

    return CrimeResult(
      totalCrimes: totalCrimes,
      violentCrimes: violentCrimes,
      sampledPoints: limitedPoints.length,
      crimePoints: crimePoints,
      routeDistanceKm: routeDistanceKm,
      weightedScore: weightedScore,
    );
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

  static String _formatCategory(String category) {
    return category
        .split('-')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}