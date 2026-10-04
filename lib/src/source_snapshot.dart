import 'dart:convert';
import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';

/// The fetched source files, read-only: what the engine analyzes.
abstract interface class SourceSnapshot {
  /// Where the code came from.
  SourceDescriptor get descriptor;

  /// Paths relative to the source root, with `/` separators, sorted.
  List<String> get paths;

  /// Content of the file at [path] (one of [paths]) as UTF-8 text;
  /// malformed bytes are replaced.
  Future<String> readAsString(String path);

  /// Releases the snapshot (deletes its temporary folder, if any).
  Future<void> dispose();
}

/// A snapshot whose files are held in memory (web, tests).
class MemorySnapshot implements SourceSnapshot {
  /// Creates a snapshot of [files] (path → bytes).
  new({required this.descriptor, required Map<String, Uint8List> files})
    : _files = Map.of(files),
      paths = List.unmodifiable(files.keys.toList()..sort());

  final Map<String, Uint8List> _files;

  @override
  final SourceDescriptor descriptor;

  @override
  final List<String> paths;

  @override
  Future<String> readAsString(String path) async {
    final bytes = _files[path];
    if (bytes == null) {
      throw ArgumentError.value(path, 'path', 'not in the snapshot');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> dispose() async => _files.clear();
}
