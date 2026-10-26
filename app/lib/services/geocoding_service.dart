import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingResult {
  final String displayName;
  final LatLng point;

  GeocodingResult({required this.displayName, required this.point});
}

class GeocodingService {
  Future<List<GeocodingResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&format=json&limit=5&addressdetails=1',
    );

    final res = await http.get(uri, headers: {
      'User-Agent': 'navegacion-app',
      'Accept-Language': 'es',
    });

    if (res.statusCode != 200) {
      throw Exception('Error al buscar: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as List<dynamic>;
    final results = <GeocodingResult>[];

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        final name = item['display_name']?.toString() ?? '';
        if (lat != null && lon != null) {
          results.add(GeocodingResult(displayName: name, point: LatLng(lat, lon)));
        }
      }
    }

    return results;
  }
}
