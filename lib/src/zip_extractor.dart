import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:code_source_client/src/fetch_event.dart';
import 'package:code_source_client/src/file_filter.dart';
import 'package:code_source_client/src/temp_storage.dart';

/// Extracts the kept files of a zip into a snapshot builder.
///
/// Refuses unsafe entries (absolute paths, `..`), strips a single top folder
/// shared by every entry (`AltMe-main/…`), and enforces [maxExtractedBytes]
/// on the kept files. Returns the stripped top folder name, or null.
Future<String?> extractZip(
  Uint8List bytes,
  SnapshotBuilder builder, {
  required int maxExtractedBytes,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  // The decoder does not throw on data that is not a zip: it returns an
  // empty archive. Check the signature, then emptiness below.
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    throw const InvalidArchive('not a zip file');
  }
  final archive = ZipDecoder().decodeBytes(bytes);

  final entries = <(String, ArchiveFile)>[];
  for (final file in archive.files) {
    final path = _safePath(file.name);
    if (path.isEmpty) continue;
    entries.add((path, file));
  }
  if (entries.isEmpty) throw const InvalidArchive('the archive is empty');
  final top = _sharedTopFolder(entries.map((e) => e.$1));

  var extracted = 0;
  var done = 0;
  for (final (path, file) in entries) {
    if (isCancelled?.call() ?? false) return top;
    done++;
    // The top folder's own entry has nothing left once stripped.
    if (path == top) continue;
    final relative = top == null ? path : path.substring(top.length + 1);
    if (file.isFile && !file.isSymbolicLink && FileFilter.keeps(relative)) {
      // Entries are decompressed lazily: a corrupt one fails here.
      final Uint8List content;
      try {
        content = file.content;
      } on FormatException catch (e) {
        throw InvalidArchive('corrupt entry "$path" (${e.message})');
      }
      extracted += content.length;
      if (extracted > maxExtractedBytes) {
        throw ArchiveTooLarge(maxExtractedBytes);
      }
      await builder.addFile(relative, content);
    }
    onProgress?.call(done, entries.length);
  }
  return top;
}

/// The entry name with `/` separators and no leading `./` or trailing `/`.
/// Throws [InvalidArchive] for absolute paths and `..` segments.
String _safePath(String name) {
  final normalized = name.replaceAll(r'\', '/');
  if (normalized.startsWith('/') || RegExp('^[A-Za-z]:').hasMatch(normalized)) {
    throw InvalidArchive('absolute path "$name"');
  }
  final segments = normalized
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  if (segments.contains('..')) {
    throw InvalidArchive('path leaving the archive "$name"');
  }
  return segments.join('/');
}

/// Folders of a Dart package's own layout: a zip whose only top folder is one
/// of them holds a package's content, not a wrapping folder.
const _packageLayoutFolders = {
  'lib',
  'bin',
  'test',
  'tool',
  'example',
  'web',
  'integration_test',
  'test_driver',
  'packages',
  'apps',
};

/// The single first segment shared by every path, when every path is below
/// it and it is not a package layout folder; otherwise null.
String? _sharedTopFolder(Iterable<String> paths) {
  String? top;
  var below = false;
  for (final path in paths) {
    final slash = path.indexOf('/');
    final first = slash == -1 ? path : path.substring(0, slash);
    if (top != null && first != top) return null;
    top = first;
    if (slash != -1) below = true;
  }
  // A lone file or only the folder entry itself: nothing to strip.
  if (!below || _packageLayoutFolders.contains(top)) return null;
  final prefix = '$top/';
  return paths.every((p) => p == top || p.startsWith(prefix)) ? top : null;
}
