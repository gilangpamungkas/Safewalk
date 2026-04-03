import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Result model returned by [PoliceService.getCrimesAlongRoute].
class CrimeResult {
  final int totalCrimes;
  final int violentCrimes;
  final int sampledPoints;

  const CrimeResult({
    required this.totalCrimes,
    required this.violentCrimes,
    required this.sampledPoints,
  });

  /// Derives a safety label and colour from the crime counts.
  String get safetyLabel {
    if (violentCrimes >= 3 || totalCrimes >= 15) return '⚠️ High Risk Area';
    if (violentCrimes >= 1 || totalCrimes >= 5) return '⚡ Moderate Risk';
    return '✅ Relatively Safe';
  }

  Color get safetyColor {
    if (violentCrimes >= 3 || totalCrimes >= 15) return Colors.red;
    if (violentCrimes >= 1 || totalCrimes >= 5) return Colors.orange;
    return Colors.green;
  }

  String get summary => '$totalCrimes crimes nearby ($violentCrimes violent)';
}

class PoliceService {
  static const _baseUrl = 'https://data.police.uk/api';

  /// Queries the Police API for crimes at each of the [sampledPoints].
  /// [sampledPoints] should already be pre-sampled (e.g. via RouteService.sampleRoutePoints).
  static Future<CrimeResult> getCrimesAlongRoute(
    List<LatLng> sampledPoints,
  ) async {
    int totalCrimes = 0;
    int violentCrimes = 0;

    // Police API has ~2 month data lag
    final now = DateTime.now();
    final queryDate = DateTime(now.year, now.month - 2);
    final dateStr =
        '${queryDate.year}-${queryDate.month.toString().padLeft(2, '0')}';

    for (final point in sampledPoints) {
      try {
        final uri = Uri.parse(
          '$_baseUrl/crimes-at-location'
          '?date=$dateStr'
          '&lat=${point.latitude}'
          '&lng=${point.longitude}',
        );

        final response = await http.get(uri);
        if (response.statusCode != 200) continue;

        final List crimes = jsonDecode(response.body);
        totalCrimes += crimes.length;
        violentCrimes += crimes
            .where((c) =>
                c['category'] == 'violent-crime' ||
                c['category'] == 'robbery')
            .length;
      } catch (e) {
        debugPrint('PoliceService error at $point: $e');
      }
    }

    return CrimeResult(
      totalCrimes: totalCrimes,
      violentCrimes: violentCrimes,
      sampledPoints: sampledPoints.length,
    );
  }
}
