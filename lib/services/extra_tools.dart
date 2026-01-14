import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';

Future<Map<String, dynamic>> getCurrentLocation() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return {
      "ok": false,
      "error": "Location permission denied",
    };
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
    ),
  );

  // 🔹 Reverse geocoding
  final placemarks = await placemarkFromCoordinates(
    position.latitude,
    position.longitude,
  );

  final place = placemarks.isNotEmpty ? placemarks.first : null;

  return {
    "ok": true,
    "lat": position.latitude,
    "lon": position.longitude,

    // Human-readable address
    "address": place == null ? null : {
      "street": place.street,
      "city": place.locality,
      "state": place.administrativeArea,
      "country": place.country,
      "postal_code": place.postalCode,
      "name": place.name,
    },
  };
}

/// Returning redable date string like "Thursday, January 1, 2026" 
String getCurrentReadableDate() {
  final now = DateTime.now();
  final readableDate = DateFormat.yMMMMEEEEd().format(now);
  return readableDate;
}

/// LLM tool: returns current local time as a human-readable string
/// Example: "Thursday, January 1, 2026 at 6:42 PM"
Future<Map<String, dynamic>> getCurrentTime() async {
  final now = DateTime.now();

  return {
    "readable": DateFormat.yMMMMEEEEd().add_jm().format(now),  
  };
}