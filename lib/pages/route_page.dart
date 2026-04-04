import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/police_service.dart';
import '../widgets/safety_badge.dart';

class RoutePage extends StatefulWidget {
  final String origin;
  final LatLng originLatLng;
  final String destination;
  final LatLng destinationLatLng;

  const RoutePage({
    super.key,
    required this.origin,
    required this.originLatLng,
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
  Set<Marker> markers = {};
  StreamSubscription<LatLng>? positionStream;
  Timer? timer;
  int seconds = 0;

  bool _mapReady = false;
  bool _locationReady = false;

  bool _safetyLoading = false;
  CrimeResult? _crimeResult;

  static const LatLng defaultLocation = LatLng(51.5074, -0.1278);

  @override
  void initState() {
    super.initState();
    _startTimer();
    _initLocation();
    _initMarkers();
  }

  void _initMarkers() {
    setState(() {
      markers = {
        Marker(
          markerId: const MarkerId('origin'),
          position: widget.originLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(title: widget.origin),
          zIndex: 2,
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(title: widget.destination),
          zIndex: 2,
        ),
      };
    });
  }

  void _buildCrimeMarkers(List<CrimePoint> crimePoints) {
    final crimeMarkers = crimePoints.map((crime) {
      return Marker(
        markerId: MarkerId('crime_${crime.id}'),
        position: crime.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          crime.isViolent
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueYellow,
        ),
        infoWindow: InfoWindow(
          title: crime.category,
          snippet: crime.street,
        ),
        alpha: 0.85,
        zIndex: 1,
      );
    }).toSet();

    setState(() {
      markers = {
        Marker(
          markerId: const MarkerId('origin'),
          position: widget.originLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(title: widget.origin),
          zIndex: 2,
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(title: widget.destination),
          zIndex: 2,
        ),
        ...crimeMarkers,
      };
    });
  }

  void _startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => seconds++);
    });
  }

  Future<void> _initLocation() async {
    final position = await LocationService.getCurrentPosition();
    if (!mounted || position == null) return;

    setState(() {
      currentPosition = position;
      _locationReady = true;
    });

    _listenToLocation();
    _tryDrawRoute();
  }

  void _listenToLocation() {
    positionStream = LocationService.positionStream().listen((position) {
      if (!mounted) return;
      setState(() => currentPosition = position);
      mapController?.animateCamera(CameraUpdate.newLatLng(position));
    });
  }

  void _tryDrawRoute() {
    if (_mapReady && _locationReady) {
      _drawRoute();
    }
  }

  Future<void> _drawRoute() async {
    final route = await RouteService.getWalkingRoute(
      origin: widget.originLatLng,
      destination: widget.destinationLatLng,
    );

    if (!mounted || route.isEmpty) return;

    setState(() {
      polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: route,
          width: 6,
          color: Colors.blue,
        ),
      };
    });

    final bounds = RouteService.boundsFromPoints(route);
    mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));

    // Fetch crime data along the route
    setState(() => _safetyLoading = true);

    final sampled = RouteService.sampleRoutePoints(route);
    final distanceKm = RouteService.calculateRouteDistanceKm(route);

    final crimeResult = await PoliceService.getCrimesAlongRoute(
      sampled,
      fullRoute: route,
      routeDistanceKm: distanceKm,
    );

    if (mounted) {
      setState(() {
        _crimeResult = crimeResult;
        _safetyLoading = false;
      });
      _buildCrimeMarkers(crimeResult.crimePoints);
    }
  }

  String _getFormattedTime() {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = (seconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$secs';
    }
    return '$minutes:$secs';
  }

  @override
  void dispose() {
    timer?.cancel();
    positionStream?.cancel();
    mapController?.dispose();
    mapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SafeWalk Active')),
      body: currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.originLatLng,
                      zoom: 15,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    polylines: polylines,
                    markers: markers,
                    onMapCreated: (controller) {
                      mapController = controller;
                      setState(() => _mapReady = true);
                      _tryDrawRoute();
                    },
                  ),
                ),

                // Bottom panel
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Origin row
                          Row(
                            children: [
                              const Icon(Icons.my_location,
                                  size: 16, color: Colors.blue),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.origin,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Destination row
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.destination,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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
                          const SizedBox(height: 12),

                          // Safety badge
                          SafetyBadge(
                            isLoading: _safetyLoading,
                            result: _crimeResult,
                          ),

                          const SizedBox(height: 8),

                          // Map legend
                          if (_crimeResult != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.location_on,
                                    size: 14, color: Colors.red),
                                SizedBox(width: 4),
                                Text('Violent',
                                    style: TextStyle(fontSize: 11)),
                                SizedBox(width: 12),
                                Icon(Icons.location_on,
                                    size: 14, color: Colors.amber),
                                SizedBox(width: 4),
                                Text('Other crime',
                                    style: TextStyle(fontSize: 11)),
                                SizedBox(width: 12),
                                Icon(Icons.location_on,
                                    size: 14, color: Colors.blue),
                                SizedBox(width: 4),
                                Text('Origin',
                                    style: TextStyle(fontSize: 11)),
                              ],
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