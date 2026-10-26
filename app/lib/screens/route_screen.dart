import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_result.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/osrm_service.dart';
import '../widgets/route_map.dart';
import 'navigation_screen.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final _mapController = MapController();
  final _repaintKey = GlobalKey();
  final _locationService = LocationService();
  final _osrmService = OsrmService();
  final _geocodingService = GeocodingService();

  LatLng? _start;
  LatLng? _end;
  RouteResult? _route;
  bool _loading = false;
  String? _error;

  bool _pickEndOnMap = false;
  StreamSubscription<Position>? _positionSub;

  bool _showRouteCard = false;
  final _startController = TextEditingController();
  final _destController = TextEditingController();
  List<GeocodingResult> _startSearchResults = [];
  List<GeocodingResult> _destSearchResults = [];
  Timer? _startDebounce;
  Timer? _destDebounce;
  bool _editingStart = false;
  bool _editingDest = false;

  @override
  void dispose() {
    _positionSub?.cancel();
    _startDebounce?.cancel();
    _destDebounce?.cancel();
    _startController.dispose();
    _destController.dispose();
    super.dispose();
  }

  List<Marker> _markers() {
    final markers = <Marker>[];
    if (_start != null) {
      markers.add(
        Marker(
          point: _start!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.green, size: 40),
        ),
      );
    }
    if (_end != null) {
      markers.add(
        Marker(
          point: _end!,
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: Colors.red, size: 40),
        ),
      );
    }
    return markers;
  }

  List<Polyline> _polylines() {
    if (_route == null || _route!.points.isEmpty) return [];
    return [
      Polyline(points: _route!.points, strokeWidth: 4, color: Colors.blue),
    ];
  }

  Future<void> _useCurrentLocationAsStart() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loc = await _locationService.getCurrentLocation();
      if (loc == null) {
        if (!mounted) return;
        setState(() {
          _error = 'No se pudo obtener ubicación o permisos denegados';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _start = loc;
        _startController.text = 'Mi ubicación';
        _startSearchResults = [];
        _editingStart = false;
      });
      _mapController.move(loc, 16);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _startPickEnd() {
    setState(() {
      _pickEndOnMap = true;
      _error = null;
      _destSearchResults = [];
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Toca el mapa para seleccionar destino')),
    );
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (!_pickEndOnMap) return;
    setState(() {
      _end = point;
      _pickEndOnMap = false;
      _showRouteCard = true;
      _destSearchResults = [];
      _destController.text = 'Destino en mapa';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Destino seleccionado')));
  }

  Future<void> _centerOnMyLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loc = await _locationService.getCurrentLocation();
      if (loc == null) {
        if (!mounted) return;
        setState(() {
          _error = 'No se pudo obtener ubicación o permisos denegados';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _start = loc;
        _startController.text = 'Mi ubicación';
        _startSearchResults = [];
        _editingStart = false;
      });
      _mapController.move(loc, 17);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _calculateRoute() async {
    if (_start == null || _end == null) {
      setState(() {
        _error = 'Selecciona origen y destino';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _route = null;
      _showRouteCard = false;
      _startSearchResults = [];
      _destSearchResults = [];
      _editingStart = false;
      _editingDest = false;
    });
    try {
      final result = await _osrmService.getRoute(_start!, _end!);
      if (!mounted) return;
      setState(() {
        _route = result;
      });
      if (result.points.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(result.points);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
        );
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NavigationScreen(
            points: result.points,
            steps: result.steps,
            distanceMeters: result.distanceMeters,
            durationSeconds: result.durationSeconds,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _onStartChanged(String value) {
    setState(() {
      _editingStart = true;
    });
    _startDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _startSearchResults = [];
      });
      return;
    }
    _startDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final results = await _geocodingService.search(value.trim());
        if (!mounted) return;
        setState(() {
          _startSearchResults = results;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _startSearchResults = [];
        });
      }
    });
  }

  void _onDestChanged(String value) {
    setState(() {
      _editingDest = true;
    });
    _destDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _destSearchResults = [];
      });
      return;
    }
    _destDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      try {
        final results = await _geocodingService.search(value.trim());
        if (!mounted) return;
        setState(() {
          _destSearchResults = results;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _destSearchResults = [];
        });
      }
    });
  }

  void _selectStartSearchResult(GeocodingResult result) {
    setState(() {
      _start = result.point;
      _startController.text = result.displayName;
      _startSearchResults = [];
      _editingStart = false;
    });
    _mapController.move(result.point, 15);
  }

  void _selectSearchResult(GeocodingResult result) {
    setState(() {
      _end = result.point;
      _destController.text = result.displayName;
      _destSearchResults = [];
      _editingDest = false;
      _pickEndOnMap = false;
    });
    _mapController.move(result.point, 15);
  }

  @override
  Widget build(BuildContext context) {
    final center = _start ?? const LatLng(40.4168, -3.7038);

    return Scaffold(
      body: Stack(
        children: [
          RouteMap(
            repaintBoundaryKey: _repaintKey,
            mapController: _mapController,
            markers: _markers(),
            polylines: _polylines(),
            initialCenter: center,
            onTap: _onMapTap,
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_showRouteCard)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            color: Colors.green,
                            size: 12,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _startController,
                              decoration: const InputDecoration(
                                hintText: 'Buscar',
                                border: InputBorder.none,
                                isDense: true,
                                prefixIcon: Icon(Icons.my_location, size: 18),
                              ),
                              onChanged: _onStartChanged,
                              onTap: () {
                                setState(() {
                                  _editingStart = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.circle, color: Colors.red, size: 12),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _destController,
                              decoration: const InputDecoration(
                                hintText: 'A dónde voy',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: _onDestChanged,
                              onTap: () {
                                setState(() {
                                  _editingDest = true;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: _loading ? null : _startPickEnd,
                            icon: const Icon(Icons.map),
                            tooltip: 'Elegir en el mapa',
                          ),
                        ],
                      ),
                      if (_startSearchResults.isNotEmpty && _editingStart)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _startSearchResults.length,
                            itemBuilder: (context, index) {
                              final res = _startSearchResults[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.location_on,
                                  size: 18,
                                ),
                                title: Text(
                                  res.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectStartSearchResult(res),
                              );
                            },
                          ),
                        ),
                      if (_destSearchResults.isNotEmpty && _editingDest)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _destSearchResults.length,
                            itemBuilder: (context, index) {
                              final res = _destSearchResults[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.place, size: 18),
                                title: Text(
                                  res.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectSearchResult(res),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  _loading || _start == null || _end == null
                                  ? null
                                  : _calculateRoute,
                              icon: const Icon(Icons.route),
                              label: const Text('Calcular ruta'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : _useCurrentLocationAsStart,
                            child: const Text('Mi ubicación'),
                          ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 80,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              onPressed: _loading ? null : _centerOnMyLocation,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.black),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _showRouteCard = !_showRouteCard;
            if (!_showRouteCard) {
              _startSearchResults = [];
              _destSearchResults = [];
              _pickEndOnMap = false;
              _editingStart = false;
              _editingDest = false;
            }
          });
        },
        child: Icon(_showRouteCard ? Icons.close : Icons.add),
      ),
    );
  }
}
