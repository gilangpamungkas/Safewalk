import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/route_service.dart';
import '../services/combined_safety_score.dart';

class RoutePickerPage extends StatefulWidget {
  final String origin;
  final LatLng originLatLng;
  final String destination;
  final LatLng destinationLatLng;
  final TimeOfDay walkingTime;
  final List<RouteAlternative> alternatives;
  final List<CombinedSafetyScore?> scores;

  const RoutePickerPage({
    super.key,
    required this.origin,
    required this.originLatLng,
    required this.destination,
    required this.destinationLatLng,
    required this.walkingTime,
    required this.alternatives,
    required this.scores,
  });

  @override
  State<RoutePickerPage> createState() => _RoutePickerPageState();
}

class _RoutePickerPageState extends State<RoutePickerPage> {
  GoogleMapController? _mapController;
  int _selectedIndex = 0;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  // Route colours
  static const _selectedColor = Color(0xFF1565C0);  // deep blue
  static const _unselectedColor = Color(0xFF9E9E9E); // grey

  @override
  void initState() {
    super.initState();
    _initMarkersAndPolylines();

    // Auto-select safest route
    int safestIndex = 0;
    int highestScore = -1;
    for (int i = 0; i < widget.scores.length; i++) {
      final s = widget.scores[i]?.safetyScore ?? 0;
      if (s > highestScore) {
        highestScore = s;
        safestIndex = i;
      }
    }
    _selectedIndex = safestIndex;
    _updatePolylines();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _initMarkersAndPolylines() {
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
  }

  void _updatePolylines() {
    final polylines = <Polyline>{};

    for (int i = 0; i < widget.alternatives.length; i++) {
      final alt = widget.alternatives[i];
      final isSelected = i == _selectedIndex;

      polylines.add(Polyline(
        polylineId: PolylineId('route_$i'),
        points: alt.points,
        width: isSelected ? 6 : 4,
        color: isSelected ? _selectedColor : _unselectedColor,
        zIndex: isSelected ? 2 : 1,
        patterns: isSelected ? [] : [PatternItem.dash(20), PatternItem.gap(10)],
        consumeTapEvents: true,
        onTap: () => _selectRoute(i),
      ));
    }

    setState(() => _polylines = polylines);
  }

  void _selectRoute(int index) {
    setState(() => _selectedIndex = index);
    _updatePolylines();

    // Fit camera to selected route
    final bounds = RouteService.boundsFromPoints(
      widget.alternatives[index].points,
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  void _fitAllRoutes() {
    // Build bounds from all routes combined
    final allPoints = widget.alternatives
        .expand((alt) => alt.points)
        .toList();
    final bounds = RouteService.boundsFromPoints(allPoints);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  String _routeLabel(int index) {
    if (widget.alternatives.length == 1) return 'Recommended';
    if (index == 0) return 'Fastest';
    if (index == widget.alternatives.length - 1) return 'Longest';
    return 'Alternative $index';
  }

  bool _isSafest(int index) {
    if (widget.scores.any((s) => s == null)) return false;
    final maxScore = widget.scores
        .map((s) => s!.safetyScore)
        .reduce((a, b) => a > b ? a : b);
    return widget.scores[index]?.safetyScore == maxScore;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.alternatives[_selectedIndex];
    final score = widget.scores[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Route'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Show all routes',
            onPressed: _fitAllRoutes,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.originLatLng,
              zoom: 14,
            ),
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              Future.delayed(const Duration(milliseconds: 300), () {
                _fitAllRoutes();
              });
            },
          ),

          // ── Route selector tabs — top of map ────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: Row(
                children: List.generate(
                  widget.alternatives.length,
                  (i) {
                    final isSelected = i == _selectedIndex;
                    final s = widget.scores[i];
                    final alt = widget.alternatives[i];
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _selectRoute(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(
                            right: i < widget.alternatives.length - 1 ? 6 : 0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _routeLabel(i),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.blue.shade700
                                          : Colors.black54,
                                    ),
                                  ),
                                  if (_isSafest(i)) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius:
                                            BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        '★',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${alt.distanceKm.toStringAsFixed(1)}km · ${alt.durationMinutes}min',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black45,
                                ),
                              ),
                              if (s != null) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: s.safetyColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${s.safetyScore}/100',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: s.safetyColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else
                                const SizedBox(
                                  height: 8,
                                  width: 8,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Bottom card — selected route details ─────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Route summary
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _routeLabel(_selectedIndex),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_isSafest(_selectedIndex)) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Safest route',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'via ${selected.summary}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.straighten,
                                    size: 14, color: Colors.black45),
                                const SizedBox(width: 4),
                                Text(
                                  '${selected.distanceKm.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.black54),
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.schedule,
                                    size: 14, color: Colors.black45),
                                const SizedBox(width: 4),
                                Text(
                                  '~${selected.durationMinutes} min',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.black54),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Safety score pill
                      if (score != null)
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: score.safetyColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${score.safetyScore}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              score.safetyLabel
                                  .replaceAll(RegExp(r'[🟢🟡🟠🔴]\s*'), ''),
                              style: TextStyle(
                                fontSize: 10,
                                color: score.safetyColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      else
                        const CircularProgressIndicator(),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Walk this route button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _selectedIndex),
                      icon: const Icon(Icons.directions_walk),
                      label: const Text(
                        'Walk This Route',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}