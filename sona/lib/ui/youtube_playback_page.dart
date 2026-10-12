import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/media_item.dart';

class YoutubePlaybackPage extends StatefulWidget {
  const YoutubePlaybackPage({
    super.key,
    required this.item,
    required this.queue,
    required this.onSelected,
  });
  final MediaItem item;
  final List<MediaItem> queue;
  final ValueChanged<MediaItem> onSelected;

  @override
  State<YoutubePlaybackPage> createState() => _YoutubePlaybackPageState();
}

class _YoutubePlaybackPageState extends State<YoutubePlaybackPage>
    with WidgetsBindingObserver {
  late final YoutubePlayerController _player;
  late final List<MediaItem> _queue;
  late int _index;
  StreamSubscription<YoutubePlayerValue>? _subscription;
  bool _ended = false;
  String? _message;

  MediaItem get _item => _queue[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queue = widget.queue.where((item) => item.isYoutube).toList();
    _index = _queue.indexWhere((item) => item.id == widget.item.id);
    if (_index < 0) {
      _queue.insert(0, widget.item);
      _index = 0;
    }
    _player = YoutubePlayerController.fromVideoId(
      videoId: _item.youtubeId!,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        origin: 'https://com.example.sona',
      ),
    );
    _subscription = _player.listen((value) {
      if (!mounted) return;
      if (value.playerState == PlayerState.playing) _ended = false;
      if (value.playerState == PlayerState.ended && !_ended) {
        _ended = true;
        if (_index + 1 < _queue.length) unawaited(_select(_index + 1));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelected(_item);
    });
  }

  Future<void> _select(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _ended = true;
    setState(() {
      _index = index;
      _message = null;
    });
    widget.onSelected(_item);
    await _player.loadVideoById(videoId: _item.youtubeId!);
  }

  Future<void> _openInYoutube() async {
    await _player.pauseVideo();
    try {
      final opened = await launchUrl(
        Uri.https('www.youtube.com', '/watch', {'v': _item.youtubeId!}),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _message = 'Could not open YouTube. Try another song.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not open YouTube.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_player.pauseVideo());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_player.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('YouTube playback')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            children: [
              LayoutBuilder(
                builder: (context, bounds) => YoutubePlayer(
                  controller: _player,
                  aspectRatio:
                      bounds.maxWidth / math.max(200, bounds.maxWidth * 9 / 16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _item.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(_item.creator),
                    const SizedBox(height: 20),
                    const Text(
                      'Tap Play in the video if it does not start automatically. '
                      'Keep this screen open while listening.',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous YouTube song',
                          onPressed: _index > 0
                              ? () => _select(_index - 1)
                              : null,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        Text('${_index + 1} / ${_queue.length}'),
                        IconButton(
                          tooltip: 'Next YouTube song',
                          onPressed: _index + 1 < _queue.length
                              ? () => _select(_index + 1)
                              : null,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                    YoutubeValueBuilder(
                      controller: _player,
                      builder: (context, value) => value.hasError
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'YouTube could not play this video here '
                                '(${value.error.code}). Try another song or open it in YouTube.',
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (_message != null) Text(_message!),
                    TextButton.icon(
                      onPressed: _openInYoutube,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open in YouTube'),
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
}
