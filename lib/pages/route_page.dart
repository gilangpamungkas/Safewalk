import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/police_service.dart';
import '../services/road_safety_service.dart';
import '../services/osm_service.dart';
import '../services/report_service.dart';
import '../services/combined_safety_score.dart';
import '../widgets/safety_badge.dart';
import '../widgets/sos_button.dart';
import '../widgets/report_button.dart';

class RoutePage extends StatefulWidget {
  final String origin;
  final LatLng originLatLng;
  final String destination;
  final LatLng destinationLatLng;
  final TimeOfDay walkingTime;
  final List<LatLng>? preloadedRoute;

  const RoutePage({
    super.key,
    required this.origin,
    required this.originLatLng,
    required this.destination,
    required this.destinationLatLng,
    required this.walkingTime,
    this.preloadedRoute,
  });

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  double _currentHeading = 0.0;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  StreamSubscription<LatLng>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  Timer? _timer;
  int _seconds = 0;

  bool _mapReady = false;
  bool _locationReady = false;
  bool _headingUp = false;
  bool _tripStarted = false;
  bool _legendVisible = true;
  bool _disposed = false;

  List<LatLng> _fullRoute = [];
  double _totalRouteKm = 0;
  double _walkedKm = 0;
  double _remainingKm = 0;

  bool _safetyLoading = false;
  CombinedSafetyScore? _safetyScore;

  // User reports
  List<UserReport> _userReports = [];

  static const double _walkingSpeedKmh = 5.0;

  @override
  void initState() {
    super.initState();
    _initMarkers();
    _initLocation();
    _listenToCompass();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  void _listenToCompass() {
    _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      if (_disposed || !mounted) return;
      if (event.heading != null) {
        _safeSetState(() => _currentHeading = event.heading!);
        if (_tripStarted && _headingUp && _currentPosition != null) {
          _updateCamera(_currentPosition!);
        }
      }
    });
  }

  void _initMarkers() {
    _safeSetState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('origin'),
          position: widget.originLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(title: '📍 ${widget.origin}'),
          zIndex: 3,
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: '🏁 ${widget.destination}'),
          zIndex: 3,
        ),
      };
    });
  }

  void _buildAllMarkers({
    required List<CrimePoint> crimePoints,
    required List<CollisionPoint> collisionPoints,
    List<UserReport>? userReports,
  }) {
    if (_disposed || !mounted) return;

    final highConcernCrimes =
        crimePoints.where((c) => c.isViolent).toList();

    final Map<String, List<CrimePoint>> grouped = {};
    for (final crime in highConcernCrimes) {
      final key =
          '${crime.location.latitude},${crime.location.longitude}';
      grouped.putIfAbsent(key, () => []).add(crime);
    }

    final crimeMarkers = grouped.entries.map((entry) {
      final crimes = entry.value;
      final count = crimes.length;
      final latestMonth = crimes
          .map((c) => c.month)
          .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
      final latestLabel =
          crimes.firstWhere((c) => c.month == latestMonth).monthLabel;
      final title = count > 1
          ? '$count incidents at this location'
          : crimes.first.category;
      final snippet = '${crimes.first.street} · latest: $latestLabel';

      return Marker(
        markerId: MarkerId('crime_${entry.key}'),
        position: crimes.first.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
        infoWindow: InfoWindow(title: title, snippet: snippet),
        alpha: 0.85,
        zIndex: 1,
      );
    }).toSet();

    final collisionMarkers = collisionPoints.map((collision) {
      return Marker(
        markerId: MarkerId(
          'collision_${collision.lat}_${collision.lng}_${collision.date}',
        ),
        position: collision.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          collision.isFatal
              ? BitmapDescriptor.hueViolet
              : BitmapDescriptor.hueOrange,
        ),
        infoWindow: InfoWindow(
          title: collision.label,
          snippet: collision.snippet,
        ),
        alpha: 0.9,
        zIndex: 1,
      );
    }).toSet();

    // ── User report markers ────────────────────────────────
    final reportMarkers = (userReports ?? _userReports).map((report) {
      return Marker(
        markerId: MarkerId('report_${report.id}'),
        position: report.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueCyan,
        ),
        infoWindow: InfoWindow(
          title: '${report.emoji} ${report.label}',
          snippet: report.description?.isNotEmpty == true
              ? report.description
              : 'Reported by community',
        ),
        alpha: 0.95,
        zIndex: 2,
      );
    }).toSet();

    _safeSetState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('origin'),
          position: widget.originLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(title: '📍 ${widget.origin}'),
          zIndex: 3,
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: '🏁 ${widget.destination}'),
          zIndex: 3,
        ),
        ...crimeMarkers,
        ...collisionMarkers,
        ...reportMarkers,
      };
    });
  }

  /// Loads user reports from Firestore and refreshes markers.
  Future<void> _loadUserReports() async {
    if (_fullRoute.isEmpty || _disposed || !mounted) return;
    try {
      final reports = await ReportService.getReportsNearRoute(_fullRoute);
      if (_disposed || !mounted) return;
      _safeSetState(() => _userReports = reports);

      // Rebuild markers to include new reports
      if (_safetyScore != null) {
        _buildAllMarkers(
          crimePoints: _safetyScore!.crimeResult.crimePoints,
          collisionPoints:
              _safetyScore!.collisionResult.collisionPoints,
          userReports: reports,
        );
      }

      debugPrint(
        'ReportService: loaded ${reports.length} reports near route',
      );
    } catch (e) {
      debugPrint('ReportService: error loading reports: $e');
    }
  }

  void _startTrip() {
    _safeSetState(() {
      _tripStarted = true;
      _headingUp = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !mounted) return;
      _safeSetState(() => _seconds++);
    });

    if (_currentPosition != null) _updateCamera(_currentPosition!);
  }

  Future<void> _initLocation() async {
    final position = await LocationService.getCurrentPosition();
    if (_disposed || !mounted || position == null) return;

    _safeSetState(() {
      _currentPosition = position;
      _locationReady = true;
    });

    _listenToLocation();
    _tryDrawRoute();
  }

  void _listenToLocation() {
    _positionStream =
        LocationService.positionStream().listen((position) {
      if (_disposed || !mounted) return;
      _safeSetState(() {
        _currentPosition = position;
        if (_tripStarted) _updateProgress(position);
      });
      if (_tripStarted) _updateCamera(position);
    });
  }

  void _updateCamera(LatLng position) {
    if (_disposed || _mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: _headingUp ? 17 : 15,
          bearing: _headingUp ? _currentHeading : 0,
          tilt: _headingUp ? 30 : 0,
        ),
      ),
    );
  }

  void _toggleHeadingUp() {
    _safeSetState(() => _headingUp = !_headingUp);
    if (_currentPosition != null) _updateCamera(_currentPosition!);
  }

  void _updateProgress(LatLng current) {
    if (_fullRoute.isEmpty || _totalRouteKm == 0) return;

    int closestIndex = 0;
    double minDist = double.infinity;
    for (int i = 0; i < _fullRoute.length; i++) {
      final d = _haversineKm(current, _fullRoute[i]);
      if (d < minDist) {
        minDist = d;
        closestIndex = i;
      }
    }

    double walked = 0;
    for (int i = 0; i < closestIndex; i++) {
      walked += _haversineKm(_fullRoute[i], _fullRoute[i + 1]);
    }

    double remaining = 0;
    for (int i = closestIndex; i < _fullRoute.length - 1; i++) {
      remaining += _haversineKm(_fullRoute[i], _fullRoute[i + 1]);
    }

    _safeSetState(() {
      _walkedKm = walked;
      _remainingKm = remaining;
    });
  }

  void _tryDrawRoute() {
    if (_mapReady && _locationReady) {
      _drawRoute();
    }
  }

  void _buildColouredPolylines(
    List<LatLng> route,
    List<double> scores,
  ) {
    if (_disposed || !mounted) return;
    if (route.length < 2 || scores.isEmpty) return;

    final coloured = <Polyline>{};
    for (int i = 0; i < route.length - 1; i++) {
      final score = i < scores.length ? scores[i] : 50.0;
      coloured.add(Polyline(
        polylineId: PolylineId('seg_$i'),
        points: [route[i], route[i + 1]],
        width: 7,
        color: OsmService.scoreToColor(score),
      ));
    }

    _safeSetState(() => _polylines = coloured);
  }

  Future<void> _drawRoute() async {
    final route = widget.preloadedRoute ??
        await RouteService.getWalkingRoute(
          origin: widget.originLatLng,
          destination: widget.destinationLatLng,
        );

    if (_disposed || !mounted || route.isEmpty) return;

    final totalKm = RouteService.calculateRouteDistanceKm(route);

    _safeSetState(() {
      _fullRoute = route;
      _totalRouteKm = totalKm;
      _remainingKm = totalKm;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: route,
          width: 6,
          color: Colors.blue,
        ),
      };
    });

    if (_disposed || _mapController == null) return;
    final bounds = RouteService.boundsFromPoints(route);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );

    _safeSetState(() => _safetyLoading = true);

    final sampled = RouteService.sampleRoutePoints(route);

    // Run all data sources in parallel including user reports
    final results = await Future.wait([
      PoliceService.getCrimesAlongRoute(
        sampled,
        fullRoute: route,
        routeDistanceKm: totalKm,
      ),
      RoadSafetyService.getCollisionsAlongRoute(route),
      OsmService.getInfrastructureScore(route),
      ReportService.getReportsNearRoute(route),
    ]);

    if (_disposed || !mounted) return;

    final crimeResult = results[0] as CrimeResult;
    final collisionResult = results[1] as CollisionResult;
    final osmResult = results[2] as OsmResult;
    final userReports = results[3] as List<UserReport>;

    _safeSetState(() => _userReports = userReports);

    if (osmResult.routePointScores.isNotEmpty) {
      _buildColouredPolylines(route, osmResult.routePointScores);
    }

    final combinedScore = CombinedSafetyScore(
      crimeResult: crimeResult,
      collisionResult: collisionResult,
      osmResult: osmResult,
      routeDistanceKm: totalKm,
      walkingTime: widget.walkingTime,
    );

    debugPrint(
      'CombinedScore: ${combinedScore.safetyScore}/100 '
      '(${combinedScore.safetyLabel}) — '
      'crime: ${combinedScore.crimeDensity.toStringAsFixed(2)}, '
      'collision: ${combinedScore.collisionDensity.toStringAsFixed(2)}, '
      'osm: ${osmResult.infrastructureScore.toStringAsFixed(1)}, '
      'time: ×${combinedScore.timeMultiplier} '
      '(${combinedScore.timePeriodLabel}), '
      'reports: ${userReports.length}',
    );

    _safeSetState(() {
      _safetyScore = combinedScore;
      _safetyLoading = false;
    });

    _buildAllMarkers(
      crimePoints: crimeResult.crimePoints,
      collisionPoints: collisionResult.collisionPoints,
      userReports: userReports,
    );
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(a.latitude)) *
            cos(_toRad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * asin(sqrt(h));
  }

  double _toRad(double deg) => deg * pi / 180;

  int get _estimatedMinutesRemaining =>
      (_remainingKm / _walkingSpeedKmh * 60).ceil();

  double get _progressFraction =>
      _totalRouteKm > 0
          ? (_walkedKm / _totalRouteKm).clamp(0.0, 1.0)
          : 0.0;

  String _formatDistance(double km) {
    if (km < 1.0) return '${(km * 1000).round()}m';
    return '${km.toStringAsFixed(1)}km';
  }

  String _getFormattedTime() {
    final hours = _seconds ~/ 3600;
    final minutes = (_seconds % 3600) ~/ 60;
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$secs';
    }
    return '$minutes:$secs';
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _positionStream?.cancel();
    _positionStream = null;
    _compassStream?.cancel();
    _compassStream = null;
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tripStarted ? 'SafeWalk Active' : 'Plan Your Route'),
        bottom: !_tripStarted && _safetyScore != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_safetyScore!.timePeriodLabel} · '
                    '${widget.walkingTime.format(context)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // ── Google Map ──────────────────────────
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: widget.originLatLng,
                          zoom: 15,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        polylines: _polylines,
                        markers: _markers,
                        onMapCreated: (controller) {
                          if (_disposed) {
                            controller.dispose();
                            return;
                          }
                          _mapController = controller;
                          _safeSetState(() => _mapReady = true);
                          _tryDrawRoute();
                        },
                      ),

                      // ── Report button — bottom right above SOS
                      Positioned(
                        bottom: 80,
                        right: 12,
                        child: ReportButton(
                          currentPosition: _currentPosition,
                          onReportSubmitted: _loadUserReports,
                        ),
                      ),

                      // ── SOS button — bottom right ───────────
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: SosButton(
                          currentPosition: _currentPosition,
                        ),
                      ),

                      // ── Floating legend — bottom left ───────
                      if (_safetyScore != null)
                        Positioned(
                          bottom: 12,
                          left: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _safeSetState(
                                  () =>
                                      _legendVisible = !_legendVisible,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withOpacity(0.92),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.map,
                                          size: 12,
                                          color: Colors.black54),
                                      const SizedBox(width: 4),
                                      Text(
                                        _legendVisible
                                            ? 'Hide legend'
                                            : 'Show legend',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_legendVisible) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withOpacity(0.92),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      _LegendItem(
                                          color: Colors.blue,
                                          label: 'Origin'),
                                      SizedBox(height: 3),
                                      _LegendItem(
                                          color: Colors.green,
                                          label: 'Destination'),
                                      SizedBox(height: 3),
                                      _LegendItem(
                                          color: Colors.red,
                                          label: 'High-concern incident'),
                                      SizedBox(height: 3),
                                      _LegendItem(
                                          color: Colors.deepPurple,
                                          label: 'Fatal collision'),
                                      SizedBox(height: 3),
                                      _LegendItem(
                                          color: Colors.orange,
                                          label: 'Serious collision'),
                                      SizedBox(height: 3),
                                      _LegendItem(
                                          color: Colors.cyan,
                                          label: 'Community report'),
                                      SizedBox(height: 6),
                                      Divider(
                                          height: 1,
                                          color: Colors.black12),
                                      SizedBox(height: 6),
                                      _PathLegendItem(
                                          color: Colors.green,
                                          label: 'Good path'),
                                      SizedBox(height: 3),
                                      _PathLegendItem(
                                          color: Colors.amber,
                                          label: 'Moderate path'),
                                      SizedBox(height: 3),
                                      _PathLegendItem(
                                          color: Colors.orange,
                                          label: 'Poor path'),
                                      SizedBox(height: 3),
                                      _PathLegendItem(
                                          color: Colors.red,
                                          label: 'Dangerous path'),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Bottom panel
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
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
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 16, color: Colors.green),
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

                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),

                          // ===== NAVIGATION PROGRESS =====
                          if (_tripStarted && _totalRouteKm > 0) ...[
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: [
                                _statBox(
                                  icon: Icons.timer,
                                  label: 'Elapsed',
                                  value: _getFormattedTime(),
                                  color: Colors.blue,
                                ),
                                _statBox(
                                  icon: Icons.schedule,
                                  label: 'Remaining',
                                  value:
                                      '~$_estimatedMinutesRemaining min',
                                  color: Colors.orange,
                                ),
                                _statBox(
                                  icon: Icons.directions_walk,
                                  label: 'Walked',
                                  value: _formatDistance(_walkedKm),
                                  color: Colors.green,
                                ),
                                _statBox(
                                  icon: Icons.flag,
                                  label: 'To go',
                                  value: _formatDistance(_remainingKm),
                                  color: Colors.red,
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${(_progressFraction * 100).round()}% completed',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54),
                                    ),
                                    Text(
                                      _formatDistance(_totalRouteKm),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _progressFraction,
                                    minHeight: 6,
                                    backgroundColor:
                                        Colors.grey.shade200,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
  Colors.blue,
),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                          ],

                          // ===== PLANNING MODE =====
                          if (!_tripStarted && _totalRouteKm > 0) ...[
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: [
                                _statBox(
                                  icon: Icons.straighten,
                                  label: 'Distance',
                                  value: _formatDistance(_totalRouteKm),
                                  color: Colors.blue,
                                ),
                                _statBox(
                                  icon: Icons.schedule,
                                  label: 'Est. time',
                                  value:
                                      '~${(_totalRouteKm / _walkingSpeedKmh * 60).ceil()} min',
                                  color: Colors.orange,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                          ],

                          // Safety badge
                          SafetyBadge(
                            isLoading: _safetyLoading,
                            result: _safetyScore,
                          ),

                          // Community reports count
                          if (_userReports.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.people,
                                    size: 13, color: Colors.cyan),
                                const SizedBox(width: 4),
                                Text(
                                  '${_userReports.length} community '
                                  '${_userReports.length == 1 ? 'report' : 'reports'} near route',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 12),

                          // ===== BUTTONS =====
                          if (!_tripStarted) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _safetyLoading ? null : _startTrip,
                                icon:
                                    const Icon(Icons.directions_walk),
                                label: const Text('Start Trip'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _toggleHeadingUp,
                                  icon: Icon(
                                    _headingUp
                                        ? Icons.navigation
                                        : Icons.explore,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _headingUp ? 'Heading' : 'North',
                                    style: const TextStyle(
                                        fontSize: 12),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _headingUp
                                        ? Colors.blue
                                        : Colors.grey,
                                    side: BorderSide(
                                      color: _headingUp
                                          ? Colors.blue
                                          : Colors.grey,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.pop(context),
                                    child: const Text(
                                        "I'm Safe - End Trip"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black45),
        ),
      ],
    );
  }
}

/// Pin legend item.
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

/// Path legend item — coloured line.
class _PathLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _PathLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}