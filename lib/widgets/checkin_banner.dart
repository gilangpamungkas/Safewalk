import 'package:flutter/material.dart';
import '../services/arrival_checkin_service.dart';

/// Persistent banner shown at the top of the map during an active walk.
/// Displays a countdown + reminder text, and pulses red when time is low.
class CheckinBanner extends StatefulWidget {
  final ArrivalCheckinService checkinService;
  final VoidCallback onSafeArrival;

  const CheckinBanner({
    super.key,
    required this.checkinService,
    required this.onSafeArrival,
  });

  @override
  State<CheckinBanner> createState() => _CheckinBannerState();
}

class _CheckinBannerState extends State<CheckinBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  int _seconds = 0;

  static const int _urgentThreshold = 120; // 2 minutes — start pulsing red

  @override
  void initState() {
    super.initState();

    _seconds = widget.checkinService.secondsRemaining;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    widget.checkinService.secondsStream.listen((seconds) {
      if (!mounted) return;
      setState(() => _seconds = seconds);

      // Start pulsing when under 2 minutes
      if (seconds <= _urgentThreshold && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _bannerColor {
    if (_seconds <= 60) return Colors.red.shade700;
    if (_seconds <= _urgentThreshold) return Colors.orange.shade700;
    return Colors.blue.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _seconds <= _urgentThreshold;
    final timeStr = ArrivalCheckinService.formatSeconds(_seconds);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: isUrgent ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        decoration: BoxDecoration(
          color: _bannerColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Clock icon
              const Icon(Icons.timer, color: Colors.white, size: 20),
              const SizedBox(width: 10),

              // Countdown + reminder text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isUrgent
                          ? '⚠️ Auto-alert in $timeStr'
                          : 'Auto-alert in $timeStr',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'Tap "I\'m Safe" when you arrive',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Quick I'm Safe button inside banner
              GestureDetector(
                onTap: widget.onSafeArrival,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "I'm Safe",
                    style: TextStyle(
                      color: _bannerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}