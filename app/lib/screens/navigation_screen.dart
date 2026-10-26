import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_result.dart';
import '../widgets/route_map.dart';

class NavigationScreen extends StatefulWidget {
  final List<LatLng> points;
  final List<RouteStep> steps;
  final double distanceMeters;
  final double durationSeconds;

  const NavigationScreen({
    super.key,
    required this.points,
    required this.steps,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _mapController = MapController();
  final _repaintKey = GlobalKey();

  String _fmtDist(double m) {
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  String _fmtTime(double s) {
    final min = (s / 60).round();
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final rem = min % 60;
    return '${h}h ${rem}min';
  }

  IconData _iconFor(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('izquierda')) return Icons.turn_left;
    if (lower.contains('derecha')) return Icons.turn_right;
    if (lower.contains('rotonda')) return Icons.roundabout_left;
    if (lower.contains('incorporar')) return Icons.merge_type;
    if (lower.contains('llegar')) return Icons.flag;
    if (lower.contains('salir')) return Icons.play_arrow;
    return Icons.straight;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.points.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(widget.points);
        _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.points.isNotEmpty ? widget.points.first : const LatLng(40.4168, -3.7038);
    final polylines = widget.points.isEmpty
        ? <Polyline>[]
        : [
            Polyline(
              points: widget.points,
              strokeWidth: 5,
              color: Colors.blue,
            ),
          ];

    return Scaffold(
      body: Stack(
        children: [
          RouteMap(
            repaintBoundaryKey: _repaintKey,
            mapController: _mapController,
            markers: const [],
            polylines: polylines,
            initialCenter: center,
            initialZoom: 14,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            right: 8,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  '${_fmtDist(widget.distanceMeters)} · ${_fmtTime(widget.durationSeconds)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DraggableScrollableSheet(
                initialChildSize: 0.22,
                minChildSize: 0.14,
                maxChildSize: 0.7,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Indicaciones',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.close),
                                label: const Text('Salir'),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: widget.steps.isEmpty
                              ? const Center(child: Text('Sin indicaciones'))
                              : ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: widget.steps.length,
                                  itemBuilder: (context, index) {
                                    final step = widget.steps[index];
                                    final instruction = step.instruction.isEmpty ? 'Continuar' : step.instruction;
                                    return ListTile(
                                      leading: Icon(_iconFor(instruction)),
                                      title: Text(instruction),
                                      subtitle: step.distanceMeters > 0 ? Text('En ${_fmtDist(step.distanceMeters)}') : null,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
