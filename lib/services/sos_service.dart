import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SosService {
  static const _contactNameKey = 'sos_contact_name';
  static const _contactPhoneKey = 'sos_contact_phone';
  static const _userNameKey = 'sos_user_name';

  /// Calls 999 immediately.
  static Future<void> call999() async {
    final uri = Uri(scheme: 'tel', path: '999');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('SosService: cannot launch phone dialler');
    }
  }

  /// Sends SMS to saved emergency contact with current location.
  static Future<bool> sendLocationSms(LatLng? location) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_contactPhoneKey);
    final userName = prefs.getString(_userNameKey) ?? 'Someone';

    if (phone == null || phone.isEmpty) return false;

    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    final locationText = location != null
        ? 'https://maps.google.com/?q=${location.latitude},${location.longitude}'
        : null;

    final message = locationText != null
        ? '🚨 SOS Alert from $userName!\n\n'
          'I need help. This is my last known location:\n'
          '$locationText\n\n'
          'Sent via SafeWalk at $time'
        : '🚨 SOS Alert from $userName!\n\n'
          'I need help but my location is unavailable.\n\n'
          'Sent via SafeWalk at $time';

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return true;
    }
    return false;
  }

  /// Saves emergency contact to local storage.
  static Future<void> saveContact({
    required String name,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactNameKey, name);
    await prefs.setString(_contactPhoneKey, phone);
  }

  /// Saves the user's own name for SOS messages.
  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  /// Loads saved emergency contact.
  static Future<Map<String, String?>> loadContact() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString(_contactNameKey),
      'phone': prefs.getString(_contactPhoneKey),
    };
  }

  /// Loads the user's own name.
  static Future<String?> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  /// Returns true if an emergency contact is saved.
  static Future<bool> hasContact() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_contactPhoneKey);
    return phone != null && phone.isNotEmpty;
  }
}