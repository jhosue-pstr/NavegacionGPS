import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/route_result.dart';

class OsrmService {
  final String baseUrl;

  OsrmService({this.baseUrl = 'https://router.project-osrm.org'});

  Future<RouteResult> getRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      '$baseUrl/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('OSRM error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw Exception('No route found');
    }

    final route = routes[0] as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;

    final points = <LatLng>[];
    for (final coord in coordinates) {
      if (coord is List && coord.length >= 2) {
        final lon = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        points.add(LatLng(lat, lon));
      }
    }

    final distance = (route['distance'] as num).toDouble();
    final duration = (route['duration'] as num).toDouble();

    final legs = route['legs'] as List<dynamic>?;
    final stepsList = <RouteStep>[];
    if (legs != null && legs.isNotEmpty) {
      final leg = legs[0] as Map<String, dynamic>;
      final steps = leg['steps'] as List<dynamic>?;
      if (steps != null) {
        for (final step in steps) {
          if (step is Map<String, dynamic>) {
            final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
            final type = maneuver['type']?.toString() ?? '';
            final modifier = maneuver['modifier']?.toString() ?? '';
            String instruction = (maneuver['instruction']?.toString() ?? '').trim();
            if (instruction.isEmpty) {
              if (type == 'depart') {
                instruction = 'Salir';
              } else if (type == 'arrive') {
                instruction = 'Llegar al destino';
              } else if (type == 'turn') {
                if (modifier.contains('left')) {
                  instruction = 'Girar a la izquierda';
                } else if (modifier.contains('right')) {
                  instruction = 'Girar a la derecha';
                } else if (modifier.contains('straight')) {
                  instruction = 'Seguir recto';
                } else {
                  instruction = 'Girar';
                }
              } else if (type == 'continue') {
                instruction = 'Seguir recto';
              } else if (type == 'new name') {
                instruction = 'Seguir por esta carretera';
              } else if (type == 'merge') {
                instruction = 'Incorporarse';
              } else if (type == 'roundabout' || type == 'rotary') {
                instruction = 'Tomar la rotonda';
              } else if (type == 'exit roundabout') {
                instruction = 'Salir de la rotonda';
              } else {
                instruction = 'Continuar';
              }
              final name = step['name']?.toString() ?? '';
              if (name.isNotEmpty && type != 'arrive' && type != 'depart') {
                instruction = '$instruction por $name';
              }
            }
            final stepDist = (step['distance'] as num?)?.toDouble() ?? 0;
            final name = step['name']?.toString();
            stepsList.add(RouteStep(instruction: instruction, distanceMeters: stepDist, name: name));
          }
        }
      }
    }

    return RouteResult(
      points: points,
      distanceMeters: distance,
      durationSeconds: duration,
      steps: stepsList,
    );
  }
}
