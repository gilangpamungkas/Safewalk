import 'package:flutter/material.dart';
import '../services/combined_safety_score.dart';

/// Displays the combined safety score badge in the route page bottom panel.
class SafetyBadge extends StatelessWidget {
  final bool isLoading;
  final CombinedSafetyScore? result;

  const SafetyBadge({
    super.key,
    required this.isLoading,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Analysing route safety...'),
        ],
      );
    }

    if (result == null) return const SizedBox.shrink();

    final osm = result!.osmResult;
    final frontageLabel = osm.frontageLabel;
    final frontageColor = _frontageColor(osm.activeFrontageCount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: result!.safetyColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: result!.safetyColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label + score pill ─────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                result!.safetyLabel,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: result!.safetyColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: result!.safetyColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${result!.safetyScore}/100',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Progress bar ───────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: result!.safetyScore / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                result!.safetyColor,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Crime summary ──────────────────────────────────
          Row(
            children: [
              const Icon(Icons.local_police,
                  size: 13, color: Colors.black45),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  result!.crimeSummary,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          // ── Collision summary ──────────────────────────────
          Row(
            children: [
              const Icon(Icons.car_crash,
                  size: 13, color: Colors.black45),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  result!.collisionSummary,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          // ── Infrastructure summary ─────────────────────────
          Row(
            children: [
              const Icon(Icons.streetview,
                  size: 13, color: Colors.black45),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  result!.osmSummary,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 8),

          // ── Street activity detail chip ────────────────────
          _DetailChip(
            icon: Icons.storefront,
            label: frontageLabel,
            sublabel: _frontageSubLabel(osm.activeFrontageCount),
            color: frontageColor,
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 6),

          // ── Data source note ───────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 11, color: Colors.black26),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Crime: Met Police (${result!.crimePeriodLabel}) · '
                  'Collisions: Dept for Transport '
                  '(${result!.collisionPeriodLabel}) · '
                  'Infrastructure: OpenStreetMap '
                  '(${result!.osmPeriodLabel})',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black38,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Plain-English explanation of street activity level.
  String _frontageSubLabel(int count) {
    if (count == 0) {
      return 'No shops or cafes near this route — quieter street';
    }
    if (count >= 10) {
      return '$count businesses nearby — well-watched, active street';
    }
    if (count >= 5) {
      return '$count businesses nearby — some street activity';
    }
    if (count == 1) {
      return '1 business near route — limited street activity';
    }
    return '$count businesses near route — limited street activity';
  }

  Color _frontageColor(int count) {
    if (count >= 10) return Colors.green;
    if (count >= 5) return Colors.amber;
    if (count >= 1) return Colors.orange;
    return Colors.grey;
  }
}

/// Small detail chip showing an icon, label and sublabel.
class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;

  const _DetailChip({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}