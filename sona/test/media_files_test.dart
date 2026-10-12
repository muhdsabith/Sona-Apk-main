import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sona/models/media_item.dart';
import 'package:sona/services/apis.dart';
import 'package:sona/services/media_files.dart';

const episode = MediaItem(
  id: 'test-episode',
  title: 'Episode',
  creator: 'Test',
  category: 'Podcasts',
  kind: MediaKind.podcast,
  source: 'https://example.com/audio.mp3',
  feedUrl: 'https://example.com/feed.xml',
  color: 0xFFC9F27A,
  art: 0,
  description: '',
);

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sona-download-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'Immediate cancellation stops before the first network request',
    () async {
      var requests = 0;
      final files = MediaFiles(
        root: directory,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final operation = files.download(episode, (_) {});
      files.cancel(episode.id);
      await expectLater(operation, throwsA(isA<CatalogException>()));
      expect(requests, 0);
      expect(await directory.list().toList(), isEmpty);
      files.dispose();
    },
  );

  test(
    'Successful download commits bytes without leaving partial files',
    () async {
      final files = MediaFiles(
        root: directory,
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'audio/mpeg'},
          ),
        ),
      );
      final name = await files.download(episode, (_) {});
      expect(await File(await files.path(name)).readAsBytes(), [1, 2, 3, 4]);
      expect(await directory.list().length, 1);
      files.dispose();
    },
  );

  test('Rejected audio response releases the job for a retry', () async {
    var attempts = 0;
    final files = MediaFiles(
      root: directory,
      clientFactory: () => MockClient((_) async {
        attempts++;
        return attempts == 1
            ? http.Response(
                '<html>Sign in</html>',
                200,
                headers: {'content-type': 'text/html'},
              )
            : http.Response.bytes([1, 2, 3], 200);
      }),
    );
    await expectLater(
      files.download(episode, (_) {}),
      throwsA(isA<CatalogException>()),
    );
    expect(await directory.list().toList(), isEmpty);
    final name = await files.download(episode, (_) {});
    expect(await File(await files.path(name)).length(), 3);
    files.dispose();
  });
}
