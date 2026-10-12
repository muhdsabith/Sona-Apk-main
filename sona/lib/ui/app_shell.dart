import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../controllers/app_controller.dart';
import '../models/media_item.dart';
import 'cover_art.dart';
import 'olam_theme.dart';
import 'wave_track.dart';
import 'youtube_playback_page.dart';

String clock(Duration value) {
  final minutes = value.inMinutes.toString();
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int tab = 0;
  String sortOrder = 'recommended';
  String query = '';
  final search = TextEditingController();
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  bool _youtubePageOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_handleYoutubePlayer);
    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedMedia,
    );
    unawaited(_loadInitialShare());
    unawaited(c.loadDiscover());
  }

  Future<void> _loadInitialShare() async {
    try {
      final items = await ReceiveSharingIntent.instance.getInitialMedia();
      _handleSharedMedia(items);
      ReceiveSharingIntent.instance.reset();
    } catch (_) {}
  }

  void _handleSharedMedia(List<SharedMediaFile> items) {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(c.setForeground(state == AppLifecycleState.resumed));
  }

  AppController get c => widget.controller;

  void _handleYoutubePlayer() {
    if (!c.youtubePlayerRequested || !mounted) return;
    c.youtubePlayerRequested = false;
    if (_youtubePageOpen) return;
    _youtubePageOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final item = c.current;
      if (!mounted || item?.isYoutube != true) {
        _youtubePageOpen = false;
        return;
      }
      try {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => YoutubePlaybackPage(
              item: item!,
              queue: List.of(c.queue),
              onSelected: c.selectYoutubePlayerItem,
            ),
          ),
        );
      } finally {
        _youtubePageOpen = false;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_handleYoutubePlayer);
    unawaited(_shareSubscription?.cancel());
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (c.error != null && c.playbackError == null)
                  MaterialBanner(
                    content: Text(c.error!),
                    actions: [
                      TextButton(
                        onPressed: c.clearError,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                if (c.libraryBusy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: !c.initialized
                      ? const Center(child: CircularProgressIndicator())
                      : IndexedStack(
                          index: tab,
                          children: [
                            _home(),
                            _search(),
                            _library(),
                            _settingsPage(),
                          ],
                        ),
                ),
                if (c.current != null) _miniPlayer(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xEB33313D), Color(0xEB22212B)],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: hairline),
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                height: 72,
                selectedIndex: tab,
                onDestinationSelected: (value) => setState(() => tab = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search_rounded),
                    label: 'Search',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _heading(String eyebrow, String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  color: muted,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );

  List<MediaItem> get _frontTracks {
    final items = <MediaItem>[...c.recentItems, ...c.catalog];
    final ids = <String>{};
    final tracks = items.where((item) => ids.add(item.id)).toList();
    if (sortOrder == 'title')
      tracks.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    if (sortOrder == 'artist')
      tracks.sort(
        (a, b) => a.creator.toLowerCase().compareTo(b.creator.toLowerCase()),
      );
    return tracks;
  }

  Widget _home() {
    final tracks = _frontTracks;
    return ListView(
      key: const PageStorageKey('tracks'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'branding/raaga-icon.png',
                  width: 48,
                  height: 48,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'RAAGA',
                  style: TextStyle(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Search',
                onPressed: () => setState(() => tab = 1),
                icon: const Icon(Icons.search),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Favourites',
                onPressed: () => _collection('Favourites', () => c.likedItems),
                icon: const Icon(Icons.favorite_border),
              ),
            ],
          ),
        ),
        _heading('A LITTLE MUSIC, JUST FOR YOU', 'Hello, music lover.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Trending now',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh songs',
                onPressed: c.discoverLoading
                    ? null
                    : () => unawaited(c.loadDiscover(force: true)),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (c.discoverLoading && c.discover.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (c.discoverError != null && c.discover.isEmpty)
          _Empty(
            icon: Icons.cloud_off,
            title: 'Could not load songs',
            body: c.discoverError!,
            action: TextButton(
              onPressed: () => unawaited(c.loadDiscover(force: true)),
              child: const Text('Retry'),
            ),
          ),
        ...c.discover.map((item) => _row(item, c.discover)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${tracks.length} songs',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sort songs',
                initialValue: sortOrder,
                onSelected: (value) => setState(() => sortOrder = value),
                icon: const Icon(Icons.sort_rounded, size: 21),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'recommended',
                    child: Text('Original order'),
                  ),
                  PopupMenuItem(value: 'title', child: Text('Song title')),
                  PopupMenuItem(value: 'artist', child: Text('Artist')),
                ],
              ),
            ],
          ),
        ),
        if (tracks.isEmpty && c.discover.isEmpty && !c.discoverLoading)
          _Empty(
            icon: Icons.music_note_outlined,
            title: 'Bring your music along',
            body: 'Import audio from your phone to listen offline.',
            action: TextButton(
              onPressed: c.libraryBusy ? null : c.importMusic,
              child: const Text('Import music'),
            ),
          ),
        if (tracks.isNotEmpty) _section('Your songs'),
        ...tracks.map((item) => _row(item, tracks)),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'LET THE MUSIC FLOW',
            style: TextStyle(color: muted, fontSize: 9, letterSpacing: 2.4),
          ),
        ),
      ],
    );
  }

  Widget _musicCards(List<MediaItem> items, List<MediaItem> collection) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: SizedBox(
                  width: 174,
                  child: Material(
                    color: paper,
                    borderRadius: BorderRadius.circular(26),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: c.loading ? null : () => _play(item, collection),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CoverArt(item: item, size: 154),
                            const SizedBox(height: 12),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.creator,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.headphones_rounded,
                                  size: 14,
                                  color: accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Background play',
                                  style: const TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _settingsPage() => ListView(
    key: const PageStorageKey('settings'),
    padding: const EdgeInsets.only(bottom: 28),
    children: [
      _heading('MAKE YOURSELF AT HOME', 'Settings'),
      _section('Your music'),
      ListTile(
        leading: const Icon(Icons.audio_file_outlined),
        title: const Text('Import songs'),
        subtitle: const Text('Audio files from your phone'),
        onTap: c.libraryBusy ? null : c.importMusic,
      ),
      ListTile(
        leading: const Icon(Icons.link_rounded),
        title: const Text('Add a direct audio link'),
        subtitle: const Text('For your own or licensed music'),
        onTap: _audioLink,
      ),
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Imported songs and direct audio streams support background listening and lock-screen controls.',
          style: TextStyle(color: muted, height: 1.5),
        ),
      ),
      _section('About'),
      const ListTile(
        leading: Icon(Icons.waves_rounded),
        title: Text('Raaga 4.8.0'),
        subtitle: Text('Let the music flow.'),
      ),
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Your library lives on this device. Uninstalling removes saved playlists and imported copies.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _section(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: muted)),
        ],
      ],
    ),
  );

  Widget _row(
    MediaItem item,
    List<MediaItem> collection, {
    UserPlaylist? playlist,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    child: Material(
      color: paper,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        leading: CoverArt(item: item, size: 46),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: c.current?.id == item.id ? accent : ink,
          ),
        ),
        subtitle: Text(
          '${item.creator}${item.isLocal || c.library.downloads.containsKey(item.id)
              ? ' · Offline'
              : item.isYoutube
              ? ' · YouTube'
              : item.isArchive
              ? ' · ${item.category}'
              : item.isSpotify
              ? ' · Spotify preview'
              : ' · Background play'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        onTap: c.loading ? null : () => _play(item, collection),
        trailing: PopupMenuButton<String>(
          tooltip: 'Track options',
          onSelected: (action) {
            if (action == 'like') c.toggleLike(item);
            if (action == 'add') _addToPlaylist(item);
            if (action == 'next') c.playNext(item);
            if (action == 'deleteItem') _deleteItem(item);
            if (action == 'remove' && playlist != null)
              c.removeFromPlaylist(playlist, item);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'like',
              child: Text(
                c.liked(item) ? 'Remove from favourites' : 'Add to favourites',
              ),
            ),
            const PopupMenuItem(value: 'add', child: Text('Add to playlist')),
            const PopupMenuItem(value: 'next', child: Text('Play next')),
            if (c.library.items.any((i) => i.id == item.id))
              const PopupMenuItem(
                value: 'deleteItem',
                child: Text('Remove from Raaga'),
              ),
            if (playlist != null)
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove from playlist'),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _search() {
    final normalized = query.trim().toLowerCase();
    final saved = c.catalog
        .where(
          (m) =>
              !m.isYoutube &&
              '${m.title} ${m.creator}'.toLowerCase().contains(normalized),
        )
        .toList();
    return ListView(
      key: const PageStorageKey('search'),
      children: [
        _heading('FIND YOUR FREQUENCY', 'Search'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              setState(() => query = value);
              if (value.trim().isEmpty) unawaited(c.searchOnline(''));
            },
            onSubmitted: (value) => unawaited(c.searchOnline(value)),
            decoration: InputDecoration(
              hintText: 'Search songs on YouTube',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => unawaited(c.searchOnline(search.text)),
              ),
            ),
          ),
        ),
        if (c.searching)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (c.onlineError != null)
          _Empty(
            icon: Icons.cloud_off,
            title: 'Could not load songs',
            body: c.onlineError!,
            action: TextButton(
              onPressed: () => c.searchOnline(c.onlineQuery),
              child: const Text('Retry'),
            ),
          ),
        if (!c.searching &&
            c.onlineError == null &&
            c.onlineQuery.isNotEmpty &&
            c.onlineResults.isEmpty)
          const _Empty(
            icon: Icons.search_off,
            title: 'No songs found',
            body: 'Try a different song or artist.',
          ),
        if (c.onlineResults.isNotEmpty) ...[
          _section('YouTube', subtitle: c.onlineQuery),
          ...c.onlineResults.map((m) => _row(m, c.onlineResults)),
        ],
        if (saved.isNotEmpty) ...[
          _section('On your phone'),
          ...saved.map((m) => _row(m, saved)),
        ] else if (c.onlineQuery.isEmpty)
          _Empty(
            icon: Icons.search_off,
            title: normalized.isEmpty
                ? 'Search for any song'
                : 'No songs found',
            body: normalized.isEmpty
                ? 'Type a song or artist and press search to stream it from YouTube.'
                : 'Press search to look on YouTube.',
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _library() => ListView(
    key: const PageStorageKey('library'),
    children: [
      _heading(
        'YOUR PERSONAL COLLECTION',
        'Saved & loved',
        trailing: IconButton.filledTonal(
          tooltip: 'Create playlist',
          onPressed: _createPlaylist,
          icon: const Icon(Icons.add),
        ),
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.favorite, color: cream),
        ),
        title: const Text(
          'Favourites',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${c.likedItems.length} saved songs'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _collection('Favourites', () => c.likedItems),
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: const Icon(Icons.audio_file, color: accent),
        title: const Text('Import music'),
        subtitle: const Text(
          'Play with the screen off and use lock-screen controls',
        ),
        onTap: c.libraryBusy ? null : c.importMusic,
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: const Icon(Icons.link, color: accent),
        title: const Text('Add an audio link'),
        subtitle: const Text(
          'Direct audio streams support background listening',
        ),
        onTap: _audioLink,
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: const Icon(Icons.download_done, color: accent),
        title: const Text('Available offline'),
        subtitle: Text('${c.offlineItems.length} tracks on this device'),
        onTap: () => _collection('Available offline', () => c.offlineItems),
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: const Icon(Icons.history, color: accent),
        title: const Text('Recently played'),
        onTap: () => _collection('Recently played', () => c.recentItems),
      ),
      _section(
        'Made by you',
        subtitle: 'Playlists for every version of your day',
      ),
      if (c.library.playlists.isEmpty)
        _Empty(
          icon: Icons.queue_music,
          title: 'Make it your own',
          body:
              'Create a playlist, then use a track’s menu to add your favourites.',
          action: TextButton.icon(
            onPressed: _createPlaylist,
            icon: const Icon(Icons.add),
            label: const Text('Create playlist'),
          ),
        ),
      ...c.library.playlists.map(
        (p) => ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.queue_music, color: accent),
          ),
          title: Text(p.name),
          subtitle: Text('${c.playlistItems(p).length} songs'),
          onTap: () =>
              _collection(p.name, () => c.playlistItems(p), playlist: p),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename')
                _renamePlaylist(p);
              else
                _deletePlaylist(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('About Raaga'),
        subtitle: const Text('Version 4.8.0 · Let the music flow'),
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'Raaga',
          applicationVersion: '4.8.0',
          applicationIcon: Image.asset(
            'branding/raaga-icon.png',
            width: 48,
            height: 48,
          ),
          children: [
            const Text(
              'Raaga is an independent app that plays the music stored on your device and your own audio links.',
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Your library lives on this device. Uninstalling Raaga removes saved playlists and imported copies.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
      const SizedBox(height: 24),
    ],
  );

  Future<void> _audioLink() async {
    var title = '', address = '';
    final values = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add an audio link'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => title = v,
                decoration: const InputDecoration(labelText: 'Track title'),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => address = v,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Direct HTTPS audio URL',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Use a direct audio file address from your own or licensed catalog. Web page links are not audio files.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, [title, address]),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (values != null) await c.addAudioLink(values[0], values[1]);
  }

  Future<void> _deleteItem(MediaItem item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Raaga?'),
        content: Text(
          'Remove “${item.title}” and its saved copy from Raaga? Your original phone file is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) await c.removeItem(item);
  }

  Future<void> _renamePlaylist(UserPlaylist playlist) async {
    var name = playlist.name;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextFormField(
          initialValue: name,
          maxLength: 60,
          onChanged: (value) => name = value,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(ctx, name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) c.renamePlaylist(playlist, result);
  }

  Future<void> _sleep() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Sleep timer')),
            for (final n in [0, 15, 30, 45, 60])
              ListTile(
                title: Text(n == 0 ? 'Off' : '$n minutes'),
                onTap: () => Navigator.pop(ctx, n),
              ),
          ],
        ),
      ),
    );
    if (minutes != null) c.setSleepTimer(minutes);
  }

  Future<UserPlaylist?> _createPlaylist() async {
    String name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A mix of your own'),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onChanged: (value) => name = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return null;
    return c.createPlaylist(result);
  }

  Future<void> _deletePlaylist(UserPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('Remove “${playlist.name}” from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) c.deletePlaylist(playlist);
  }

  Future<void> _addToPlaylist(MediaItem item) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: ListView(
            children: [
              const ListTile(
                title: Text(
                  'Add to playlist',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New playlist'),
                onTap: () => Navigator.pop(context, 'new'),
              ),
              ...c.library.playlists.map(
                (p) => ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(p.name),
                  trailing: p.itemIds.contains(item.id)
                      ? const Icon(Icons.check, color: accent)
                      : null,
                  onTap: () => Navigator.pop(context, p.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    UserPlaylist? playlist;
    if (selected == 'new') {
      playlist = await _createPlaylist();
    } else {
      playlist = c.library.playlists.where((p) => p.id == selected).firstOrNull;
    }
    if (playlist == null || !mounted) return;
    c.addToPlaylist(playlist, item);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added to ${playlist.name}')));
  }

  void _collection(
    String title,
    List<MediaItem> Function() items, {
    UserPlaylist? playlist,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final collection = items();
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (collection.isEmpty)
                    const _Empty(
                      icon: Icons.music_note,
                      title: 'Your next favourite is waiting',
                      body:
                          'Browse the collection and save something you love.',
                    ),
                  ...collection.map(
                    (m) => _row(m, collection, playlist: playlist),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _play(MediaItem item, List<MediaItem> collection) =>
      c.playItem(item, from: collection);

  Widget _miniPlayer() {
    final item = c.current!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: paper,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _fullPlayer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    CoverArt(item: item, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            c.usingYoutubePlayer
                                ? 'Tap Play to open YouTube player'
                                : c.playbackError != null
                                ? 'Playback unavailable · Tap for details'
                                : c.loading
                                ? 'Getting your song ready…'
                                : item.creator,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    _playButton(compact: true),
                    IconButton(
                      tooltip: 'Next song',
                      onPressed: c.loading ? null : () => c.next(),
                      icon: const Icon(Icons.skip_next_rounded, size: 25),
                    ),
                  ],
                ),
              ),
              StreamBuilder<Duration>(
                stream: c.player.positionStream,
                builder: (_, snapshot) {
                  final total = c.player.duration?.inMilliseconds ?? 0;
                  final position = snapshot.data?.inMilliseconds ?? 0;
                  return LinearProgressIndicator(
                    minHeight: 2,
                    value: total > 0
                        ? (position / total).clamp(0.0, 1.0).toDouble()
                        : 0,
                    backgroundColor: hairline,
                    color: accent,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _playing =>
      c.player.playing && c.player.processingState != ProcessingState.completed;

  Widget _playButton({bool compact = false}) => c.loading
      ? SizedBox(
          width: compact ? 48 : 64,
          height: compact ? 48 : 64,
          child: const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      : IconButton.filled(
          tooltip: _playing ? 'Pause' : 'Play',
          style: IconButton.styleFrom(
            backgroundColor: compact ? Colors.transparent : accent,
            foregroundColor: compact ? ink : cream,
            minimumSize: Size.square(compact ? 48 : 64),
          ),
          onPressed: c.togglePlayback,
          icon: Icon(
            _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: compact ? 28 : 40,
          ),
        );

  Widget _timeline() => StreamBuilder<Duration?>(
    stream: c.player.durationStream,
    builder: (_, durationSnapshot) => StreamBuilder<Duration>(
      stream: c.player.positionStream,
      builder: (_, positionSnapshot) {
        final unavailable = c.loading || c.playbackError != null;
        final duration = unavailable
            ? Duration.zero
            : durationSnapshot.data ?? c.player.duration ?? Duration.zero;
        final position = unavailable
            ? Duration.zero
            : positionSnapshot.data ?? c.player.position;
        final total = duration.inMilliseconds;
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(
                context,
              ).copyWith(trackShape: const WaveTrack()),
              child: Slider(
                semanticFormatterCallback: (value) =>
                    clock(Duration(milliseconds: value.round())),
                value: total > 0
                    ? position.inMilliseconds.clamp(0, total).toDouble()
                    : 0,
                max: total > 0 ? total.toDouble() : 1,
                onChanged: unavailable || total == 0
                    ? null
                    : (v) => c.seek(Duration(milliseconds: v.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    clock(position),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  Text(
                    total == 0 ? '—:—' : clock(duration),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  void _fullPlayer() {
    if (c.usingYoutubePlayer) {
      unawaited(c.openYoutubePlayer());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: paper,
      builder: (sheetContext) => AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final item = c.current;
          if (item == null) return const SizedBox.shrink();
          final artSize = (MediaQuery.sizeOf(context).height * .37).clamp(
            180.0,
            370.0,
          );
          return FractionallySizedBox(
            heightFactor: .98,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Close player',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'NOW PLAYING',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: c.liked(item)
                                ? 'Remove favourite'
                                : 'Save favourite',
                            onPressed: () => c.toggleLike(item),
                            icon: Icon(
                              c.liked(item)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_outline_rounded,
                              color: c.liked(item) ? accent : ink,
                              size: 21,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add to playlist',
                            onPressed: () => _addToPlaylist(item),
                            icon: const Icon(
                              Icons.playlist_add_rounded,
                              size: 23,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Queue',
                            onPressed: () =>
                                _collection('Up next', () => c.queue),
                            icon: const Icon(
                              Icons.queue_music_rounded,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      LayoutBuilder(
                        builder: (_, bounds) => Center(
                          child: CoverArt(
                            item: item,
                            size: artSize.clamp(0, bounds.maxWidth).toDouble(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Tooltip(
                        message: item.title,
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 24,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.creator,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      if (c.loading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Getting your song ready…',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      if (item.isYoutube && !c.loading)
                        TextButton.icon(
                          onPressed: c.openYoutubePlayer,
                          icon: const Icon(Icons.smart_display_outlined),
                          label: const Text('Use YouTube player'),
                        ),
                      _timeline(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: 'Shuffle',
                            onPressed: c.toggleShuffle,
                            isSelected: c.shuffle,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: c.shuffle ? accent : muted,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Previous song',
                            onPressed: c.loading ? null : c.previous,
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 29,
                            ),
                          ),
                          _playButton(),
                          IconButton(
                            tooltip: 'Next song',
                            onPressed: c.loading ? null : () => c.next(),
                            icon: const Icon(Icons.skip_next_rounded, size: 29),
                          ),
                          IconButton(
                            tooltip: 'Repeat song',
                            onPressed: c.toggleRepeat,
                            isSelected: c.repeat,
                            icon: Icon(
                              Icons.repeat_one_rounded,
                              color: c.repeat ? accent : muted,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          onPressed: _sleep,
                          icon: const Icon(Icons.bedtime_outlined, size: 17),
                          label: Text(
                            c.sleepUntil == null
                                ? 'Sleep timer'
                                : 'Sleep timer is on',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (c.playbackError != null)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: paper,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Playback unavailable',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                c.playbackError!,
                                style: const TextStyle(
                                  color: ink,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      children: [
        Icon(icon, size: 44, color: accent),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}
