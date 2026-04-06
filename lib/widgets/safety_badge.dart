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
          // Label + score pill row
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

          // Progress bar — higher score = safer = more fill
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

          // Crime summary row
          Row(
            children: [
              const Icon(Icons.local_police,
                  size: 13, color: Colors.black45),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${result!.crimeSummary} · ${result!.crimePeriodLabel}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          // Collision summary row
          Row(
            children: [
              const Icon(Icons.car_crash,
                  size: 13, color: Colors.black45),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${result!.collisionSummary} · ${result!.collisionPeriodLabel}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 6),

          // Data source note
          Row(
            children: const [
              Icon(Icons.info_outline, size: 11, color: Colors.black26),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Crime: Met Police · Collisions: Dept for Transport',
                  style: TextStyle(
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
}