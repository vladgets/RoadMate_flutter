import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_transcript_api/youtube_transcript_api.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

final _api = YouTubeTranscriptApi();

/// Fetches the full transcript text of a YouTube video by URL or ID.
Future<String?> getYoutubeTranscriptText(String urlOrId) async {
  try {
    final id = _extractVideoId(urlOrId);
    if (id == null) return null;

    final items = await _api.fetch(id);
    return items.map((e) => e.text).join(' ');
  } catch (_) {
    return null;
  }
}

String? _extractVideoId(String input) {
  final trimmed = input.trim();
  if (!trimmed.contains('http')) return trimmed.isEmpty ? null : trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.host.contains('youtu.be')) {
    return uri.pathSegments.first;
  }

  if (uri.queryParameters['v'] != null) {
    return uri.queryParameters['v'];
  }

  if (uri.pathSegments.length >= 2 &&
      (uri.pathSegments.first == 'shorts' ||
          uri.pathSegments.first == 'embed')) {
    return uri.pathSegments[1];
  }

  return null;
}

final _yt = YoutubeExplode();

AudioOnlyStreamInfo? _selectAudioOnlyStream(
  Iterable<AudioOnlyStreamInfo> streams, {
  required bool preferLowBandwidth,
}) {
  if (streams.isEmpty) return null;

  // Prefer MP4/M4A for better compatibility and fewer CDN quirks.
  final mp4 = streams.where((s) => s.container.name.toLowerCase() == 'mp4');
  final pool = mp4.isNotEmpty ? mp4 : streams;

  return pool.reduce((a, b) {
    final aBps = a.bitrate.bitsPerSecond;
    final bBps = b.bitrate.bitsPerSecond;

    if (preferLowBandwidth) {
      return aBps <= bBps ? a : b;
    } else {
      return aBps >= bBps ? a : b;
    }
  });
}

/// Returns the BEST audio-only stream URL (m4a/webm)
Future<Uri?> getYoutubeAudioStreamUrl(String videoIdOrUrl) async {
  try {
    final id = _extractVideoId(videoIdOrUrl);
    if (id == null) return null;

    final manifest = await _yt.videos.streamsClient.getManifest(id);
    final streamInfo = _selectAudioOnlyStream(
      manifest.audioOnly,
      preferLowBandwidth: false,
    );

    return streamInfo?.url;

  } catch (_) {
    return null;
  }
}

/// Streams and plays the full YouTube audio (audio-only stream) from the beginning.
/// Returns the resolved audio-only stream URL (useful for debugging/logging).
Future<Uri?> playYoutubeAudioFull(
  AudioPlayer player,
  String videoIdOrUrl, {
  bool preferLowBandwidth = false,
  Duration? initialPosition,
}) async {
  try {
    final id = _extractVideoId(videoIdOrUrl);
    if (id == null) return null;

    final manifest = await _yt.videos.streamsClient.getManifest(id);
    final audioOnly = manifest.audioOnly;

    if (audioOnly.isEmpty) return null;

    final streamInfo = _selectAudioOnlyStream(
      audioOnly,
      preferLowBandwidth: preferLowBandwidth,
    );

    if (streamInfo == null) return null;

    final uri = streamInfo.url;
    await player.setAudioSource(AudioSource.uri(uri));

    // await player.setUrl(uri.toString());
    await player.seek(initialPosition ?? Duration.zero);
    await player.play();

    return uri;
  } catch (_) {
    return null;
  }
}

/// Plays a single segment of YouTube audio.
/// Seeks to [start], plays for [duration], then pauses.
/// Returns a callback that cancels the scheduled stop and pauses immediately.
Future<VoidCallback?> playYoutubeAudioSegment(
  AudioPlayer player,
  String videoIdOrUrl, {
  required Duration start,
  required Duration duration,
  bool preferLowBandwidth = false,
}) async {
  try {
    if (duration <= Duration.zero) return null;
    if (start < Duration.zero) return null;

    final uri = await playYoutubeAudioFull(
      player,
      videoIdOrUrl,
      preferLowBandwidth: preferLowBandwidth,
      initialPosition: start,
    );

    if (uri == null) return null;

    final timer = Timer(duration, () async {
      try {
        if (player.playing) {
          await player.pause();
        }
      } catch (_) {
        // ignore
      }
    });

    return () {
      timer.cancel();
      try {
        player.pause();
      } catch (_) {
        // ignore
      }
    };
  } catch (_) {
    return null;
  }
}


/// Opens the YouTube app (if installed) or web browser to play the given video.
Future<void> openYoutubeVideo(
  String videoId, {
  int? startSeconds,
  bool autoplay = true,
}) async {
  final start = startSeconds ?? 0;
  final auto = autoplay ? 1 : 0;

  final appUri = Uri.parse(
    'youtube://watch?v=$videoId&t=${start}s&autoplay=$auto',
  );

  final webUri = Uri.parse(
    'https://www.youtube.com/watch?v=$videoId&t=${start}s&autoplay=$auto',
  );

  if (await canLaunchUrl(appUri)) {
    await launchUrl(appUri);
  } else {
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}