import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_api_flutter/google_places_api_flutter.dart';
// ignore: implementation_imports
import 'package:google_places_api_flutter/src/domain/google_api/place_details_model.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import 'route_page.dart';

class SafeWalkHomePage extends StatefulWidget {
  const SafeWalkHomePage({super.key});

  @override
  State<SafeWalkHomePage> createState() => _SafeWalkHomePageState();
}

class _SafeWalkHomePageState extends State<SafeWalkHomePage> {
  // Origin
  String selectedOrigin = 'Current Location';
  LatLng? selectedOriginLatLng;
  bool _isLoadingOrigin = false;
  final TextEditingController _originController = TextEditingController();

  // Destination
  String selectedDestination = '';
  LatLng? selectedDestinationLatLng;
  final TextEditingController _destinationController = TextEditingController();

  final List<String> quickSelect = [
    'Home',
    'Work',
    'Gym',
    "Friend's Place",
    'Station',
    'Market',
  ];

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
  }

  /// Detects current location and sets it as the default origin.
  Future<void> _detectCurrentLocation() async {
    setState(() => _isLoadingOrigin = true);

    final latLng = await LocationService.getCurrentPosition();

    if (!mounted) return;

    if (latLng != null) {
      setState(() {
        selectedOriginLatLng = latLng;
        selectedOrigin = 'Current Location';
        _originController.text = 'Current Location';
        _isLoadingOrigin = false;
      });
    } else {
      setState(() {
        _isLoadingOrigin = false;
        _originController.text = '';
      });
    }
  }

  void _onOriginSelected(Prediction prediction, PlaceDetailsModel? details) {
    if (!mounted) return;

    final lat = details?.result.geometry?.location.lat;
    final lng = details?.result.geometry?.location.lng;

    if (lat == null || lng == null) {
      debugPrint('Origin selected but lat/lng missing: ${prediction.description}');
      return;
    }

    setState(() {
      selectedOrigin = prediction.description;
      selectedOriginLatLng = LatLng(lat, lng);
      _originController.text = selectedOrigin;
    });

    FocusScope.of(context).unfocus();
  }

  void _onDestinationSelected(Prediction prediction, PlaceDetailsModel? details) {
    if (!mounted) return;

    final lat = details?.result.geometry?.location.lat;
    final lng = details?.result.geometry?.location.lng;

    if (lat == null || lng == null) {
      debugPrint('Destination selected but lat/lng missing: ${prediction.description}');
      return;
    }

    setState(() {
      selectedDestination = prediction.description;
      selectedDestinationLatLng = LatLng(lat, lng);
      _destinationController.text = selectedDestination;
    });

    FocusScope.of(context).unfocus();
  }

  Future<void> _geocodeQuickSelect(String label) async {
    final latLng = await RouteService.geocodeLabel(label);
    if (!mounted || latLng == null) return;

    setState(() {
      selectedDestination = label;
      selectedDestinationLatLng = latLng;
      _destinationController.text = label;
    });
  }

  bool get _canStart =>
      selectedOriginLatLng != null && selectedDestinationLatLng != null;

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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

                // ===== ORIGIN FIELD =====
                Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'From',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    // Re-detect current location button
                    if (!_isLoadingOrigin)
                      TextButton.icon(
                        onPressed: _detectCurrentLocation,
                        icon: const Icon(Icons.gps_fixed, size: 16),
                        label: const Text('Use my location'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (_isLoadingOrigin)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                PlaceSearchField(
                  controller: _originController,
                  apiKey: apiKey,
                  isLatLongRequired: true,
                  itemBuilder: (context, prediction) => ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(prediction.description),
                  ),
                  onPlaceSelected: _onOriginSelected,
                ),

                const SizedBox(height: 8),

                // Arrow connecting origin to destination
                const Icon(Icons.arrow_downward, color: Colors.grey),

                const SizedBox(height: 8),

                // ===== DESTINATION FIELD =====
                Row(
                  children: const [
                    Icon(Icons.location_on, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'To',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PlaceSearchField(
                  controller: _destinationController,
                  apiKey: apiKey,
                  isLatLongRequired: true,
                  itemBuilder: (context, prediction) => ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(prediction.description),
                  ),
                  onPlaceSelected: _onDestinationSelected,
                ),

                const SizedBox(height: 16),

                // ===== QUICK SELECT CHIPS =====
                Wrap(
                  spacing: 8,
                  children: quickSelect.map((item) {
                    final isSelected = selectedDestination == item;
                    return ChoiceChip(
                      label: Text(item),
                      selected: isSelected,
                      onSelected: (_) => _geocodeQuickSelect(item),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // ===== START WALKING BUTTON =====
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canStart
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoutePage(
                                  origin: selectedOrigin,
                                  originLatLng: selectedOriginLatLng!,
                                  destination: selectedDestination,
                                  destinationLatLng: selectedDestinationLatLng!,
                                ),
                              ),
                            )
                        : null,
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