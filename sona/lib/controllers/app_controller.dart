import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../services/audio_handler.dart';
import '../services/media_files.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/media_item.dart';
import '../services/apis.dart';
import '../services/archive_api.dart';
import '../services/library_store.dart';
import '../services/spotify_import.dart';
import '../services/youtube_api.dart';
import '../services/youtube_playback.dart';

class AppController extends ChangeNotifier {
  AppController({required this.store, required this.handler});
  final RaagaAudioHandler handler;
  final MediaFiles files = MediaFiles();
  final ArchiveApi archive = ArchiveApi();
  final YoutubeApi youtube = YoutubeApi();
  List<MediaItem> discover = [];
  bool discoverLoading = false;
  String? discoverError;
  static const discoverQuery = 'trending songs';

  Future<void> loadDiscover({bool force = false}) async {
    if (discoverLoading || (discover.isNotEmpty && !force)) return;
    discoverLoading = true;
    discoverError = null;
    _refresh();
    try {
      final found = await youtube.search(discoverQuery);
      if (_disposed) return;
      discover = found;
    } catch (e) {
      if (_disposed) return;
      discoverError = e is YoutubeException
          ? e.message
          : 'Could not load songs. Check your connection.';
    } finally {
      discoverLoading = false;
      _refresh();
    }
  }

  final SpotifyImportService spotify = SpotifyImportService();
  List<MediaItem> onlineResults = [];
  String onlineQuery = '';
  String? onlineError;
  bool searching = false;
  bool loadingMore = false;
  bool canLoadMore = false;
  int _onlinePage = 1;
  int _searchRevision = 0;

  Future<void> searchOnline(String query) async {
    final revision = ++_searchRevision;
    onlineQuery = query.trim();
    onlineResults = [];
    onlineError = null;
    canLoadMore = false;
    loadingMore = false;
    _onlinePage = 1;
    searching = onlineQuery.isNotEmpty;
    _refresh();
    if (!searching) return;
    try {
      final found = await youtube.search(onlineQuery);
      if (_disposed || revision != _searchRevision) return;
      onlineResults = found;
      canLoadMore = false;
    } catch (e) {
      if (_disposed || revision != _searchRevision) return;
      onlineError = e is YoutubeException
          ? e.message
          : 'Could not search right now. Try again.';
    } finally {
      if (!_disposed && revision == _searchRevision) {
        searching = false;
        _refresh();
      }
    }
  }

  Future<void> moreOnline() async {
    if (!canLoadMore || loadingMore || searching) return;
    final revision = _searchRevision;
    loadingMore = true;
    onlineError = null;
    _refresh();
    try {
      final page = await archive.search(onlineQuery, page: _onlinePage + 1);
      if (_disposed || revision != _searchRevision) return;
      _onlinePage++;
      final ids = onlineResults.map((m) => m.id).toSet();
      onlineResults = [
        ...onlineResults,
        ...page.items.where((m) => ids.add(m.id)),
      ];
      canLoadMore = page.hasMore;
    } catch (e) {
      if (!_disposed && revision == _searchRevision) {
        onlineError = e is ArchiveException
            ? e.message
            : 'Could not load more. Try again.';
      }
    } finally {
      if (!_disposed && revision == _searchRevision) {
        loadingMore = false;
        _refresh();
      }
    }
  }

  void _retainOnline(MediaItem item) {
    if ((item.isArchive || item.isYoutube) &&
        !library.items.any((m) => m.id == item.id)) {
      library.items.add(item);
      _rebuildCatalog();
    }
  }

  final PodcastApi podcastApi = PodcastApi();
  SpotifyPlaylistImport? lastSpotifyImport;
  final Map<String, double?> downloading = {};
  final Set<String> _cancelledDownloads = {};
  bool libraryBusy = false;
  Timer? _sleepTimer;
  DateTime? sleepUntil;
  String? playbackError;
  bool usingYoutubePlayer = false;
  bool youtubePlayerRequested = false;
  bool _openingYoutubePlayer = false;

  Future<void> openYoutubePlayer() async {
    if (current?.isYoutube != true || _disposed || _openingYoutubePlayer)
      return;
    _openingYoutubePlayer = true;
    try {
      _wantPlay = false;
      usingYoutubePlayer = true;
      await player.stop();
      if (_disposed) return;
      loading = false;
      youtubePlayerRequested = true;
      playbackError = null;
      error = null;
      _retainOnline(current!);
      _refresh();
    } finally {
      _openingYoutubePlayer = false;
    }
  }

  void selectYoutubePlayerItem(MediaItem item) {
    current = item;
    handler.setNowPlaying(item, queue);
    _retainOnline(item);
    library.history.remove(item.id);
    library.history.insert(0, item.id);
    if (library.history.length > 50) library.history.removeLast();
    _refresh();
    unawaited(persist());
  }

  bool get hasUserContent => catalog.isNotEmpty;
  List<MediaItem> get recentItems =>
      library.history.expand((id) => catalog.where((m) => m.id == id)).toList();
  List<MediaItem> get offlineItems => catalog
      .where((m) => m.isLocal || library.downloads.containsKey(m.id))
      .toList();
  void _rebuildCatalog() {
    catalog = library.items
        .where(
          (m) =>
              !m.isPodcast &&
              !m.source.startsWith('assets/') &&
              !m.source.startsWith('saavn:'),
        )
        .toList();
  }

  String _libraryError(Object e) => e is CatalogException
      ? e.message
      : 'Could not complete that action. Check your connection and available storage.';
  final LibraryStore store;
  AudioPlayer get player => handler.player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  LibrarySnapshot library = LibrarySnapshot();
  List<MediaItem> catalog = [];
  List<MediaItem> queue = [];
  MediaItem? current;
  bool initialized = false;
  bool loading = false;
  bool shuffle = false;
  bool repeat = false;
  bool _disposed = false;
  bool _completionHandled = false;
  bool _wantPlay = false;
  String? error;
  double speed = 1;
  int _lastSavedSecond = -1;

  void _refresh() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      library = await store.read();
    } catch (_) {
      error =
          'Saved library could not be read. Changes will be saved from this session.';
    }
    _rebuildCatalog();
    try {
      await files.cleanPartialFiles();
    } catch (_) {}
    handler.onPlay = () async {
      if (current != null &&
          (!player.playing ||
              player.processingState == ProcessingState.completed))
        await togglePlayback();
    };
    handler.onPause = pause;
    handler.onStop = pause;
    handler.onNext = () => next();
    handler.onPrevious = previous;
    handler.onSeek = seek;
    handler.onQueueItem = (index) async {
      if (index >= 0 && index < queue.length)
        await playItem(queue[index], from: queue);
    };
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {
      error = 'Audio setup failed. Try playing a track again.';
    }
    _subscriptions.add(
      player.playerStateStream.listen((state) {
        _refresh();
        if (state.playing &&
            state.processingState == ProcessingState.completed &&
            !loading &&
            !_completionHandled) {
          _completionHandled = true;
          unawaited(_complete());
        }
      }),
    );
    _subscriptions.add(
      player.positionStream.listen((position) {
        if (loading ||
            current?.isPodcast != true ||
            player.processingState == ProcessingState.completed)
          return;
        final seconds = position.inSeconds;
        if (seconds % 5 == 0 && seconds != _lastSavedSecond) {
          _lastSavedSecond = seconds;
          library.progress[current!.id] = position.inMilliseconds;
          unawaited(persist());
        }
      }),
    );
    _subscriptions.add(
      player.errorStream.listen((e) {
        if (current?.isYoutube == true && loading) return;
        if (current?.isYoutube == true && !loading && !usingYoutubePlayer) {
          unawaited(openYoutubePlayer());
          return;
        }
        if (usingYoutubePlayer) return;
        playbackError = error =
            'Unable to play this audio. Tap play to try again. (${_detail(e)})';
        loading = false;
        _refresh();
      }),
    );
    initialized = true;
    _refresh();
  }

  List<MediaItem> get music => catalog.where((m) => !m.isPodcast).toList();
  List<MediaItem> get podcasts => catalog.where((m) => m.isPodcast).toList();
  List<MediaItem> get likedItems =>
      catalog.where((m) => library.likes.contains(m.id)).toList();
  bool liked(MediaItem item) => library.likes.contains(item.id);
  List<MediaItem> playlistItems(UserPlaylist p) =>
      p.itemIds.expand((id) => catalog.where((m) => m.id == id)).toList();

  Future<void> persist() async {
    try {
      await store.save(library);
    } catch (_) {
      error = 'Your changes could not be saved on this device.';
      _refresh();
    }
  }

  void _remember() {
    if (current?.isPodcast == true && !loading) {
      library.progress[current!.id] =
          player.processingState == ProcessingState.completed
          ? 0
          : player.position.inMilliseconds;
    }
  }

  Future<void> playItem(MediaItem item, {List<MediaItem>? from}) async {
    if (loading || _disposed) return;
    _remember();
    _wantPlay = true;
    loading = true;
    usingYoutubePlayer = false;
    youtubePlayerRequested = false;
    error = null;
    playbackError = null;
    _refresh();
    try {
      await player.pause();
      queue = List.of(from == null || from.isEmpty ? [item] : from);
      if (!queue.any((m) => m.id == item.id)) queue.insert(0, item);
      current = item;
      handler.setNowPlaying(item, queue);
      _completionHandled = false;
      _lastSavedSecond = -1;
      Duration? duration;
      final downloaded = library.downloads[item.id];
      if (downloaded != null &&
          await File(await files.path(downloaded)).exists()) {
        duration = await player.setFilePath(await files.path(downloaded));
      } else if (item.isLocal) {
        duration = await player.setFilePath(
          await files.path(item.source.substring(6)),
        );
      } else if (item.isYoutube) {
        duration = await loadYoutubeAudio(
          resolve: () => youtube.resolve(item),
          load: (url) => player.setUrl(url),
          stop: player.stop,
        );
      } else if (item.isArchive) {
        duration = await player.setUrl(await archive.resolve(item));
      } else if (item.isSpotify) {
        final trackId = item.spotifyTrackId;
        final preview =
            item.previewUrl ??
            (trackId == null ? null : await spotify.fetchTrackPreview(trackId));
        if (preview == null) {
          throw const CatalogException(
            'Spotify does not provide a preview for this track. Raaga imports the playlist, but it cannot stream Spotify full tracks as direct audio.',
          );
        }
        duration = await player.setUrl(preview);
      } else if (item.source.startsWith('assets/')) {
        duration = await player.setAsset(item.source);
      } else {
        duration = await player.setUrl(item.source);
      }
      _retainOnline(item);
      library.history.remove(item.id);
      library.history.insert(0, item.id);
      if (library.history.length > 50)
        library.history.removeRange(50, library.history.length);
      final saved = item.isPodcast ? library.progress[item.id] ?? 0 : 0;
      if (saved > 0 &&
          duration != null &&
          saved < duration.inMilliseconds - 1000) {
        await player.seek(Duration(milliseconds: saved));
      }
      await player.setSpeed(item.isPodcast ? speed : 1);
      loading = false;
      _refresh();
      unawaited(_start());
      unawaited(persist());
    } catch (e) {
      if (item.isYoutube && !_disposed) {
        await openYoutubePlayer();
        return;
      }
      playbackError = error = e is YoutubeException
          ? e.message
          : e is ArchiveException
          ? e.message
          : e is CatalogException
          ? e.message
          : 'Unable to load this audio. Check the file or connection and tap play to retry. (${_detail(e)})';
      loading = false;
      _refresh();
    }
  }

  String _detail(Object e) {
    final text = e.toString().replaceAll('\n', ' ').trim();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  Future<void> _start() async {
    if (_disposed || !_wantPlay) return;
    try {
      await player.play();
    } catch (e) {
      if (current?.isYoutube == true) {
        await openYoutubePlayer();
        return;
      }
      playbackError = error =
          'Playback failed. Please try again. (${_detail(e)})';
      _refresh();
    }
  }

  Future<void> togglePlayback() async {
    if (loading || current == null) return;
    if (usingYoutubePlayer) {
      await openYoutubePlayer();
      return;
    }
    if (playbackError != null ||
        player.processingState == ProcessingState.idle) {
      await playItem(current!, from: queue);
      return;
    }
    if (player.playing && player.processingState != ProcessingState.completed) {
      _wantPlay = false;
      await player.pause();
      _remember();
      await persist();
    } else {
      _wantPlay = true;
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
        _completionHandled = false;
      }
      unawaited(_start());
    }
    _refresh();
  }

  Future<void> _complete() async {
    if (current == null) return;
    final completedId = current!.id;
    if (current!.isPodcast) library.progress[current!.id] = 0;
    await persist();
    if (_disposed ||
        loading ||
        !_wantPlay ||
        current?.id != completedId ||
        player.processingState != ProcessingState.completed)
      return;
    if (repeat) {
      await player.seek(Duration.zero);
      _completionHandled = false;
      unawaited(_start());
    } else {
      await next(automatic: true);
    }
  }

  Future<void> next({bool automatic = false}) async {
    if (queue.isEmpty || current == null || loading) return;
    final index = queue.indexWhere((m) => m.id == current!.id);
    if (shuffle && queue.length > 1) {
      final options = queue.where((m) => m.id != current!.id).toList();
      await playItem(options[Random().nextInt(options.length)], from: queue);
    } else if (index + 1 < queue.length) {
      await playItem(queue[index + 1], from: queue);
    } else if (!automatic) {
      await playItem(queue.first, from: queue);
    } else {
      await player.pause();
      _refresh();
    }
  }

  Future<void> previous() async {
    if (current == null || loading) return;
    if (player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final index = queue.indexWhere((m) => m.id == current!.id);
    if (index > 0)
      await playItem(queue[index - 1], from: queue);
    else {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) async {
    if (loading || current == null) return;
    final maxMs = player.duration?.inMilliseconds ?? 0;
    final ms = position.inMilliseconds.clamp(0, maxMs).toInt();
    try {
      await player.seek(Duration(milliseconds: ms));
      if (ms < maxMs) _completionHandled = false;
      _remember();
      await persist();
    } catch (_) {
      error = 'Could not seek in this audio.';
      _refresh();
    }
  }

  Future<void> cycleSpeed() async {
    if (loading) return;
    const speeds = [1.0, 1.25, 1.5, 2.0];
    final nextSpeed = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
    try {
      await player.setSpeed(nextSpeed);
      speed = nextSpeed;
    } catch (_) {
      error = 'Playback speed could not be changed.';
    }
    _refresh();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    _refresh();
  }

  void toggleRepeat() {
    repeat = !repeat;
    _refresh();
  }

  void clearError() {
    error = null;
    _refresh();
  }

  void toggleLike(MediaItem item) {
    _retainOnline(item);
    if (!library.likes.remove(item.id)) library.likes.add(item.id);
    _refresh();
    unawaited(persist());
  }

  UserPlaylist? createPlaylist(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final p = UserPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
    );
    library.playlists.add(p);
    _refresh();
    unawaited(persist());
    return p;
  }

  void addToPlaylist(UserPlaylist p, MediaItem item) {
    _retainOnline(item);
    if (!p.itemIds.contains(item.id)) p.itemIds.add(item.id);
    _refresh();
    unawaited(persist());
  }

  void removeFromPlaylist(UserPlaylist p, MediaItem item) {
    p.itemIds.remove(item.id);
    _refresh();
    unawaited(persist());
  }

  void deletePlaylist(UserPlaylist p) {
    library.playlists.remove(p);
    _refresh();
    unawaited(persist());
  }

  Future<void> pause() async {
    _wantPlay = false;
    await player.pause();
    _remember();
    await persist();
    _refresh();
  }

  Future<void> setForeground(bool foreground) async {
    if (!foreground && !_disposed) {
      _remember();
      await persist();
    }
  }

  Future<void> importMusic() async {
    if (libraryBusy) return;
    libraryBusy = true;
    error = null;
    _refresh();
    try {
      final items = await files.pickMusic();
      final ids = library.items.map((i) => i.id).toSet();
      library.items.insertAll(0, items.where((i) => ids.add(i.id)));
      _rebuildCatalog();
      await persist();
    } catch (e) {
      error = _libraryError(e);
    } finally {
      libraryBusy = false;
      _refresh();
    }
  }

  bool isSpotifyPlaylistReference(String text) =>
      SpotifyImportService.findPlaylistReference(text) != null;

  String? spotifyPlaylistReference(String text) =>
      SpotifyImportService.findPlaylistReference(text);

  Future<UserPlaylist?> importSpotifyPlaylist(String address) async {
    if (libraryBusy) return null;
    libraryBusy = true;
    error = null;
    _refresh();
    try {
      final imported = await spotify.fetchPlaylist(address);
      lastSpotifyImport = imported;
      final existingIds = library.items.map((item) => item.id).toSet();
      library.items.insertAll(
        0,
        imported.items.where((item) => existingIds.add(item.id)),
      );
      final playlistId = 'spotify-playlist-${imported.id}';
      UserPlaylist? playlist;
      for (final candidate in library.playlists) {
        if (candidate.id == playlistId) {
          playlist = candidate;
          break;
        }
      }
      final targetPlaylist =
          playlist ?? UserPlaylist(id: playlistId, name: imported.name);
      if (!library.playlists.any((item) => item.id == targetPlaylist.id)) {
        library.playlists.add(targetPlaylist);
      }
      targetPlaylist.name = imported.name;
      targetPlaylist.itemIds
        ..clear()
        ..addAll(imported.items.map((item) => item.id));
      _rebuildCatalog();
      await persist();
      _refresh();
      return targetPlaylist;
    } catch (e) {
      error = _libraryError(e);
      _refresh();
      return null;
    } finally {
      libraryBusy = false;
      _refresh();
    }
  }

  Future<bool> addAudioLink(String title, String address) async {
    try {
      final uri = httpsAddress(address);
      if (title.trim().isEmpty)
        throw const CatalogException('Enter a title for this track.');
      final id = 'stream-${sha256.convert(utf8.encode(uri.toString()))}';
      if (!library.items.any((i) => i.id == id)) {
        library.items.insert(
          0,
          MediaItem(
            id: id,
            title: title.trim(),
            creator: 'Your audio link',
            category: 'Your music',
            kind: MediaKind.music,
            source: uri.toString(),
            color: 0xFF8AB4FF,
            art: 1,
            description: 'Audio streamed from a link you added.',
          ),
        );
      }
      _rebuildCatalog();
      await persist();
      _refresh();
      return true;
    } catch (e) {
      error = _libraryError(e);
      _refresh();
      return false;
    }
  }

  Future<bool> subscribe(String address) async {
    if (libraryBusy) return false;
    libraryBusy = true;
    error = null;
    _refresh();
    try {
      final result = await podcastApi.fetchFeed(address);
      _mergeFeed(result);
      await persist();
      return true;
    } catch (e) {
      error = _libraryError(e);
      return false;
    } finally {
      libraryBusy = false;
      _refresh();
    }
  }

  void _mergeFeed(FeedResult result) {
    library.feeds.removeWhere((f) => f.url == result.feed.url);
    library.feeds.add(result.feed);
    final ids = result.episodes.map((e) => e.id).toSet();
    library.items.removeWhere((i) => ids.contains(i.id));
    library.items.insertAll(0, result.episodes);
    _rebuildCatalog();
  }

  Future<void> refreshFeeds() async {
    if (libraryBusy) return;
    libraryBusy = true;
    error = null;
    _refresh();
    var failures = 0;
    try {
      for (final feed in List<PodcastFeed>.of(library.feeds)) {
        try {
          _mergeFeed(await podcastApi.fetchFeed(feed.url));
        } catch (_) {
          failures++;
        }
      }
      await persist();
      if (failures > 0)
        error =
            '$failures feed(s) could not refresh. Saved episodes are still available.';
    } finally {
      libraryBusy = false;
      _refresh();
    }
  }

  Future<void> removeItem(MediaItem item) async {
    if (loading || downloading.containsKey(item.id)) return;
    if (current?.id == item.id) {
      await handler.stop();
      current = null;
    }
    queue.removeWhere((i) => i.id == item.id);
    if (current != null) {
      handler.setNowPlaying(current!, queue);
    } else {
      handler.queue.add([]);
      handler.mediaItem.add(null);
    }
    library.items.removeWhere((i) => i.id == item.id);
    library.likes.remove(item.id);
    library.progress.remove(item.id);
    library.history.remove(item.id);
    for (final p in library.playlists) {
      p.itemIds.remove(item.id);
    }
    final downloaded = library.downloads.remove(item.id);
    _rebuildCatalog();
    await persist();
    _refresh();
    try {
      if (item.isLocal) await files.remove(item.source.substring(6));
      if (downloaded != null) await files.remove(downloaded);
    } catch (_) {
      error =
          'Removed from the library, but its saved audio file could not be deleted.';
      _refresh();
    }
  }

  Future<void> unsubscribe(PodcastFeed feed) async {
    if (libraryBusy) return;
    library.feeds.removeWhere((f) => f.url == feed.url);
    await persist();
    _refresh();
  }

  Future<void> download(MediaItem item) async {
    if (!item.isPodcast ||
        item.feedUrl == null ||
        downloading.containsKey(item.id) ||
        library.downloads.containsKey(item.id))
      return;
    downloading[item.id] = null;
    error = null;
    _refresh();
    try {
      final name = await files.download(item, (value) {
        downloading[item.id] = value;
        _refresh();
      });
      library.downloads[item.id] = name;
      await persist();
    } catch (e) {
      if (!_cancelledDownloads.contains(item.id)) error = _libraryError(e);
    } finally {
      downloading.remove(item.id);
      _cancelledDownloads.remove(item.id);
      _refresh();
    }
  }

  void cancelDownload(String id) {
    if (!downloading.containsKey(id)) return;
    _cancelledDownloads.add(id);
    files.cancel(id);
  }

  Future<void> removeDownload(MediaItem item) async {
    if (loading || downloading.containsKey(item.id)) return;
    if (current?.id == item.id) await handler.stop();
    final name = library.downloads[item.id];
    if (name == null) return;
    try {
      await files.remove(name);
      library.downloads.remove(item.id);
      await persist();
      _refresh();
    } catch (_) {
      error = 'Could not delete the downloaded file.';
      _refresh();
    }
  }

  void playNext(MediaItem item) {
    if (current == null) {
      unawaited(playItem(item));
      return;
    }
    if (item.id == current!.id) return;
    queue.removeWhere((i) => i.id == item.id);
    final index = queue.indexWhere((i) => i.id == current!.id);
    queue.insert(index + 1, item);
    handler.setNowPlaying(current!, queue);
    _refresh();
  }

  void renamePlaylist(UserPlaylist playlist, String name) {
    if (name.trim().isEmpty) return;
    playlist.name = name.trim();
    unawaited(persist());
    _refresh();
  }

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepUntil = minutes == 0
        ? null
        : DateTime.now().add(Duration(minutes: minutes));
    if (minutes > 0)
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        sleepUntil = null;
        unawaited(pause());
        _refresh();
      });
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepTimer?.cancel();
    files.dispose();
    podcastApi.dispose();
    spotify.dispose();
    _searchRevision++;
    archive.dispose();
    youtube.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
