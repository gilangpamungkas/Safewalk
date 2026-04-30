import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_api_flutter/google_places_api_flutter.dart';
// ignore: implementation_imports
import 'package:google_places_api_flutter/src/domain/google_api/place_details_model.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../services/police_service.dart';
import '../services/road_safety_service.dart';
import '../services/osm_service.dart';
import '../services/combined_safety_score.dart';
import '../services/saved_destinations_service.dart';
import 'route_page.dart';
import 'route_picker_page.dart';

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

  // Walking time
  TimeOfDay _walkingTime = TimeOfDay.now();
  bool _useCurrentTime = true;

  // Loading state
  bool _loadingRoutes = false;

  // Saved destinations
  List<SavedDestination> _savedDestinations = [];
  bool _loadingDestinations = true;

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
    _loadSavedDestinations();
  }

  Future<void> _loadSavedDestinations() async {
    final destinations = await SavedDestinationsService.load();
    if (!mounted) return;
    setState(() {
      _savedDestinations = destinations;
      _loadingDestinations = false;
    });
  }

  Future<void> _detectCurrentLocation() async {
    setState(() => _isLoadingOrigin = true);
    final latLng = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (latLng != null) {
      final address = await LocationService.reverseGeocode(latLng);
      if (!mounted) return;
      setState(() {
        selectedOriginLatLng = latLng;
        selectedOrigin = address;
        _originController.text = address;
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
    if (lat == null || lng == null) return;
    setState(() {
      selectedOrigin = prediction.description;
      selectedOriginLatLng = LatLng(lat, lng);
      _originController.text = selectedOrigin;
    });
    FocusScope.of(context).unfocus();
  }

  void _onDestinationSelected(
      Prediction prediction, PlaceDetailsModel? details) {
    if (!mounted) return;
    final lat = details?.result.geometry?.location.lat;
    final lng = details?.result.geometry?.location.lng;
    if (lat == null || lng == null) return;
    setState(() {
      selectedDestination = prediction.description;
      selectedDestinationLatLng = LatLng(lat, lng);
      _destinationController.text = selectedDestination;
    });
    FocusScope.of(context).unfocus();
  }

  /// Select a saved destination and populate the destination field.
  void _onSavedDestinationTap(SavedDestination dest) {
    setState(() {
      selectedDestination = dest.address;
      selectedDestinationLatLng = dest.latLng;
      _destinationController.text = dest.label;
    });
  }

  Future<void> _pickWalkingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _walkingTime,
      helpText: 'When are you planning to walk?',
    );
    if (picked != null && mounted) {
      setState(() {
        _walkingTime = picked;
        _useCurrentTime = false;
      });
    }
  }

  void _resetToNow() {
    setState(() {
      _walkingTime = TimeOfDay.now();
      _useCurrentTime = true;
    });
  }

  String _timePeriodIcon(TimeOfDay time) {
    final h = time.hour;
    if (h >= 6 && h < 9) return '🌅';
    if (h >= 9 && h < 17) return '☀️';
    if (h >= 17 && h < 20) return '🌆';
    if (h >= 20 && h < 23) return '🌙';
    if (h >= 23 || h < 3) return '🌃';
    return '🌌';
  }

  String _timeRiskHint(TimeOfDay time) {
    final h = time.hour;
    if (h >= 6 && h < 9) return 'Morning — generally safe';
    if (h >= 9 && h < 17) return 'Daytime — safest period';
    if (h >= 17 && h < 20) return 'Evening — moderate risk';
    if (h >= 20 && h < 23) return 'Night — higher risk';
    if (h >= 23 || h < 3) return 'Late night — highest risk';
    return 'Very late — isolated roads';
  }

  Color _timeRiskColor(TimeOfDay time) {
    final h = time.hour;
    if (h >= 6 && h < 9) return Colors.green;
    if (h >= 9 && h < 17) return Colors.green;
    if (h >= 17 && h < 20) return Colors.amber;
    if (h >= 20 && h < 23) return Colors.orange;
    if (h >= 23 || h < 3) return Colors.red;
    return Colors.orange;
  }

  // ── Saved destination dialog ─────────────────────────────────────────────

  /// Show dialog to add or edit a saved destination.
  void _showSaveDestinationDialog({SavedDestination? existing}) {
    final isEditing = existing != null;
    final labelController =
        TextEditingController(text: existing?.label ?? '');
    final addressController =
        TextEditingController(text: existing?.address ?? '');
    String selectedEmoji = existing?.emoji ?? '📍';
    LatLng? pickedLatLng = existing?.latLng;

    // Pre-fill with current destination if adding new
    if (!isEditing && selectedDestinationLatLng != null) {
      addressController.text = selectedDestination;
      pickedLatLng = selectedDestinationLatLng;
    }

    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Text(selectedEmoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'Edit Place' : 'Save Destination',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Emoji picker ──────────────────────────────
                const Text(
                  'Choose icon',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: destinationEmojis.map((emoji) {
                    final isSelected = emoji == selectedEmoji;
                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => selectedEmoji = emoji),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.shade50
                              : Colors.grey.shade100,
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // ── Label ─────────────────────────────────────
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Home, Work, Gym',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),

                const SizedBox(height: 12),

                // ── Address search ────────────────────────────
                const Text(
                  'Address',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                PlaceSearchField(
                  controller: addressController,
                  apiKey: apiKey,
                  isLatLongRequired: true,
                  itemBuilder: (context, prediction) => ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(prediction.description,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  onPlaceSelected: (prediction, details) {
                    final lat = details?.result.geometry?.location.lat;
                    final lng = details?.result.geometry?.location.lng;
                    if (lat != null && lng != null) {
                      setDialogState(() {
                        addressController.text = prediction.description;
                        pickedLatLng = LatLng(lat, lng);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final label = labelController.text.trim();
                final address = addressController.text.trim();

                if (label.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a name')),
                  );
                  return;
                }
                if (address.isEmpty || pickedLatLng == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please search and select an address')),
                  );
                  return;
                }

                final destination = SavedDestination(
                  id: existing?.id ?? SavedDestinationsService.generateId(),
                  emoji: selectedEmoji,
                  label: label,
                  address: address,
                  latLng: pickedLatLng!,
                );

                if (isEditing) {
                  await SavedDestinationsService.update(destination);
                } else {
                  final added =
                      await SavedDestinationsService.add(destination);
                  if (!added && ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Maximum 5 saved places reached. Delete one first.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                }

                if (ctx.mounted) Navigator.pop(ctx);
                await _loadSavedDestinations();
              },
              child: Text(isEditing ? 'Update' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press on a chip to edit or delete.
  void _showDestinationOptions(SavedDestination dest) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(dest.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dest.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(dest.address,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.blue),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                _showSaveDestinationDialog(existing: dest);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await SavedDestinationsService.delete(dest.id);
                await _loadSavedDestinations();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Route finding ────────────────────────────────────────────────────────

  Future<void> _findRoutes() async {
    if (!_canStart) return;
    FocusScope.of(context).unfocus();
    setState(() => _loadingRoutes = true);

    try {
      final alternatives = await RouteService.getWalkingRouteAlternatives(
        origin: selectedOriginLatLng!,
        destination: selectedDestinationLatLng!,
      );

      if (!mounted) return;

      if (alternatives.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No routes found. Try a different destination.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _loadingRoutes = false);
        return;
      }

      final scoreFutures = alternatives.map((alt) async {
        try {
          final sampled = RouteService.sampleRoutePoints(alt.points);
          final results = await Future.wait([
            PoliceService.getCrimesAlongRoute(
              sampled,
              fullRoute: alt.points,
              routeDistanceKm: alt.distanceKm,
            ),
            RoadSafetyService.getCollisionsAlongRoute(alt.points),
            OsmService.getInfrastructureScore(alt.points),
          ]);
          return CombinedSafetyScore(
            crimeResult: results[0] as CrimeResult,
            collisionResult: results[1] as CollisionResult,
            osmResult: results[2] as OsmResult,
            routeDistanceKm: alt.distanceKm,
            walkingTime: _walkingTime,
          );
        } catch (e) {
          debugPrint('Score error for route ${alt.index}: $e');
          return null;
        }
      }).toList();

      final scores = await Future.wait(scoreFutures);
      if (!mounted) return;

      setState(() => _loadingRoutes = false);

      final pickedIndex = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => RoutePickerPage(
            origin: selectedOrigin,
            originLatLng: selectedOriginLatLng!,
            destination: selectedDestination,
            destinationLatLng: selectedDestinationLatLng!,
            walkingTime: _walkingTime,
            alternatives: alternatives,
            scores: scores,
          ),
        ),
      );

      if (pickedIndex != null && mounted) {
        final picked = alternatives[pickedIndex];
        final pickedScore = scores[pickedIndex];
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoutePage(
              origin: selectedOrigin,
              originLatLng: selectedOriginLatLng!,
              destination: selectedDestination,
              destinationLatLng: selectedDestinationLatLng!,
              walkingTime: _walkingTime,
              preloadedRoute: picked.points,
              preloadedScore: pickedScore,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding routes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── SOS contact picker ───────────────────────────────────────────────────

  Future<Map<String, String>?> _pickContact() async {
    try {
      final granted =
          await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contacts permission denied'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return null;
      final full = await FlutterContacts.getContact(
        contact.id,
        withProperties: true,
      );
      if (full == null || full.phones.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected contact has no phone number'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }
      return {'name': full.displayName, 'phone': full.phones.first.number};
    } catch (e) {
      debugPrint('Contact picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open contacts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  void _showContactSettings() async {
    final contact = await SosService.loadContact();
    final savedUserName = await SosService.loadUserName();
    if (!mounted) return;

    final userNameController =
        TextEditingController(text: savedUserName ?? '');
    final contactNameController =
        TextEditingController(text: contact['name'] ?? '');
    final phoneController =
        TextEditingController(text: contact['phone'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.emergency, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('SOS Settings'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your name',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
                const SizedBox(height: 6),
                TextField(
                  controller: userNameController,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'e.g. Sarah',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Used in the SOS message so the recipient knows who sent it.',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 16),
                const Text('Emergency contact',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54)),
                const SizedBox(height: 6),
                const Text(
                  'This person receives your location via SMS when you use the SOS button.',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactNameController,
                  decoration: const InputDecoration(
                    labelText: 'Contact name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+44 7700 900000',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      FocusScope.of(ctx).unfocus();
                      final picked = await _pickContact();
                      if (picked != null) {
                        setDialogState(() {
                          contactNameController.text = picked['name']!;
                          phoneController.text = picked['phone']!;
                        });
                      }
                    },
                    icon: const Icon(Icons.contacts, size: 18),
                    label: const Text('Choose from contacts'),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SMS preview',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.black45)),
                      const SizedBox(height: 4),
                      Text(
                        '🚨 SOS Alert from '
                        '${userNameController.text.isEmpty ? '[Your name]' : userNameController.text}'
                        '!\n\n'
                        'I need help. This is my last known location:\n'
                        'https://maps.google.com/?q=...\n\n'
                        'Sent via SafeWalk at ${TimeOfDay.now().format(ctx)}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final userName = userNameController.text.trim();
                final contactName = contactNameController.text.trim();
                final phone = phoneController.text.trim();
                if (contactName.isEmpty || phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Please enter emergency contact name and phone'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                await SosService.saveUserName(userName);
                await SosService.saveContact(name: contactName, phone: phone);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('SOS settings saved'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canStart =>
      selectedOriginLatLng != null && selectedDestinationLatLng != null;

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeWalk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.emergency),
            tooltip: 'SOS Settings',
            onPressed: _showContactSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Image.asset(
                  'assets/icon/app_icon.png',
                  width: 64,
                  height: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Start Your SafeWalk',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // ── ORIGIN ────────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text('From',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
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
                const Icon(Icons.arrow_downward, color: Colors.grey),
                const SizedBox(height: 8),

                // ── DESTINATION ───────────────────────────────────────────
                Row(
                  children: const [
                    Icon(Icons.location_on, color: Colors.red),
                    SizedBox(width: 8),
                    Text('To',
                        style: TextStyle(fontWeight: FontWeight.w600)),
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

                // ── SAVED DESTINATIONS ────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      'My Places',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    if (_savedDestinations.length <
                        SavedDestinationsService.maxDestinations)
                      TextButton.icon(
                        onPressed: () =>
                            _showSaveDestinationDialog(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Save current'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.blue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_loadingDestinations)
                  const SizedBox(
                    height: 36,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_savedDestinations.isEmpty)
                  // Empty state
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.grey.shade200, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.bookmark_border,
                            size: 28, color: Colors.grey.shade400),
                        const SizedBox(height: 6),
                        Text(
                          'No saved places yet',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search a destination then tap "Save current"',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                else
                  // Saved destination chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._savedDestinations.map((dest) {
                        final isSelected =
                            selectedDestinationLatLng == dest.latLng;
                        return GestureDetector(
                          onTap: () => _onSavedDestinationTap(dest),
                          onLongPress: () =>
                              _showDestinationOptions(dest),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue.shade600
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(dest.emoji,
                                    style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 6),
                                Text(
                                  dest.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      // Add more button (when under limit)
                      if (_savedDestinations.length <
                          SavedDestinationsService.maxDestinations)
                        GestureDetector(
                          onTap: () => _showSaveDestinationDialog(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.grey.shade300,
                                  style: BorderStyle.solid),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add,
                                    size: 16,
                                    color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  'Add place',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 12),

                // ── WALKING TIME ──────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.black54),
                    const SizedBox(width: 8),
                    const Text('Walking time',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (!_useCurrentTime)
                      TextButton(
                        onPressed: _resetToNow,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Reset to now'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickWalkingTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(_timePeriodIcon(_walkingTime),
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _useCurrentTime
                                  ? 'Now — ${_walkingTime.format(context)}'
                                  : _walkingTime.format(context),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            Text(
                              _timeRiskHint(_walkingTime),
                              style: TextStyle(
                                fontSize: 12,
                                color: _timeRiskColor(_walkingTime),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16, color: Colors.black38),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 16),

                // ── FIND ROUTES BUTTON ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _canStart && !_loadingRoutes ? _findRoutes : null,
                    icon: _loadingRoutes
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(_loadingRoutes
                        ? 'Finding safest routes...'
                        : 'Find Routes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── SOS HINT ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sos, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      'SOS button available during your walk',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _showContactSettings,
                      child: Text(
                        '· Set up SOS',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}