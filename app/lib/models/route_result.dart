import 'package:latlong2/latlong.dart';

class RouteStep {
  final String instruction;
  final double distanceMeters;
  final String? name;

  RouteStep({
    required this.instruction,
    required this.distanceMeters,
    this.name,
  });
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });
}
