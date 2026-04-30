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

  static const _selectedColor = Color(0xFF1565C0);
  static const _unselectedColor = Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _initMarkersAndPolylines();

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
        patterns: isSelected
            ? []
            : [PatternItem.dash(20), PatternItem.gap(10)],
        consumeTapEvents: true,
        onTap: () => _selectRoute(i),
      ));
    }
    setState(() => _polylines = polylines);
  }

  void _selectRoute(int index) {
    setState(() => _selectedIndex = index);
    _updatePolylines();
    final bounds = RouteService.boundsFromPoints(
      widget.alternatives[index].points,
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  void _fitAllRoutes() {
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

  bool _hasLowestCrime(int index) {
    if (widget.scores.any((s) => s == null)) return false;
    final minCrime = widget.scores
        .map((s) => s!.crimeDensity)
        .reduce((a, b) => a < b ? a : b);
    return widget.scores[index]?.crimeDensity == minCrime;
  }

  bool _hasFewestCollisions(int index) {
    if (widget.scores.any((s) => s == null)) return false;
    final minCollision = widget.scores
        .map((s) => s!.collisionDensity)
        .reduce((a, b) => a < b ? a : b);
    return widget.scores[index]?.collisionDensity == minCollision;
  }

  bool _hasBestInfrastructure(int index) {
    if (widget.scores.any((s) => s == null)) return false;
    final maxInfra = widget.scores
        .map((s) => s!.osmResult.infrastructureScore)
        .reduce((a, b) => a > b ? a : b);
    return widget.scores[index]?.osmResult.infrastructureScore ==
        maxInfra;
  }

  bool _isShortest(int index) {
    final minDist = widget.alternatives
        .map((a) => a.distanceKm)
        .reduce((a, b) => a < b ? a : b);
    return widget.alternatives[index].distanceKm == minDist;
  }

  bool _isFastest(int index) {
    final minDur = widget.alternatives
        .map((a) => a.durationMinutes)
        .reduce((a, b) => a < b ? a : b);
    return widget.alternatives[index].durationMinutes == minDur;
  }

  /// Returns a list of insight chips for a given route.
  /// Only shows insights that are unique to this route
  /// (best among all alternatives).
  List<_InsightChip> _insightsFor(int index) {
    final chips = <_InsightChip>[];

    if (widget.alternatives.length <= 1) return chips;

    if (_isSafest(index)) {
      chips.add(const _InsightChip(
        icon: Icons.shield,
        label: 'Safest overall',
        color: Colors.green,
      ));
    }
    if (_hasLowestCrime(index)) {
      chips.add(const _InsightChip(
        icon: Icons.local_police,
        label: 'Lowest crime',
        color: Colors.blue,
      ));
    }
    if (_hasFewestCollisions(index)) {
      chips.add(const _InsightChip(
        icon: Icons.car_crash,
        label: 'Fewest collisions',
        color: Colors.indigo,
      ));
    }
    if (_hasBestInfrastructure(index)) {
      chips.add(const _InsightChip(
        icon: Icons.lightbulb,
        label: 'Best lit & paved',
        color: Colors.amber,
      ));
    }
    if (_isFastest(index) && !_isSafest(index)) {
      chips.add(const _InsightChip(
        icon: Icons.speed,
        label: 'Fastest',
        color: Colors.orange,
      ));
    }
    if (_isShortest(index) && !_isFastest(index)) {
      chips.add(const _InsightChip(
        icon: Icons.straighten,
        label: 'Shortest',
        color: Colors.teal,
      ));
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.alternatives[_selectedIndex];
    final score = widget.scores[_selectedIndex];
    final insights = _insightsFor(_selectedIndex);

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

          // ── Route selector tabs — top ────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
  padding: EdgeInsets.fromLTRB(
    20, 16, 20,
    MediaQuery.of(context).padding.bottom + 16,
  ),
  decoration: const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                            right: i < widget.alternatives.length - 1
                                ? 6
                                : 0,
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

          // ── Bottom card ──────────────────────────────────
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
                  // Route summary row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                      fontSize: 13,
                                      color: Colors.black54),
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.schedule,
                                    size: 14, color: Colors.black45),
                                const SizedBox(width: 4),
                                Text(
                                  '~${selected.durationMinutes} min',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54),
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
                              score.safetyLabel.replaceAll(
                                RegExp(r'[🟢🟡🟠🔴]\s*'), ''),
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

                  // ── Insight chips ──────────────────────────
                  if (insights.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Why this route stands out',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: insights.map((chip) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: chip.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: chip.color.withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(chip.icon,
                                  size: 12, color: chip.color),
                              const SizedBox(width: 4),
                              Text(
                                chip.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: chip.color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // ── Data breakdown ─────────────────────────
                  if (score != null) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Colors.black12),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _dataPoint(
                          icon: Icons.local_police,
                          label: 'Crime',
                          value: '${score.crimeResult.totalCrimes}',
                          color: Colors.red,
                        ),
                        _dataPoint(
                          icon: Icons.car_crash,
                          label: 'Collisions',
                          value:
                              '${score.collisionResult.totalCollisions}',
                          color: Colors.deepPurple,
                        ),
                        _dataPoint(
  icon: Icons.lightbulb,
  label: 'Lit',
  value: '${score.osmResult.litDistancePct.round()}%',
  color: Colors.amber,
),
                        _dataPoint(
                          icon: Icons.streetview,
                          label: 'Pavement',
                          value: score.osmResult.sidewalkSegments > 0
                              ? 'Yes'
                              : 'Limited',
                          color: Colors.teal,
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Walk button ────────────────────────────
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

  Widget _dataPoint({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
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
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Data class for an insight chip.
class _InsightChip {
  final IconData icon;
  final String label;
  final Color color;

  const _InsightChip({
    required this.icon,
    required this.label,
    required this.color,
  });
}