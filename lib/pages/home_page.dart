import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_api_flutter/google_places_api_flutter.dart';
// ignore: implementation_imports
import 'package:google_places_api_flutter/src/domain/google_api/place_details_model.dart';
import '../services/route_service.dart';
import 'route_page.dart';

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

  void _onPlaceSelected(Prediction prediction, PlaceDetailsModel? details) {
    if (!mounted) return;

    final lat = details?.result?.geometry?.location?.lat;
    final lng = details?.result?.geometry?.location?.lng;

    if (lat == null || lng == null) {
      debugPrint('Place selected but lat/lng missing: ${prediction.description}');
      return;
    }

    setState(() {
      selectedDestination = prediction.description;
      selectedLatLng = LatLng(lat, lng);
      _searchController.text = selectedDestination;
    });

    FocusScope.of(context).unfocus();
  }

  Future<void> _geocodeQuickSelect(String label) async {
    final latLng = await RouteService.geocodeLabel(label);
    if (!mounted || latLng == null) return;

    setState(() {
      selectedDestination = label;
      selectedLatLng = latLng;
      _searchController.text = label;
    });
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

                // Google Places search field
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

                // Quick select chips
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

                // Start walking button
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
