import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class LocationService {
  /// Gets the current device position once.
  static Future<LatLng?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  /// Returns a stream of position updates.
  static Stream<LatLng> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).map((pos) => LatLng(pos.latitude, pos.longitude));
  }

  /// Reverse geocodes a [LatLng] to a human-readable address.
  ///
  /// Returns the most specific useful label:
  /// - Named building/POI if available (e.g. "University College London")
  /// - Street address if no POI (e.g. "12 Gower Street, London")
  /// - Falls back to "Current Location" if geocoding fails
  static Future<String> reverseGeocode(LatLng position) async {
    try {
      final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) return 'Current Location';

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${position.latitude},${position.longitude}'
        '&key=$apiKey'
        '&result_type=establishment|point_of_interest|street_address',
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return 'Current Location';

      final json = jsonDecode(response.body);
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) return 'Current Location';

      // Try to find a named POI first (establishment, university, etc.)
      for (final result in results) {
        final types = List<String>.from(result['types'] ?? []);
        if (types.contains('establishment') ||
            types.contains('point_of_interest') ||
            types.contains('university') ||
            types.contains('school') ||
            types.contains('hospital') ||
            types.contains('transit_station')) {
          final name = result['name'] as String?;
          if (name != null && name.isNotEmpty) return name;
        }
      }

      // Fall back to formatted address of first result
      // Shorten it — remove country (UK) for brevity
      final formatted =
          results.first['formatted_address'] as String? ?? '';
      if (formatted.isEmpty) return 'Current Location';

      // Remove ", UK" or ", United Kingdom" suffix
      return formatted
          .replaceAll(', UK', '')
          .replaceAll(', United Kingdom', '')
          .trim();
    } catch (e) {
      debugPrint('LocationService: reverse geocode error: $e');
      return 'Current Location';
    }
  }
}