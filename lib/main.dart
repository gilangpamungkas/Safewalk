import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_places_api_flutter/google_places_api_flutter.dart';
// ignore: implementation_imports
import 'package:google_places_api_flutter/src/domain/google_api/place_details_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const SafeWalkApp());
}

class SafeWalkApp extends StatelessWidget {
  const SafeWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeWalk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const PermissionWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// ================= PERMISSION WRAPPER =================
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
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      setState(() => _granted = true);
    } else {
      // FIX: Handle denial so the UI doesn't spin forever
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
    return const SafeWalkHomePage();
  }
}

/// ================= HOME PAGE =================
class SafeWalkHomePage extends StatefulWidget {
  const SafeWalkHomePage({super.key});

  @override
  State<SafeWalkHomePage> createState() => _SafeWalkHomePageState();
}

class _SafeWalkHomePageState extends State<SafeWalkHomePage> {
  String selectedDestination = '';
  LatLng? selectedLatLng;
  final TextEditingController _searchController = TextEditingController();

  final List<String> quickSelect = [
    'Home',
    'Work',
    'Gym',
    "Friend's Place",
    'Station',
    'Market',
  ];

  /// Called by onPlaceSelected — PlaceDetailsModel already contains lat/lng
  /// when isLatLongRequired: true, so no manual HTTP call is needed.
  void _onPlaceSelected(Prediction prediction, PlaceDetailsModel? details) {
    if (!mounted) return;

    final lat = details?.result?.geometry?.location?.lat;
    final lng = details?.result?.geometry?.location?.lng;

    if (lat == null || lng == null) {
      debugPrint("Place selected but lat/lng missing: ${prediction.description}");
      return;
    }

    setState(() {
      selectedDestination = prediction.description;
      selectedLatLng = LatLng(lat, lng);
      _searchController.text = selectedDestination;
    });

    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeWalk'),
        actions: [
          IconButton(icon: const Icon(Icons.history), onPressed: () {}),
          IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.shield, size: 64, color: Colors.blue.shade700),
                const SizedBox(height: 16),
                const Text(
                  'Start Your SafeWalk',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                /// ===== GOOGLE PLACES SEARCH =====
                /// v2.0.0 requires: apiKey, itemBuilder, onPlaceSelected.
                /// Styling is done via decorationBuilder since inputDecoration
                /// is not a parameter on this widget.
                PlaceSearchField(
                  controller: _searchController,
                  apiKey: apiKey,
                  isLatLongRequired: true,
                  itemBuilder: (context, prediction) => ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(prediction.description),
                  ),
                  onPlaceSelected: _onPlaceSelected,
                ),

                const SizedBox(height: 16),

                /// ===== QUICK SELECT CHIPS =====
                /// FIX: Removed hardcoded London LatLng from quick-select chips.
                /// Quick-select destinations without a known coordinate now open
                /// a geocode lookup instead of silently routing to London.
                Wrap(
                  spacing: 8,
                  children: quickSelect.map((item) {
                    final isSelected = selectedDestination == item;
                    return ChoiceChip(
                      label: Text(item),
                      selected: isSelected,
                      onSelected: (_) async {
                        // Geocode the quick-select label so it resolves to a
                        // real location rather than a hardcoded fallback.
                        await _geocodeQuickSelect(item);
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                /// ===== START WALKING BUTTON =====
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedLatLng == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoutePage(
                                  destination: selectedDestination,
                                  destinationLatLng: selectedLatLng!,
                                ),
                              ),
                            ),
                    child: const Text('Start Walking'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// FIX: Geocode a plain-text label (used for quick-select chips).
  /// Uses the Geocoding API so chips resolve to real map coordinates.
  Future<void> _geocodeQuickSelect(String label) async {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';
    final url =
        "https://maps.googleapis.com/maps/api/geocode/json?"
        "address=${Uri.encodeComponent(label)}&key=$apiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body);
      if (json["status"] == "OK") {
        final loc = json["results"][0]["geometry"]["location"];
        if (!mounted) return;
        setState(() {
          selectedDestination = label; // keep the chip label as display name
          selectedLatLng = LatLng(
            (loc["lat"] as num).toDouble(),
            (loc["lng"] as num).toDouble(),
          );
          _searchController.text = label;
        });
      } else {
        debugPrint("Geocode error for '$label': ${json["status"]}");
      }
    } catch (e) {
      debugPrint("_geocodeQuickSelect error: $e");
    }
  }
}

/// ================= ROUTE PAGE =================
class RoutePage extends StatefulWidget {
  final String destination;
  final LatLng destinationLatLng;

  const RoutePage({
    super.key,
    required this.destination,
    required this.destinationLatLng,
  });

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  GoogleMapController? mapController;
  LatLng? currentPosition;
  Set<Polyline> polylines = {};
  StreamSubscription<Position>? positionStream;
  Timer? timer;
  int seconds = 0;

  // FIX: Track whether the map and location are both ready before drawing.
  bool _mapReady = false;
  bool _locationReady = false;

  static const LatLng defaultLocation = LatLng(51.5074, -0.1278);

  @override
  void initState() {
    super.initState();
    _startTimer();
    _initLocation();
  }

  void _startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => seconds++);
    });
  }

  Future<void> _initLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;

      setState(() {
        currentPosition = LatLng(position.latitude, position.longitude);
        _locationReady = true;
      });

      _listenToLocation();

      // FIX: Only draw route when BOTH map controller and location are ready.
      _tryDrawRoute();
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _listenToLocation() {
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) {
      if (!mounted) return;

      setState(() {
        currentPosition = LatLng(position.latitude, position.longitude);
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLng(currentPosition!),
      );
    });
  }

  /// FIX: Unified gate — only proceed when both location and map are ready.
  void _tryDrawRoute() {
    if (_mapReady && _locationReady) {
      _drawRoute();
    }
  }

  Future<void> _drawRoute() async {
    if (currentPosition == null || mapController == null) return;

    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

    // v3.1.0: apiKey goes in the PolylinePoints constructor, NOT in PolylineRequest.
    final polylinePoints = PolylinePoints(apiKey: apiKey);

    final request = PolylineRequest(
      origin: PointLatLng(
          currentPosition!.latitude, currentPosition!.longitude),
      destination: PointLatLng(
        widget.destinationLatLng.latitude,
        widget.destinationLatLng.longitude,
      ),
      mode: TravelMode.walking,
    );

    try {
      final result =
          await polylinePoints.getRouteBetweenCoordinates(request: request);

      if (!mounted) return;

      if (result.points.isNotEmpty) {
        final route = result.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        setState(() {
          polylines = {
            Polyline(
              polylineId: const PolylineId("route"),
              points: route,
              width: 6,
              color: Colors.blue,
            ),
          };
        });

        _fitBounds(route);
      } else {
        debugPrint("No polyline points returned. Error: ${result.errorMessage}");
      }
    } catch (e) {
      debugPrint("Polyline Error: $e");
    }
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty || mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    positionStream?.cancel();
    // FIX: Null out mapController after dispose to prevent late callbacks
    // from calling methods on a disposed controller.
    mapController?.dispose();
    mapController = null;
    super.dispose();
  }

  String _getFormattedTime() {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = (seconds % 60).toString().padLeft(2, '0');
    // FIX: Show hours when the walk exceeds 59:59
    if (hours > 0) {
      return "$hours:${minutes.toString().padLeft(2, '0')}:$secs";
    }
    return "$minutes:$secs";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SafeWalk Active")),
      body: currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: currentPosition ?? defaultLocation,
                      zoom: 15,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    polylines: polylines,
                    markers: {
                      Marker(
                        markerId: const MarkerId("destination"),
                        position: widget.destinationLatLng,
                        infoWindow: InfoWindow(title: widget.destination),
                      ),
                    },
                    onMapCreated: (controller) {
                      mapController = controller;
                      // FIX: Set _mapReady flag and use the unified gate
                      // instead of calling _drawRoute() directly, avoiding
                      // the race condition where currentPosition is still null.
                      setState(() => _mapReady = true);
                      _tryDrawRoute();
                    },
                  ),
                ),
// AFTER
Container(
  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
  decoration: const BoxDecoration(
    color: Colors.white,
    borderRadius:
        BorderRadius.vertical(top: Radius.circular(20)),
    boxShadow: [
      BoxShadow(color: Colors.black12, blurRadius: 10)
    ],
  ),
  child: SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Destination: ${widget.destination}",
            style:
                const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            _getFormattedTime(),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("I'm Safe - End Trip"),
            ),
          ),
        ],
      ),
    ),
  ),
),
              ],
            ),
    );
  }
}