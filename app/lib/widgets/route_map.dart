import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RouteMap extends StatelessWidget {
  final MapController mapController;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(TapPosition, LatLng)? onTap;
  final GlobalKey repaintBoundaryKey;

  const RouteMap({
    super.key,
    required this.repaintBoundaryKey,
    required this.mapController,
    required this.markers,
    required this.polylines,
    required this.initialCenter,
    this.initialZoom = 13,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintBoundaryKey,
      child: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: initialZoom,
          onTap: onTap,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.jhosue.navegacion',
            tileProvider: NetworkTileProvider(),
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}
