import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/media_item.dart';

class YoutubeException implements Exception {
  const YoutubeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Searches YouTube and resolves a temporary audio stream for a video.
/// Only the video id is stored; the stream address is fetched when you press
/// play because YouTube stream links expire.
class YoutubeApi {
  YoutubeApi() : _yt = YoutubeExplode();
  final YoutubeExplode _yt;

  Future<List<MediaItem>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    try {
      final results = await _yt.search
          .search(text)
          .timeout(const Duration(seconds: 25));
      final items = <MediaItem>[];
      for (final video in results.take(25)) {
        final id = video.id.value;
        items.add(
          MediaItem(
            id: 'youtube-$id',
            title: video.title,
            creator: video.author,
            category: 'YouTube',
            kind: MediaKind.music,
            source: 'youtube:$id',
            color: 0xFFB4A7F5,
            art: id.length % 5,
            description: 'Streamed from YouTube.',
            artworkUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
            durationMs: video.duration?.inMilliseconds,
          ),
        );
      }
      return items;
    } catch (_) {
      throw const YoutubeException(
        'Could not search YouTube right now. Check your connection and try again.',
      );
    }
  }

  Future<String> resolve(MediaItem item) async {
    final id = item.youtubeId;
    if (id == null) throw const YoutubeException('Not a YouTube song.');
    final playbackClient = YoutubeExplode();
    try {
      final manifest = await playbackClient.videos.streamsClient
          .getManifest(id, ytClients: [YoutubeApiClient.androidSdkless])
          .timeout(const Duration(seconds: 15));
      final streams = manifest.audioOnly.toList();
      streams.sort((a, b) {
        final aMp4 = a.container.name == 'mp4';
        final bMp4 = b.container.name == 'mp4';
        if (aMp4 != bMp4) return aMp4 ? -1 : 1;
        return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
      });
      if (streams.isEmpty) {
        throw const YoutubeException('No direct audio stream is available.');
      }
      return streams.first.url.toString();
    } finally {
      playbackClient.close();
    }
  }

  void dispose() => _yt.close();
}
