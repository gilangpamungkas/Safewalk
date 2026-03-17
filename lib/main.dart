import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_places_api_flutter/google_places_api_flutter.dart';
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

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      setState(() => _granted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    'Home', 'Work', 'Gym', "Friend's Place", 'Station', 'Market',
  ];

  /// Fetch place details and update selectedDestination & selectedLatLng
  Future<void> _selectPlace(Prediction prediction) async {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';
    final placeId = prediction.place_id;
    if (placeId == null) return;

    final detailUrl =
        "https://maps.googleapis.com/maps/api/place/details/json?"
        "place_id=$placeId&key=$apiKey";

    final response = await http.get(Uri.parse(detailUrl));
    final json = jsonDecode(response.body);

    if (json["status"] == "OK") {
      final loc = json["result"]["geometry"]["location"];
      setState(() {
        selectedDestination = json["result"]["name"];
        selectedLatLng = LatLng(loc["lat"], loc["lng"]);
        _searchController.text = selectedDestination;
      });

      // Dismiss the keyboard and close the prediction overlay
      FocusManager.instance.primaryFocus?.unfocus();
    }
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
                PlaceSearchField(
                  controller: _searchController,
                  apiKey: apiKey,
                  isLatLongRequired: true,
                  onPlaceSelected: (Prediction prediction, _) async {
                    await _selectPlace(prediction);
                  },
                  itemBuilder: (context, suggestion) {
                    return ListTile(
                      title: Text(suggestion.description ?? ""),
                      onTap: () async {
                        // We removed PlaceSearchField.of(context) here as it was causing the crash.
                        // _selectPlace handles the state update and UI cleanup.
                        await _selectPlace(suggestion);
                      },
                    );
                  },
                ),

                const SizedBox(height: 16),

                /// ===== QUICK SELECT CHIPS =====
                Wrap(
                  spacing: 8,
                  children: quickSelect.map((item) {
                    final isSelected = selectedDestination == item;
                    return ChoiceChip(
                      label: Text(item),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          selectedDestination = item;
                          // Note: You may want to replace this default LatLng with saved coordinates later
                          selectedLatLng = const LatLng(51.5074, -0.1278); 
                          _searchController.text = selectedDestination;
                        });
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
      });

      _listenToLocation();

      if (mapController != null) {
        _drawRoute();
      }
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

  Future<void> _drawRoute() async {
    if (currentPosition == null || mapController == null) return;

    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';
    final polylinePoints = PolylinePoints(apiKey: apiKey);

    final request = PolylineRequest(
      origin: PointLatLng(currentPosition!.latitude, currentPosition!.longitude),
      destination: PointLatLng(
        widget.destinationLatLng.latitude,
        widget.destinationLatLng.longitude,
      ),
      mode: TravelMode.walking,
    );

    try {
      final result = await polylinePoints.getRouteBetweenCoordinates(request: request);

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
    mapController?.dispose();
    super.dispose();
  }

  String _getFormattedTime() {
    final minutes = (seconds ~/ 60);
    final secs = (seconds % 60).toString().padLeft(2, '0');
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
                      _drawRoute();
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Destination: ${widget.destination}",
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Text(_getFormattedTime(),
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue)),
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
              ],
            ),
    );
  }
}