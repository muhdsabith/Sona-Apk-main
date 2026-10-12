import 'dart:async';

Future<Duration?> loadYoutubeAudio({
  required Future<String> Function() resolve,
  required Future<Duration?> Function(String) load,
  required Future<void> Function() stop,
  Duration timeout = const Duration(seconds: 25),
}) async {
  var active = true;
  try {
    return await (() async {
      final url = await resolve();
      if (!active) throw TimeoutException('YouTube audio request expired.');
      return await load(url);
    })().timeout(timeout);
  } catch (_) {
    active = false;
    await stop();
    rethrow;
  } finally {
    active = false;
  }
}
