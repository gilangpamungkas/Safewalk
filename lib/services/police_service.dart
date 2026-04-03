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

  /// Queries the Police API for crimes along [sampledPoints].
  /// Uses street-level crimes endpoint for broader coverage.
  static Future<CrimeResult> getCrimesAlongRoute(
    List<LatLng> sampledPoints,
  ) async {
    int totalCrimes = 0;
    int violentCrimes = 0;

    // Use a known available date — API has 3-4 month lag
    // TODO: replace with dynamic latest-available date once confirmed working
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

        debugPrint(
          'PoliceService: ${point.latitude},${point.longitude} '
          '→ status ${response.statusCode}',
        );

        if (response.statusCode != 200) continue;

        final List crimes = jsonDecode(response.body);

        debugPrint(
          'PoliceService: ${point.latitude},${point.longitude} '
          '→ ${crimes.length} crimes',
        );

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