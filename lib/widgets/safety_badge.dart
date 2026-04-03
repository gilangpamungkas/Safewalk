import 'package:flutter/material.dart';
import '../services/police_service.dart';

/// Displays the safety score badge in the route page bottom panel.
class SafetyBadge extends StatelessWidget {
  final bool isLoading;
  final CrimeResult? result;

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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: result!.safetyColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: result!.safetyColor),
      ),
      child: Column(
        children: [
          Text(
            result!.safetyLabel,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: result!.safetyColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            result!.summary,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
