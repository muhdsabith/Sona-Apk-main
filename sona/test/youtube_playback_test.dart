import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sona/services/youtube_playback.dart';

void main() {
  test('single-use audio URL is handed to the player exactly once', () async {
    var requests = 0;
    var stops = 0;
    final duration = await loadYoutubeAudio(
      resolve: () async => 'https://example.com/single-use-audio',
      load: (url) async {
        expect(url, 'https://example.com/single-use-audio');
        requests++;
        if (requests > 1) throw StateError('Link already consumed');
        return const Duration(minutes: 3);
      },
      stop: () async => stops++,
    );
    expect(duration, const Duration(minutes: 3));
    expect(requests, 1);
    expect(stops, 0);
  });

  test('rejected audio stops the native player before fallback', () async {
    var stopped = false;
    await expectLater(
      loadYoutubeAudio(
        resolve: () async => 'https://example.com/rejected',
        load: (_) async => throw StateError('HTTP 403'),
        stop: () async => stopped = true,
      ),
      throwsStateError,
    );
    expect(stopped, isTrue);
  });

  test('timed-out resolution cannot load audio over the fallback', () async {
    final pending = Completer<String>();
    var loads = 0;
    var stops = 0;
    await expectLater(
      loadYoutubeAudio(
        resolve: () => pending.future,
        load: (_) async {
          loads++;
          return Duration.zero;
        },
        stop: () async => stops++,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    pending.complete('https://example.com/late-audio');
    await Future<void>.delayed(Duration.zero);
    expect(loads, 0);
    expect(stops, 1);
  });

  test('stalled player load stops before returning the timeout', () async {
    final pending = Completer<Duration?>();
    var stopped = false;
    await expectLater(
      loadYoutubeAudio(
        resolve: () async => 'https://example.com/stalled',
        load: (_) => pending.future,
        stop: () async => stopped = true,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(stopped, isTrue);
    pending.complete(Duration.zero);
  });
}
