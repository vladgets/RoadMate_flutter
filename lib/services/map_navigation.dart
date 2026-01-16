import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import 'extra_tools.dart';


/// Replace this with YOUR existing function.
Future<String> getCurrentLocationLatLng() async {
  final loc = await getCurrentLocation();

  if (loc["ok"] != true) {
    throw Exception("Failed to get current location: ${loc["error"]}");
  }

  final double lat = loc["lat"];
  final double lon = loc["lon"];

  return "$lat,$lon";
}

String _routeTypeToMode(String routeType) {
  switch (routeType) {
    case "on_foot":
      return "walking";
    case "by_car":
    default:
      return "driving";
  }
}

Future<Map<String, dynamic>> callTrafficEtaServer({
  required String serverBaseUrl,
  required String destination,
  String routeType = "by_car",
  String units = "imperial",
}) async {
  final origin = await getCurrentLocationLatLng();
  final mode = _routeTypeToMode(routeType);

  final uri = Uri.parse("$serverBaseUrl/traffic_eta");

  final resp = await http.post(
    uri,
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "origin": origin,
      "destination": destination,
      "mode": mode,   // server expects "driving" | "walking"
      "units": units, // "metric" | "imperial"
    }),
  );

  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception("traffic_eta failed ${resp.statusCode}: ${resp.body}");
  }

  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  return data;
}

/// Handles a call to the Traffic ETA tool.
Future<Map<String, dynamic>> handleTrafficEtaToolCall(Map<String, dynamic> args) async {
  final destination = (args["destination"] as String?)?.trim();
  if (destination == null || destination.isEmpty) {
    return {
      "ok": false,
      "error": "Missing required parameter: destination",
    };
  }

  final routeType = (args["route_type"] as String?) ?? "by_car";
  final units = (args["units"] as String?) ?? "imperial";

  final data = await callTrafficEtaServer(
    serverBaseUrl: Config.serverUrl,
    destination: destination,
    routeType: routeType,
    units: units,
  );

  // Your server already returns a nice voice summary
  // (and structured fields like distanceMeters/baseSeconds/liveSeconds).
  return data;
}

/// Handles a call to the Open Maps Route tool.
Future<Map<String, dynamic>> handleOpenMapsRouteToolCall(Map<String, dynamic> args) async {
  final destination = (args["destination"] as String?)?.trim();
  if (destination == null || destination.isEmpty) {
    return {"ok": false, "error": "Missing required parameter: destination"};
  }

  final routeType = (args["route_type"] as String?) ?? "by_car";
  final encodedDest = Uri.encodeComponent(destination);

  Uri launchUri;

  if (Platform.isAndroid) {
    // 🔹 Android: system navigation intent (default app)
    // driving → google.navigation:q=
    // walking → google.navigation:q=&mode=w
    final mode = routeType == "on_foot" ? "w" : "d";

    launchUri = Uri.parse(
      "google.navigation:q=$encodedDest&mode=$mode",
    );
  } else if (Platform.isIOS) {
    // 🔹 iOS: Apple Maps (system default)
    final dirFlag = routeType == "on_foot" ? "w" : "d";

    launchUri = Uri.parse(
      "http://maps.apple.com/?daddr=$encodedDest&dirflg=$dirFlag",
    );
  } else {
    return {"ok": false, "error": "Unsupported platform"};
  }

  final opened = await launchUrl(
    launchUri,
    mode: LaunchMode.externalApplication,
  );

  if (!opened) {
    return {"ok": false, "error": "Could not open navigation app"};
  }

  return {
    "ok": true,
    "opened": true,
    "mode": routeType,
  };
}