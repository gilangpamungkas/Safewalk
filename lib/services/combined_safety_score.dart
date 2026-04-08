import 'package:flutter/material.dart';
import 'police_service.dart';
import 'road_safety_service.dart';
import 'osm_service.dart';

/// Combines crime, collision and pedestrian infrastructure
/// data into a single safety score.
class CombinedSafetyScore {
  final CrimeResult crimeResult;
  final CollisionResult collisionResult;
  final OsmResult osmResult;
  final double routeDistanceKm;
  final TimeOfDay walkingTime;

  const CombinedSafetyScore({
    required this.crimeResult,
    required this.collisionResult,
    required this.osmResult,
    required this.routeDistanceKm,
    required this.walkingTime,
  });

  /// Crime weighted density per km.
  double get crimeDensity => routeDistanceKm > 0
      ? crimeResult.weightedScore / routeDistanceKm
      : 0;

  /// Collision weighted score per km.
  double get collisionDensity => routeDistanceKm > 0
      ? collisionResult.collisionScore / routeDistanceKm
      : 0;

  /// Time of day multiplier for crime risk.
  ///
  /// Crime patterns by hour (based on Met Police data patterns):
  /// - Daytime (09:00–17:00): baseline, multiplier = 1.0
  /// - Morning (06:00–09:00): quieter, multiplier = 0.7
  /// - Evening (17:00–20:00): moderate rise, multiplier = 1.2
  /// - Night (20:00–23:00): significant rise, multiplier = 1.5
  /// - Late night (23:00–03:00): highest risk, multiplier = 1.8
  /// - Very late (03:00–06:00): quieter but isolated, multiplier = 1.4
  double get timeMultiplier {
    final hour = walkingTime.hour;

    if (hour >= 6 && hour < 9) return 0.7;   // morning
    if (hour >= 9 && hour < 17) return 1.0;  // daytime — baseline
    if (hour >= 17 && hour < 20) return 1.2; // evening commute
    if (hour >= 20 && hour < 23) return 1.5; // night
    if (hour >= 23 || hour < 3) return 1.8;  // late night
    return 1.4;                               // very late (03:00–06:00)
  }

  /// Human readable time period label.
  String get timePeriodLabel {
    final hour = walkingTime.hour;
    if (hour >= 6 && hour < 9) return 'Morning';
    if (hour >= 9 && hour < 17) return 'Daytime';
    if (hour >= 17 && hour < 20) return 'Evening';
    if (hour >= 20 && hour < 23) return 'Night';
    if (hour >= 23 || hour < 3) return 'Late Night';
    return 'Very Late';
  }

  /// Power curve risk scoring.
  static double _riskScore(double density, {required double knee}) {
    if (density <= 0) return 0;
    return (100 * density / (density + knee)).clamp(0.0, 100.0);
  }

  /// Crime risk score — adjusted by time of day multiplier.
  double get crimeRiskScore =>
      (_riskScore(crimeDensity, knee: 50) * timeMultiplier).clamp(0.0, 100.0);

  /// Collision risk score — not affected by time of day.
  double get collisionRiskScore => _riskScore(collisionDensity, knee: 15);

  /// OSM infrastructure risk score.
  double get osmRiskScore =>
      (100 - osmResult.infrastructureScore).clamp(0.0, 100.0);

  /// Combined risk:
  /// - Crime 60%
  /// - Collision 25%
  /// - OSM infra 15%
  double get combinedRiskScore =>
      (crimeRiskScore * 0.60) +
      (collisionRiskScore * 0.25) +
      (osmRiskScore * 0.15);

  /// 0–100 safety score.
  int get safetyScore =>
      (100 - combinedRiskScore).round().clamp(0, 100);

  String get safetyLabel {
    if (safetyScore >= 75) return '🟢 Safe';
    if (safetyScore >= 55) return '🟡 Low Risk';
    if (safetyScore >= 30) return '🟠 Moderate Risk';
    return '🔴 High Risk';
  }

  Color get safetyColor {
    if (safetyScore >= 75) return Colors.green;
    if (safetyScore >= 55) return Colors.amber;
    if (safetyScore >= 30) return Colors.orange;
    return Colors.red;
  }

  String get crimeSummary =>
      '${crimeResult.totalCrimes} relevant crimes '
      '(${crimeResult.violentCrimes} high-concern incidents)';

  String get collisionSummary =>
      '${collisionResult.totalCollisions} road collisions '
      '(${collisionResult.fatalCollisions} fatal, '
      '${collisionResult.seriousCollisions} serious)';

  String get osmSummary => osmResult.summary;

  String get crimePeriodLabel {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 6);
    final to = DateTime(now.year, now.month - 4);
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May',
      'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[from.month]}–${months[to.month]} ${to.year}';
  }

  String get collisionPeriodLabel => '2022–2024';

  String get osmPeriodLabel => 'live data';
}