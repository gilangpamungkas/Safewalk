import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'sos_service.dart';

/// Manages the arrival check-in countdown for a walk.
///
/// Usage:
///   1. Call [start] when trip begins — pass estimated minutes + last position.
///   2. Call [updatePosition] as the user moves.
///   3. Call [cancel] when user taps "I'm Safe".
///   4. Listen to [secondsRemaining] stream to update UI.
///   5. Provide [onWarning] callback — fired when timer hits 0, before SMS.
///   6. Provide [onAlertSent] callback — fired after SMS is sent.
class ArrivalCheckinService {
  static const int _bufferMinutes = 5;

  Timer? _timer;
  int _secondsRemaining = 0;
  LatLng? _lastPosition;
  bool _cancelled = false;
  bool _alertFired = false;

  final StreamController<int> _streamController =
      StreamController<int>.broadcast();

  /// Stream of seconds remaining — listen to drive the UI countdown.
  Stream<int> get secondsStream => _streamController.stream;

  int get secondsRemaining => _secondsRemaining;
  bool get isActive => _timer != null && _timer!.isActive;

  /// Start the check-in timer.
  ///
  /// [estimatedMinutes] — route estimated walk time.
  /// [currentPosition] — current GPS position for the SOS SMS.
  /// [onWarning] — called when countdown hits 0; show the dialog here.
  /// [onAlertSent] — called after SMS is dispatched.
  void start({
    required int estimatedMinutes,
    required LatLng currentPosition,
    required VoidCallback onWarning,
    required VoidCallback onAlertSent,
  }) {
    _cancelled = false;
    _alertFired = false;
    _lastPosition = currentPosition;

    // Total countdown = estimated walk time + 5 min buffer.
    final totalMinutes = estimatedMinutes + _bufferMinutes;
    _secondsRemaining = totalMinutes * 60;

    debugPrint(
      'ArrivalCheckin: started — ${totalMinutes}min countdown '
      '(${estimatedMinutes}min walk + ${_bufferMinutes}min buffer)',
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cancelled) {
        timer.cancel();
        return;
      }

      _secondsRemaining--;

      if (!_streamController.isClosed) {
        _streamController.add(_secondsRemaining);
      }

      if (_secondsRemaining <= 0 && !_alertFired) {
        _alertFired = true;
        timer.cancel();
        debugPrint('ArrivalCheckin: countdown expired — firing warning');
        onWarning(); // Show dialog first
        _sendAlert(onAlertSent);
      }
    });
  }

  /// Update the last known position — called from location stream.
  void updatePosition(LatLng position) {
    _lastPosition = position;
  }

  /// Cancel the check-in — call when user taps "I'm Safe".
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    debugPrint('ArrivalCheckin: cancelled by user — safe arrival confirmed');
  }

  /// Send the SOS SMS to the emergency contact.
  Future<void> _sendAlert(VoidCallback onAlertSent) async {
    // Small delay so the warning dialog fully renders before we try to
    // launch the SMS app — without this the intent gets suppressed on Android.
    await Future.delayed(const Duration(milliseconds: 800));
    try {
      await SosService.sendLocationSms(_lastPosition);
      debugPrint('ArrivalCheckin: SOS SMS sent');
      onAlertSent();
    } catch (e) {
      debugPrint('ArrivalCheckin: SMS send error — $e');
    }
  }

  void dispose() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _streamController.close();
  }

  /// Format remaining seconds as MM:SS string.
  static String formatSeconds(int seconds) {
    if (seconds <= 0) return '0:00';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}