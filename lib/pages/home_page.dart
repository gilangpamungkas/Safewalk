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

  // Walking time — defaults to now, user can change
  TimeOfDay _walkingTime = TimeOfDay.now();
  bool _useCurrentTime = true;

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

  Future<void> _geocodeQuickSelect(String label) async {
    final latLng = await RouteService.geocodeLabel(label);
    if (!mounted || latLng == null) return;
    setState(() {
      selectedDestination = label;
      selectedDestinationLatLng = latLng;
      _destinationController.text = label;
    });
  }

  /// Opens time picker so user can plan a future walk.
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

  /// Resets walking time back to now.
  void _resetToNow() {
    setState(() {
      _walkingTime = TimeOfDay.now();
      _useCurrentTime = true;
    });
  }

  /// Returns emoji icon for the time period.
  String _timePeriodIcon(TimeOfDay time) {
    final h = time.hour;
    if (h >= 6 && h < 9) return '🌅';
    if (h >= 9 && h < 17) return '☀️';
    if (h >= 17 && h < 20) return '🌆';
    if (h >= 20 && h < 23) return '🌙';
    if (h >= 23 || h < 3) return '🌃';
    return '🌌';
  }

  /// Returns a risk hint for the selected time.
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

  /// Picks a contact from the phone's contact book.
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

      return {
        'name': full.displayName,
        'phone': full.phones.first.number,
      };
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

  /// Shows emergency contact settings dialog.
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
                const Text(
                  'Your name',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
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
                  'Used in the SOS message so the recipient '
                  'knows who sent it.',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 16),
                const Text(
                  'Emergency contact',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'This person receives your location via SMS '
                  'when you use the SOS button.',
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
                      const Text(
                        'SMS preview',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🚨 SOS Alert from '
                        '${userNameController.text.isEmpty ? '[Your name]' : userNameController.text}'
                        '!\n\n'
                        'I need help. This is my last known location:\n'
                        'https://maps.google.com/?q=...\n\n'
                        'Sent via SafeWalk at ${TimeOfDay.now().format(ctx)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                          height: 1.4,
                        ),
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
                        'Please enter emergency contact name and phone',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                await SosService.saveUserName(userName);
                await SosService.saveContact(
                  name: contactName,
                  phone: phone,
                );

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
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
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

                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 12),

                // ===== WALKING TIME =====
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.black54),
                    const SizedBox(width: 8),
                    const Text(
                      'Walking time',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    // Reset to now button — only shown if custom time set
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

                // Time selector row
                GestureDetector(
                  onTap: _pickWalkingTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _timePeriodIcon(_walkingTime),
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _useCurrentTime
                                  ? 'Now — ${_walkingTime.format(context)}'
                                  : _walkingTime.format(context),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
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
                        const Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.black38,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 16),

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
                                  destinationLatLng:
                                      selectedDestinationLatLng!,
                                  walkingTime: _walkingTime,
                                ),
                              ),
                            )
                        : null,
                    child: const Text('Start Walking'),
                  ),
                ),

                const SizedBox(height: 12),

                // ===== SOS HINT =====
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sos, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      'SOS button available during your walk',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
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