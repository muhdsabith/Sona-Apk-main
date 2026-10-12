enum MediaKind { music, podcast }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.creator,
    required this.category,
    required this.kind,
    required this.source,
    required this.color,
    required this.art,
    required this.description,
    this.artworkUrl,
    this.feedUrl,
    this.durationMs,
    this.previewUrl,
    this.externalUrl,
  });
  final String id, title, creator, category, source, description;
  final MediaKind kind;
  final int color, art;
  final String? artworkUrl, feedUrl;
  final int? durationMs;
  final String? previewUrl, externalUrl;
  bool get isPodcast => kind == MediaKind.podcast;
  bool get isLocal => source.startsWith('local:');
  bool get isArchive => source.startsWith('archive:');
  bool get isYoutube => source.startsWith('youtube:');
  String? get youtubeId =>
      isYoutube ? source.substring('youtube:'.length) : null;
  bool get isSpotify => source.startsWith('spotify:track:');
  String? get spotifyTrackId =>
      isSpotify ? source.substring('spotify:track:'.length) : null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'creator': creator,
    'category': category,
    'kind': kind.name,
    'source': source,
    'color': color,
    'art': art,
    'description': description,
    'artworkUrl': artworkUrl,
    'feedUrl': feedUrl,
    'durationMs': durationMs,
    'previewUrl': previewUrl,
    'externalUrl': externalUrl,
  };
  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    id: j['id'] as String,
    title: j['title'] as String,
    creator: j['creator'] as String,
    category: j['category'] as String? ?? 'Your music',
    kind: j['kind'] == 'podcast' ? MediaKind.podcast : MediaKind.music,
    source: j['source'] as String,
    color: j['color'] as int? ?? 0xFFD4BFA5,
    art: j['art'] as int? ?? 0,
    description: j['description'] as String? ?? '',
    artworkUrl: j['artworkUrl'] as String?,
    feedUrl: j['feedUrl'] as String?,
    durationMs: j['durationMs'] as int?,
    previewUrl: j['previewUrl'] as String?,
    externalUrl: j['externalUrl'] as String?,
  );
}

class PodcastFeed {
  const PodcastFeed({
    required this.url,
    required this.title,
    required this.creator,
    this.artworkUrl,
  });
  final String url, title, creator;
  final String? artworkUrl;
  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'creator': creator,
    'artworkUrl': artworkUrl,
  };
  factory PodcastFeed.fromJson(Map<String, dynamic> j) => PodcastFeed(
    url: j['url'] as String,
    title: j['title'] as String,
    creator: j['creator'] as String? ?? '',
    artworkUrl: j['artworkUrl'] as String?,
  );
}

class UserPlaylist {
  UserPlaylist({required this.id, required this.name, List<String>? itemIds})
    : itemIds = itemIds ?? [];
  final String id;
  String name;
  final List<String> itemIds;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'itemIds': itemIds};
  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
    id: j['id'] as String,
    name: j['name'] as String,
    itemIds: List<String>.from(j['itemIds'] as List),
  );
}
