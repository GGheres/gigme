import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationState {
  const LocationState({
    required this.center,
    required this.userLocation,
    required this.loading,
    required this.permissionDenied,
    required this.error,
  });

  final LatLng center;
  final LatLng? userLocation;
  final bool loading;
  final bool permissionDenied;
  final String? error;

  factory LocationState.initial() => const LocationState(
        center: LatLng(52.37, 4.90),
        userLocation: null,
        loading: true,
        permissionDenied: false,
        error: null,
      );

  LocationState copyWith({
    LatLng? center,
    LatLng? userLocation,
    bool? loading,
    bool? permissionDenied,
    String? error,
  }) {
    return LocationState(
      center: center ?? this.center,
      userLocation: userLocation ?? this.userLocation,
      loading: loading ?? this.loading,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      error: error,
    );
  }
}

class LocationController extends ChangeNotifier {
  LocationController() {
    unawaited(refresh());
  }

  LocationState _state = LocationState.initial();
  LocationState get state => _state;

  Future<void> refresh() async {
    _state = _state.copyWith(loading: true, error: null);
    notifyListeners();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _state = _state.copyWith(
          loading: false,
          permissionDenied: true,
          error: 'Location service is disabled.',
        );
        notifyListeners();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _state = _state.copyWith(
          loading: false,
          permissionDenied: true,
          error: 'Location permission denied. Using default city center.',
        );
        notifyListeners();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final point = LatLng(position.latitude, position.longitude);
      _state = _state.copyWith(
        center: point,
        userLocation: point,
        loading: false,
        permissionDenied: false,
      );
      notifyListeners();
    } catch (error) {
      _state = _state.copyWith(
        loading: false,
        error: 'Failed to read geolocation: $error',
      );
      notifyListeners();
    }
  }

  void setMapCenter(LatLng center) {
    _state = _state.copyWith(center: center, error: null);
    notifyListeners();
  }
}

final locationControllerProvider = ChangeNotifierProvider<LocationController>((ref) {
  final controller = LocationController();
  ref.onDispose(controller.dispose);
  return controller;
});
