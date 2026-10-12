import 'package:flutter_test/flutter_test.dart';
import 'package:sona/services/spotify_import.dart';

void main() {
  test('parses Spotify playlist share links', () {
    const id = '0YoARAGd8qpclYOMPVyGov';
    expect(
      SpotifyImportService.playlistIdFrom(
        'https://open.spotify.com/playlist/$id?si=test&utm_source=copy-link',
      ),
      id,
    );
    expect(
      SpotifyImportService.playlistIdFrom('spotify:playlist:$id'),
      id,
    );
    expect(SpotifyImportService.playlistIdFrom(id), id);
  });

  test('finds a Spotify playlist link inside shared text', () {
    const id = '0YoARAGd8qpclYOMPVyGov';
    final ref = SpotifyImportService.findPlaylistReference(
      'Listen to this https://open.spotify.com/playlist/$id?si=abc',
    );
    expect(ref, isNotNull);
    expect(SpotifyImportService.playlistIdFrom(ref!), id);
  });

  test('parses Spotify embed next data into Raaga tracks', () {
    const playlistId = '0YoARAGd8qpclYOMPVyGov';
    const track1 = '4iV5W9uYEdYUVa79Axb7Rh';
    const track2 = '1301WleyT98MSxVHPZCA6M';
    const html = '''
<html><body>
<script id="__NEXT_DATA__" type="application/json">
{"props":{"pageProps":{"state":{"data":{"entity":{"type":"playlist","name":"Night Mix","subtitle":"Dev","trackList":[{"uri":"spotify:track:$track1","title":"First Song","subtitle":"First Artist","audioPreview":{"url":"https://p.scdn.co/mp3-preview/first"}},{"uri":"spotify:track:$track2","title":"Second Song","subtitle":"Second Artist","audioPreview":null}]}}}}}}
</script>
</body></html>
''';
    final result = SpotifyImportService.parseEmbedHtml(html, playlistId);
    expect(result.name, 'Night Mix');
    expect(result.owner, 'Dev');
    expect(result.items, hasLength(2));
    expect(result.items.first.title, 'First Song');
    expect(result.items.first.creator, 'First Artist');
    expect(result.items.first.isSpotify, isTrue);
    expect(
      result.items.first.previewUrl,
      'https://p.scdn.co/mp3-preview/first',
    );
    expect(result.items.last.previewUrl, isNull);
  });
}
