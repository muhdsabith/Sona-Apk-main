import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sona/services/archive_api.dart';

void main() {
  test('parse keeps only Creative Commons, public-domain and LibriVox items', () {
    final body = jsonEncode({
      'response': {
        'numFound': 3,
        'docs': [
          {
            'identifier': 'cc-song',
            'title': 'CC song',
            'creator': ['Artist'],
            'licenseurl': 'http://creativecommons.org/licenses/by-sa/4.0/',
          },
          {
            'identifier': 'book',
            'title': 'A book',
            'collection': ['librivox', 'audio_bookspoetry'],
          },
          {
            'identifier': 'unlicensed',
            'title': 'Unknown rights',
            'licenseurl': 'http://example.com/terms',
          },
        ],
      },
    });
    final page = ArchiveApi.parse(body);
    expect(page.items.map((m) => m.source), ['archive:cc-song', 'archive:book']);
    expect(page.items.first.category, 'CC BY-SA 4.0');
    expect(page.items.first.creator, 'Artist');
    expect(page.items.last.category, 'Public domain');
    expect(page.hasMore, isFalse);
  });

  test('licenseLabel handles CC0 and rejects other licenses', () {
    expect(
      ArchiveApi.licenseLabel('https://creativecommons.org/publicdomain/zero/1.0/'),
      'CC0',
    );
    expect(ArchiveApi.licenseLabel('http://example.com/terms'), isNull);
  });

  test('pickMp3 returns an encoded direct download URL', () {
    final body = jsonEncode({
      'files': [
        {'name': 'cover.jpg'},
        {'name': 'disc 1/track 01.mp3'},
      ],
    });
    expect(
      ArchiveApi.pickMp3('my-item', body),
      'https://archive.org/download/my-item/disc%201/track%2001.mp3',
    );
    expect(
      () => ArchiveApi.pickMp3('x', jsonEncode({'files': []})),
      throwsA(isA<ArchiveException>()),
    );
  });
}
