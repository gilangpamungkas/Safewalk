import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../pages/splash_page.dart';

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _granted = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      setState(() => _granted = true);
    } else {
      setState(() => _denied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Location permission is required to use SafeWalk.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    setState(() => _denied = false);
                    await _requestLocationPermission();
                  },
                  child: const Text('Grant Permission'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_granted) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Routes to SplashPage which then decides:
    // first launch → OnboardingPage → HomePage
    // returning user → HomePage directly
    return const SplashPage();
  }
}