import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../models/media_item.dart' as app;

class RaagaAudioHandler extends BaseAudioHandler with SeekHandler {
  final player = ja.AudioPlayer(useProxyForRequestHeaders: false);
  Future<void> Function()? onPlay, onPause, onNext, onPrevious, onStop;
  Future<void> Function(Duration)? onSeek;
  Future<void> Function(int)? onQueueItem;
  int _index = 0;
  RaagaAudioHandler() {
    player.playbackEventStream.listen(
      (_) => broadcast(),
      onError: (Object _) => broadcast(),
    );
    player.playerStateStream.listen((_) => broadcast());
    player.speedStream.listen((_) => broadcast());
    player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null)
        mediaItem.add(item.copyWith(duration: duration));
    });
  }
  MediaItem _media(app.MediaItem item) => MediaItem(
    id: item.id,
    title: item.title,
    artist: item.creator,
    album: item.isPodcast ? item.creator : 'Raaga',
    duration: item.durationMs == null
        ? null
        : Duration(milliseconds: item.durationMs!),
    artUri: item.artworkUrl?.startsWith('https://') == true
        ? Uri.tryParse(item.artworkUrl!)
        : null,
  );
  void setNowPlaying(app.MediaItem item, List<app.MediaItem> items) {
    queue.add(items.map(_media).toList());
    _index = items.indexWhere((i) => i.id == item.id);
    mediaItem.add(_media(item));
    broadcast();
  }

  void broadcast() {
    final playing =
        player.playing &&
        player.processingState != ja.ProcessingState.completed;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (player.processingState) {
          ja.ProcessingState.idle => AudioProcessingState.idle,
          ja.ProcessingState.loading => AudioProcessingState.loading,
          ja.ProcessingState.buffering => AudioProcessingState.buffering,
          ja.ProcessingState.ready => AudioProcessingState.ready,
          ja.ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: _index < 0 ? null : _index,
      ),
    );
  }

  @override
  Future<void> play() async {
    await onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await onPause?.call();
  }

  @override
  Future<void> stop() async {
    await onStop?.call();
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await onSeek?.call(position);
  }

  @override
  Future<void> skipToNext() async {
    await onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onPrevious?.call();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await onQueueItem?.call(index);
  }
}
