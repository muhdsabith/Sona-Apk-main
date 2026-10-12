import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sona/services/apis.dart';
import 'package:sona/services/library_store.dart';
import 'package:sona/models/media_item.dart';

const feed =
    '''<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<title>Science &amp; Stories</title><itunes:author>Author</itunes:author>
<itunes:image href="https://example.com/cover.jpg"/>
<item><title>One</title><guid>stable-one</guid><itunes:duration>1:02:03</itunes:duration>
<description><![CDATA[<p>Hello <b>world</b></p>]]></description>
<enclosure url="https://example.com/one.mp3" type="audio/mpeg"/></item>
<item><title>Duplicate</title><guid>stable-one</guid><enclosure url="https://example.com/one.mp3" type="audio/mpeg"/></item>
<item><title>Two</title><enclosure url="https://example.com/two.m4a" type="audio/mp4"/></item>
<item><title>Unsafe</title><enclosure url="http://example.com/three.mp3" type="audio/mpeg"/></item>
<item><title>Video</title><enclosure url="https://example.com/four.mp4" type="video/mp4"/></item>
</channel></rss>''';

void main() {
  test(
    'Podcast RSS yields unique playable episodes and durable identities',
    () {
      final result = PodcastApi.parseFeed(feed, 'https://example.com/feed.xml');
      expect(result.feed.title, 'Science & Stories');
      expect(result.episodes.length, 2);
      expect(result.episodes.first.durationMs, 3723000);
      expect(result.episodes.first.description, 'Hello world');
      expect(result.episodes.first.artworkUrl, 'https://example.com/cover.jpg');
      final changed = feed
          .replaceAll('One</title>', 'Renamed</title>')
          .replaceAll('one.mp3', 'new.mp3');
      expect(
        PodcastApi.parseFeed(
          changed,
          'https://example.com/feed.xml',
        ).episodes.first.id,
        result.episodes.first.id,
      );
      expect(
        PodcastApi.parseFeed(
          feed,
          'https://other.com/feed.xml',
        ).episodes.first.id,
        isNot(result.episodes.first.id),
      );
    },
  );
  test('Non-podcast and empty feeds fail explicitly', () {
    expect(
      () => PodcastApi.parseFeed('<html/>', 'https://example.com'),
      throwsA(isA<CatalogException>()),
    );
    expect(
      () =>
          PodcastApi.parseFeed('<rss><channel/></rss>', 'https://example.com'),
      throwsA(isA<CatalogException>()),
    );
  });
  test(
    'Old libraries migrate with favourites, playlist membership and progress intact',
    () {
      final old = LibrarySnapshot.fromJson({
        'likes': ['m1'],
        'playlists': [
          {
            'id': 'a',
            'name': 'Mix',
            'itemIds': ['m1'],
          },
        ],
        'progress': {'p1': 2500},
      });
      expect(old.likes, {'m1'});
      expect(old.playlists.single.itemIds, ['m1']);
      expect(old.progress['p1'], 2500);
      expect(old.items, isEmpty);
      expect(old.feeds, isEmpty);
      expect(old.downloads, isEmpty);
    },
  );
  test(
    'Library round trip preserves imported sources and offline episode references',
    () {
      final parsed = PodcastApi.parseFeed(feed, 'https://example.com/feed.xml');
      final snapshot = LibrarySnapshot(
        items: parsed.episodes,
        feeds: [parsed.feed],
        downloads: {parsed.episodes.first.id: 'saved.mp3'},
        history: [parsed.episodes.first.id],
        playlists: [
          UserPlaylist(
            id: 'x',
            name: 'My mix',
            itemIds: [parsed.episodes.first.id],
          ),
        ],
      );
      final copy = LibrarySnapshot.fromJson(snapshot.toJson());
      expect(copy.items.first.toJson(), snapshot.items.first.toJson());
      expect(copy.downloads, snapshot.downloads);
      expect(copy.history, snapshot.history);
      expect(copy.feeds.single.title, parsed.feed.title);
    },
  );
  test('HTTP redirect downgrade is rejected before a second request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'http://example.com/audio'},
      );
    });
    await expectLater(
      openAudioRequest(client, Uri.parse('https://example.com/start')),
      throwsA(isA<CatalogException>()),
    );
    expect(calls, 1);
    client.close();
  });
  test('Podcast search filters entries without secure feeds', () async {
    final api = PodcastApi(
      client: MockClient((r) async {
        expect(r.url.queryParameters['term'], 'Malayalam');
        return http.Response(
          '{"results":[{"feedUrl":"https://example.com/feed","collectionName":"Talk"},{"feedUrl":"http://example.com/feed","collectionName":"Old"}]}',
          200,
        );
      }),
    );
    expect((await api.search('Malayalam')).single.title, 'Talk');
    api.dispose();
  });
}
