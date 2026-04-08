import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A single user report category.
class ReportCategory {
  final String type;
  final String label;
  final String emoji;
  final Duration expiry;
  final Color color;

  const ReportCategory({
    required this.type,
    required this.label,
    required this.emoji,
    required this.expiry,
    required this.color,
  });
}

/// A report fetched from Firestore.
class UserReport {
  final String id;
  final String type;
  final String label;
  final String emoji;
  final LatLng location;
  final DateTime timestamp;
  final DateTime expiresAt;
  final int confirmed;
  final String? description;

  const UserReport({
    required this.id,
    required this.type,
    required this.label,
    required this.emoji,
    required this.location,
    required this.timestamp,
    required this.expiresAt,
    required this.confirmed,
    this.description,
  });
}

class ReportService {
  static final _db = FirebaseFirestore.instance;

  /// All report categories with their expiry durations.
  static const List<ReportCategory> categories = [
    ReportCategory(
      type: 'dangerous_animal',
      label: 'Dangerous Animal',
      emoji: '🐕',
      expiry: Duration(hours: 6),
      color: Colors.orange,
    ),
    ReportCategory(
      type: 'suspicious_activity',
      label: 'Suspicious Activity',
      emoji: '👁',
      expiry: Duration(hours: 4),
      color: Colors.red,
    ),
    ReportCategory(
      type: 'antisocial_behaviour',
      label: 'Antisocial Behaviour',
      emoji: '⚠️',
      expiry: Duration(days: 7),
      color: Colors.deepOrange,
    ),
    ReportCategory(
      type: 'broken_lighting',
      label: 'Broken Lighting',
      emoji: '💡',
      expiry: Duration(days: 14),
      color: Colors.amber,
    ),
    ReportCategory(
      type: 'blocked_pavement',
      label: 'Blocked Pavement',
      emoji: '🚧',
      expiry: Duration(days: 7),
      color: Colors.brown,
    ),
    ReportCategory(
      type: 'flooding',
      label: 'Flooding / Hazard',
      emoji: '🌊',
      expiry: Duration(hours: 24),
      color: Colors.blue,
    ),
    ReportCategory(
      type: 'all_clear',
      label: 'All Clear',
      emoji: '✅',
      expiry: Duration(hours: 2),
      color: Colors.green,
    ),
  ];

  /// Returns category info for a given type.
  static ReportCategory? categoryFor(String type) {
    try {
      return categories.firstWhere((c) => c.type == type);
    } catch (_) {
      return null;
    }
  }

  /// Submits a new report to Firestore.
  static Future<void> submitReport({
    required String type,
    required LatLng location,
    String? description,
  }) async {
    final category = categoryFor(type);
    if (category == null) return;

    final now = DateTime.now();
    final expiresAt = now.add(category.expiry);

    await _db.collection('reports').add({
      'type': type,
      'lat': location.latitude,
      'lng': location.longitude,
      'description': description ?? '',
      'timestamp': now.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'confirmed': 0,
    });

    debugPrint(
      'ReportService: submitted $type at '
      '${location.latitude},${location.longitude}, '
      'expires ${expiresAt.toIso8601String()}',
    );
  }

  /// Fetches active (non-expired) reports near a route.
  static Future<List<UserReport>> getReportsNearRoute(
    List<LatLng> route, {
    double radiusMetres = 100,
  }) async {
    if (route.isEmpty) return [];

    // Build bounding box around route
    double minLat = route.first.latitude;
    double maxLat = route.first.latitude;
    double minLng = route.first.longitude;
    double maxLng = route.first.longitude;

    for (final p in route) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Add padding
    const pad = 0.002;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final now = DateTime.now().toIso8601String();

    // Query Firestore — filter by bounding box and not expired
    final snapshot = await _db
        .collection('reports')
        .where('lat', isGreaterThan: minLat)
        .where('lat', isLessThan: maxLat)
        .where('expiresAt', isGreaterThan: now)
        .get();

    final reports = <UserReport>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();

      // Filter by longitude (Firestore can only filter one range at a time)
      if (lng < minLng || lng > maxLng) continue;

      final type = data['type'] as String? ?? '';
      final category = categoryFor(type);
      if (category == null) continue;

      reports.add(UserReport(
        id: doc.id,
        type: type,
        label: category.label,
        emoji: category.emoji,
        location: LatLng(lat, lng),
        timestamp: DateTime.parse(data['timestamp'] as String),
        expiresAt: DateTime.parse(data['expiresAt'] as String),
        confirmed: (data['confirmed'] as num?)?.toInt() ?? 0,
        description: data['description'] as String?,
      ));
    }

    debugPrint('ReportService: ${reports.length} active reports near route');
    return reports;
  }

  /// Confirms a report — increments confirmed count.
  static Future<void> confirmReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({
      'confirmed': FieldValue.increment(1),
    });
  }
}