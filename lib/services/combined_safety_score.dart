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

  const CombinedSafetyScore({
    required this.crimeResult,
    required this.collisionResult,
    required this.osmResult,
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
  double get crimeRiskScore => _riskScore(crimeDensity, knee: 50);

  /// Collision risk score (0–100, higher = more risky)
  double get collisionRiskScore => _riskScore(collisionDensity, knee: 15);

  /// OSM infrastructure risk score (0–100, higher = more risky)
  /// Inverted from infrastructureScore since higher infra = safer
  double get osmRiskScore =>
      (100 - osmResult.infrastructureScore).clamp(0.0, 100.0);

  /// Combined risk score:
  /// - Crime 60%       — pedestrian-specific, route-relevant
  /// - Collision 25%   — road danger, all users
  /// - OSM infra 15%   — pavement, lighting, speed limits
  ///
  /// OSM weight is lower because:
  /// - Not all segments have full tag coverage
  /// - Infrastructure is slower to change than crime patterns
  double get combinedRiskScore =>
      (crimeRiskScore * 0.60) +
      (collisionRiskScore * 0.25) +
      (osmRiskScore * 0.15);

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

  /// OSM infrastructure summary.
  String get osmSummary => osmResult.summary;

  /// Date range label for crime data.
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
  String get collisionPeriodLabel => '2022–2024';

  /// OSM data is continuously updated by volunteers.
  String get osmPeriodLabel => 'live data';
}