import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/report_service.dart';

class ReportButton extends StatelessWidget {
  final LatLng? currentPosition;
  final VoidCallback onReportSubmitted;

  const ReportButton({
    super.key,
    required this.currentPosition,
    required this.onReportSubmitted,
  });

  void _onTap(BuildContext context) async {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available yet'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReportPage(location: currentPosition!),
      ),
    );

    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '✅ Report submitted — thank you for keeping others safe!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      onReportSubmitted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.orange, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag, color: Colors.orange, size: 22),
            Text(
              'Report',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-page report form — avoids bottom sheet overflow issues.
class _ReportPage extends StatefulWidget {
  final LatLng location;

  const _ReportPage({required this.location});

  @override
  State<_ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<_ReportPage> {
  String? _selectedType;
  final _descController = TextEditingController();
  bool _submitting = false;
  late LatLng _reportLocation;
  bool _locationAdjusted = false;

  @override
  void initState() {
    super.initState();
    _reportLocation = widget.location;
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _adjustLocation() async {
    final adjusted = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => _LocationPickerPage(
          initialLocation: _reportLocation,
        ),
      ),
    );

    if (adjusted != null && mounted) {
      setState(() {
        _reportLocation = adjusted;
        _locationAdjusted = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select what you want to report'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      await ReportService.submitReport(
        type: _selectedType!,
        location: _reportLocation,
        description: _descController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a Hazard'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info banner ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your report will be visible to other SafeWalk '
                      'users in this area.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Location ────────────────────────────────
            const Text(
              'Hazard location',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: _locationAdjusted
                    ? Colors.blue.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _locationAdjusted
                      ? Colors.blue.shade300
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _locationAdjusted
                        ? Icons.location_on
                        : Icons.my_location,
                    size: 18,
                    color: _locationAdjusted
                        ? Colors.blue
                        : Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _locationAdjusted
                              ? 'Custom location'
                              : 'Your current location',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _locationAdjusted
                                ? Colors.blue.shade700
                                : Colors.black87,
                          ),
                        ),
                        Text(
                          '${_reportLocation.latitude.toStringAsFixed(5)}, '
                          '${_reportLocation.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _adjustLocation,
                    icon: const Icon(Icons.edit_location_alt,
                        size: 16),
                    label: const Text(
                      'Adjust',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "Adjust" to move the pin to the exact hazard '
              'location — useful if the hazard is ahead of you.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black38,
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 20),

            // ── Category ────────────────────────────────
            const Text(
              'What are you reporting?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
              children: ReportService.categories.map((cat) {
                final isSelected = _selectedType == cat.type;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedType = cat.type),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cat.color.withOpacity(0.15)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? cat.color
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cat.emoji,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? cat.color
                                  : Colors.black54,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── Description ──────────────────────────────
            const Text(
              'Description (optional)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                hintText: 'e.g. Large aggressive dog near park gate',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_note),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 8),

            // Expiry note
            if (_selectedType != null)
              Builder(builder: (ctx) {
                final cat =
                    ReportService.categoryFor(_selectedType!);
                if (cat == null) return const SizedBox.shrink();
                final hours = cat.expiry.inHours;
                final label = hours >= 24
                    ? '${cat.expiry.inDays} days'
                    : '$hours hours';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'ℹ️ This report will be visible for $label '
                    'then automatically removed.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }),

            const SizedBox(height: 20),

            // ── Submit ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Report',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Full-screen map for picking exact hazard location.
class _LocationPickerPage extends StatefulWidget {
  final LatLng initialLocation;

  const _LocationPickerPage({required this.initialLocation});

  @override
  State<_LocationPickerPage> createState() =>
      _LocationPickerPageState();
}

class _LocationPickerPageState
    extends State<_LocationPickerPage> {
  late LatLng _pickedLocation;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _pickedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust Hazard Location'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _pickedLocation),
            child: const Text(
              'Confirm',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 17,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: {
              Marker(
                markerId: const MarkerId('report_pin'),
                position: _pickedLocation,
                draggable: true,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
                infoWindow: const InfoWindow(
                  title: 'Hazard location',
                  snippet: 'Drag to adjust',
                ),
                onDragEnd: (newPos) {
                  setState(() => _pickedLocation = newPos);
                },
              ),
            },
            onTap: (latLng) {
              setState(() => _pickedLocation = latLng);
            },
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),

          // Instruction banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              color: Colors.black87,
              child: const Row(
                children: [
                  Icon(Icons.touch_app,
                      color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap anywhere on the map or drag the orange '
                      'pin to mark the exact hazard location.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Confirm button
          Positioned(
            bottom: 32,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, _pickedLocation),
              icon: const Icon(Icons.check),
              label: const Text(
                'Confirm this location',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}