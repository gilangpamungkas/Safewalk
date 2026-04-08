import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/sos_service.dart';

class SosButton extends StatelessWidget {
  final LatLng? currentPosition;

  const SosButton({super.key, required this.currentPosition});

  void _onTap(BuildContext context) async {
    // Load contact before showing dialog
    final contact = await SosService.loadContact();
    final hasContact =
        contact['name'] != null && contact['phone'] != null &&
        contact['name']!.isNotEmpty && contact['phone']!.isNotEmpty;

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sos, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text(
              'Emergency Help',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Call 999 ──────────────────────────────
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await SosService.call999();
              },
              icon: const Icon(Icons.call, size: 18),
              label: const Text(
                'Call 999 — Emergency Services',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

            const SizedBox(height: 10),

            // ── SMS emergency contact ─────────────────
            ElevatedButton.icon(
              onPressed: hasContact
                  ? () async {
                      Navigator.pop(ctx);
                      final sent = await SosService.sendLocationSms(
                        currentPosition,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              sent
                                  ? '✅ Location sent to ${contact['name']}'
                                  : '❌ Failed to send SMS',
                            ),
                            backgroundColor:
                                sent ? Colors.green : Colors.red,
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.sms, size: 18),
              label: Text(
                hasContact
                    ? 'SMS ${contact['name']}'
                    : 'SMS Contact (not set)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade500,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

            // Hint if no contact set
            if (!hasContact) ...[
              const SizedBox(height: 6),
              const Text(
                'Set an emergency contact on the home screen',
                style: TextStyle(fontSize: 11, color: Colors.black45),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1, color: Colors.black12),
            const SizedBox(height: 6),

            // Disclaimer
            const Text(
              'Only use 999 in a genuine emergency.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sos, color: Colors.white, size: 22),
            Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}