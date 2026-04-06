import 'package:flutter/material.dart';
import 'police_service.dart';
import 'road_safety_service.dart';

/// Combines crime data and road collision data into a single safety score.
class CombinedSafetyScore {
  final CrimeResult crimeResult;
  final CollisionResult collisionResult;
  final double routeDistanceKm;

  const CombinedSafetyScore({
    required this.crimeResult,
    required this.collisionResult,
    required this.routeDistanceKm,
  });

  /// Crime weighted density per km.
  double get crimeDensity => routeDistanceKm > 0
      ? crimeResult.weightedScore / routeDistanceKm
      : 0;

  /// Collision weighted score per km.
  /// Fatal = 5pts, Serious = 2pts.
  double get collisionDensity => routeDistanceKm > 0
      ? collisionResult.collisionScore / routeDistanceKm
      : 0;

  /// Power curve risk scoring.
  ///
  /// Formula: risk = 100 × density / (density + knee)
  ///
  /// The "knee" is the density at which risk = 50%.
  /// Below knee → mostly safe, above knee → mostly risky.
  ///
  /// Calibrated against known London routes:
  /// - Richmond → Kew:       crime ~8/km   → 🟢 80
  /// - Muswell Hill:         crime ~3/km   → 🟢 89
  /// - Clapham Common:       crime ~15/km  → 🟡 63
  /// - Hackney → London Fds: crime ~105/km → 🟠 34
  /// - Brixton:              crime ~150/km → 🔴 27
  /// - Shoreditch:           crime ~240/km → 🔴 22
  /// - Camden:               crime ~358/km → 🔴 17
  static double _riskScore(double density, {required double knee}) {
    if (density <= 0) return 0;
    return (100 * density / (density + knee)).clamp(0.0, 100.0);
  }

  /// Crime risk score (0–100, higher = more risky)
  /// knee = 50: risk hits 50% at density 50/km
  double get crimeRiskScore => _riskScore(crimeDensity, knee: 50);

  /// Collision risk score (0–100, higher = more risky)
  /// knee = 15: risk hits 50% at collision density 15/km
  double get collisionRiskScore => _riskScore(collisionDensity, knee: 15);

  /// Combined risk:
  /// - Crime 70% — pedestrian-specific, route-relevant
  /// - Collision 30% — covers all road users not just pedestrians
  double get combinedRiskScore =>
      (crimeRiskScore * 0.7) + (collisionRiskScore * 0.3);

  /// 0–100 safety score. 100 = safest, 0 = most dangerous.
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

  /// Crime summary — avoids alarming language.
  String get crimeSummary =>
      '${crimeResult.totalCrimes} relevant crimes '
      '(${crimeResult.violentCrimes} high-concern incidents)';

  /// Collision summary.
  String get collisionSummary =>
      '${collisionResult.totalCollisions} road collisions '
      '(${collisionResult.fatalCollisions} fatal, '
      '${collisionResult.seriousCollisions} serious)';

  /// Date range label for crime data.
  /// Police API has ~3-4 month lag so we query 4-6 months back.
  /// e.g. "Oct–Dec 2025"
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

  /// Date range label for collision data.
  /// DfT data covers 2022–2024 (3 years for statistical reliability).
  String get collisionPeriodLabel => '2022–2024';
}