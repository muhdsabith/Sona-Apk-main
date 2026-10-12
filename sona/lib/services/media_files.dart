import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/media_item.dart';
import 'apis.dart';

class MediaFiles {
  MediaFiles({Directory? root, http.Client Function()? clientFactory})
    : _root = root,
      _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  Directory? _root;
  final Map<String, http.Client> _downloads = {};
  Future<Directory> get root async {
    _root ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/sona_audio',
    );
    await _root!.create(recursive: true);
    return _root!;
  }

  Future<String> path(String name) async {
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      throw const CatalogException('Invalid saved audio filename.');
    }
    return '${(await root).path}/$name';
  }

  Future<List<MediaItem>> pickMusic() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      allowMultiple: true,
    );
    if (selection == null) return [];
    final result = <MediaItem>[];
    final created = <File>[];
    try {
      for (final picked in selection.files) {
        if (picked.path == null)
          throw const CatalogException(
            'This file could not be read. Download it to your phone first.',
          );
        final file = File(picked.path!);
        if (await file.length() > 500 * 1024 * 1024)
          throw const CatalogException(
            'Choose audio files smaller than 500 MB.',
          );
        final hash = (await sha256.bind(file.openRead()).first).toString();
        final ext = picked.name.split('.').last.toLowerCase();
        if (!['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'].contains(ext))
          continue;
        final name = '$hash.$ext';
        final destination = File(await path(name));
        if (!await destination.exists()) {
          final temp = File('${destination.path}.part');
          try {
            await file.copy(temp.path);
            await temp.rename(destination.path);
            created.add(destination);
          } catch (_) {
            if (await temp.exists()) await temp.delete();
            rethrow;
          }
        }
        final title = picked.name
            .replaceFirst(RegExp(r'\.[^.]+$'), '')
            .replaceAll('_', ' ');
        result.add(
          MediaItem(
            id: 'local-$hash',
            title: title,
            creator: 'On your device',
            category: 'Your music',
            kind: MediaKind.music,
            source: 'local:$name',
            color: 0xFFD4BFA5,
            art: result.length % 5,
            description: 'Imported audio. Available offline in Raaga.',
          ),
        );
      }
      return result;
    } catch (_) {
      for (final f in created) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> cleanPartialFiles() async {
    await for (final entity in (await root).list()) {
      if (entity is File && entity.path.endsWith('.part'))
        await entity.delete();
    }
  }

  Future<String> download(
    MediaItem item,
    void Function(double?) progress,
  ) async {
    if (_downloads.containsKey(item.id))
      throw const CatalogException('This episode is already downloading.');
    final client = _clientFactory();
    _downloads[item.id] = client;
    File? temp;
    IOSink? sink;
    try {
      final uri = httpsAddress(item.source);
      final suffix = uri.path.split('.').last.toLowerCase();
      final ext = ['mp3', 'm4a', 'aac', 'ogg', 'wav', 'flac'].contains(suffix)
          ? suffix
          : 'mp3';
      final name =
          'download-${item.id.replaceAll(RegExp('[^a-zA-Z0-9-]'), '')}.$ext';
      final target = File(await path(name));
      if (!identical(_downloads[item.id], client)) {
        throw const CatalogException('Download cancelled.');
      }
      temp = File('${target.path}.part');
      final response = await openAudioRequest(client, uri);
      final type = response.headers['content-type'] ?? '';
      if (type.contains('text/html') || type.contains('application/json')) {
        throw const CatalogException(
          'The publisher returned a webpage instead of audio.',
        );
      }
      final total = response.contentLength;
      if (total != null && total > 500 * 1024 * 1024)
        throw const CatalogException(
          'This episode is larger than the 500 MB download limit.',
        );
      sink = temp.openWrite();
      var received = 0;
      var flushed = 0;
      final updates = Stopwatch()..start();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (!_downloads.containsKey(item.id))
          throw const CatalogException('Download cancelled.');
        received += chunk.length;
        if (received > 500 * 1024 * 1024)
          throw const CatalogException(
            'This episode is too large to download.',
          );
        sink.add(chunk);
        if (received - flushed >= 1024 * 1024) {
          await sink.flush();
          flushed = received;
        }
        if (updates.elapsedMilliseconds >= 250) {
          progress(total == null || total == 0 ? null : received / total);
          updates.reset();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0 || (total != null && total != received))
        throw const CatalogException(
          'The download was incomplete. Please retry.',
        );
      if (!_downloads.containsKey(item.id))
        throw const CatalogException('Download cancelled.');
      await temp.rename(target.path);
      return name;
    } finally {
      try {
        await sink?.close();
      } finally {
        try {
          if (temp != null && await temp.exists()) await temp.delete();
        } finally {
          client.close();
          if (identical(_downloads[item.id], client)) {
            _downloads.remove(item.id);
          }
        }
      }
    }
  }

  void cancel(String id) {
    _downloads.remove(id)?.close();
  }

  Future<void> remove(String name) async {
    final f = File(await path(name));
    if (await f.exists()) await f.delete();
  }

  void dispose() {
    for (final c in _downloads.values) {
      c.close();
    }
    _downloads.clear();
  }
}
