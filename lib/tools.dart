import 'package:geolocator/geolocator.dart';


/// Fetches the user's current GPS location.
/// Returns the most accurate location available from the device.
Future<Map<String, dynamic>> getCurrentLocation() async {
  // Permission flow
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    return {
      "ok": false,
      "error": "Location permission deniedForever",
    };
  }

  if (permission == LocationPermission.denied) {
    return {
      "ok": false,
      "error": "Location permission denied",
    };
  }

  final locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    timeLimit: Duration(seconds: 10),
  );

  final position = await Geolocator.getCurrentPosition(
    locationSettings: locationSettings,
  );

  return {
    "ok": true,
    "lat": position.latitude,
    "lng": position.longitude,
  };
}
