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
  /// Separates safe/dangerous areas much better than log scale.
  ///
  /// Calibrated against known London routes:
  /// - Richmond → Kew:          crime ~13/km  → should be 🟢 ~85
  /// - Muswell Hill:            crime ~10/km  → should be 🟢 ~88
  /// - Camden → Mornington:     crime ~494/km → should be 🔴 ~29
  static double _riskScore(double density, {required double knee}) {
    if (density <= 0) return 0;
    return (100 * density / (density + knee)).clamp(0.0, 100.0);
  }

  /// Crime risk score (0–100, higher = more risky)
  /// knee = 50: risk hits 50% at density 50/km
  /// → quiet streets (10-15/km) score ~17-23% risk ✅
  /// → Camden (494/km) scores ~91% risk ✅
  double get crimeRiskScore => _riskScore(crimeDensity, knee: 50);

  /// Collision risk score (0–100, higher = more risky)
  /// knee = 15: risk hits 50% at collision density 15/km
  /// → Richmond (3.14/km) scores ~17% risk ✅
  /// → Camden (28.79/km) scores ~66% risk ✅
  double get collisionRiskScore => _riskScore(collisionDensity, knee: 15);

  /// Combined risk:
  /// - Crime 70% — more granular, route-specific, pedestrian-relevant
  /// - Collision 30% — covers all road users not just pedestrians
  double get combinedRiskScore =>
      (crimeRiskScore * 0.7) + (collisionRiskScore * 0.3);

  /// 0–100 safety score. 100 = safest, 0 = most dangerous.
  int get safetyScore =>
      (100 - combinedRiskScore).round().clamp(0, 100);

  String get safetyLabel {
    if (safetyScore >= 75) return '🟢 Safe';
    if (safetyScore >= 50) return '🟡 Low Risk';
    if (safetyScore >= 30) return '🟠 Moderate Risk';
    return '🔴 High Risk';
  }

  Color get safetyColor {
    if (safetyScore >= 75) return Colors.green;
    if (safetyScore >= 50) return Colors.amber;
    if (safetyScore >= 30) return Colors.orange;
    return Colors.red;
  }

  String get crimeSummary =>
      '${crimeResult.totalCrimes} crimes '
      '(${crimeResult.violentCrimes} high-concern)';

  String get collisionSummary =>
      '${collisionResult.totalCollisions} collisions '
      '(${collisionResult.fatalCollisions} fatal, '
      '${collisionResult.seriousCollisions} serious)';
}