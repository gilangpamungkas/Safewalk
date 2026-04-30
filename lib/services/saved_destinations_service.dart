import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A single saved destination.
class SavedDestination {
  final String id;
  final String emoji;
  final String label;
  final String address;
  final LatLng latLng;

  const SavedDestination({
    required this.id,
    required this.emoji,
    required this.label,
    required this.address,
    required this.latLng,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'label': label,
        'address': address,
        'lat': latLng.latitude,
        'lng': latLng.longitude,
      };

  factory SavedDestination.fromJson(Map<String, dynamic> json) =>
      SavedDestination(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        label: json['label'] as String,
        address: json['address'] as String,
        latLng: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
      );
}

/// Manages up to 5 saved destinations in local storage.
class SavedDestinationsService {
  static const String _key = 'saved_destinations';
  static const int maxDestinations = 5;

  /// Load all saved destinations.
  static Future<List<SavedDestination>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SavedDestination.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SavedDestinations: load error — $e');
      return [];
    }
  }

  /// Save a new destination. Returns false if limit reached.
  static Future<bool> add(SavedDestination destination) async {
    final existing = await load();
    if (existing.length >= maxDestinations) return false;
    existing.add(destination);
    await _persist(existing);
    return true;
  }

  /// Update an existing destination by id.
  static Future<void> update(SavedDestination updated) async {
    final existing = await load();
    final index = existing.indexWhere((d) => d.id == updated.id);
    if (index != -1) {
      existing[index] = updated;
      await _persist(existing);
    }
  }

  /// Delete a destination by id.
  static Future<void> delete(String id) async {
    final existing = await load();
    existing.removeWhere((d) => d.id == id);
    await _persist(existing);
  }

  static Future<void> _persist(List<SavedDestination> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((d) => d.toJson()).toList()),
    );
  }

  /// Generate a unique id for a new destination.
  static String generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString();
}

/// Quick emoji picker options for destinations.
const List<String> destinationEmojis = [
  '🏠', '💼', '🏋️', '👟', '🛒', '🏥', '🎓', '☕',
  '🍽️', '🏖️', '⛪', '🎭', '🏟️', '🚉', '✈️', '❤️',
];