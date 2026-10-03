import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/src/fetch_event.dart';
import 'package:code_source_client/src/file_filter.dart';
import 'package:code_source_client/src/source_snapshot.dart';
import 'package:code_source_client/src/temp_storage.dart';
import 'package:path/path.dart' as p;

/// Native platforms extract archives into a temporary directory.
TempStorage defaultTempStorage() => DirectoryTempStorage();

/// Native platforms read local folders in place.
LocalFolderReader? defaultLocalFolderReader() => const IoLocalFolderReader();

/// Native platforms can download repository archives.
const bool gitSupportedByDefault = true;

/// Stores each snapshot in a new temporary directory, deleted on dispose.
class DirectoryTempStorage implements TempStorage {
  /// Creates the storage; [parent] defaults to the system temp directory.
  new({this.parent});

  /// Directory the temporary directories are created in; defaults to the
  /// system temp directory.
  final Directory? parent;

  @override
  Future<SnapshotBuilder> create() async {
    final base = parent ?? Directory.systemTemp;
    return _DirectorySnapshotBuilder(await base.createTemp('dc3d_'));
  }
}

class _DirectorySnapshotBuilder implements SnapshotBuilder {
  new(this._root);

  final Directory _root;
  final _paths = <String>[];

  @override
  Future<void> addFile(String path, Uint8List bytes) async {
    final file = File(p.joinAll([_root.path, ...path.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    _paths.add(path);
  }

  @override
  Future<SourceSnapshot> build(SourceDescriptor descriptor) async =>
      DirectorySnapshot(
        root: _root,
        descriptor: descriptor,
        paths: _paths,
        deleteOnDispose: true,
      );

  @override
  Future<void> discard() async {
    if (_root.existsSync()) await _root.delete(recursive: true);
  }
}

/// A snapshot whose files are in a directory.
class DirectorySnapshot implements SourceSnapshot {
  /// Creates a snapshot of [paths] below [root]; [deleteOnDispose] deletes
  /// [root] on [dispose] (temporary folders, never the user's own folder).
  new({
    required this.root,
    required this.descriptor,
    required List<String> paths,
    required this.deleteOnDispose,
  }) : paths = List.unmodifiable(paths.toList()..sort());

  /// Directory holding the files.
  final Directory root;

  /// Whether [dispose] deletes [root].
  final bool deleteOnDispose;

  @override
  final SourceDescriptor descriptor;

  @override
  final List<String> paths;

  @override
  Future<String> readAsString(String path) async {
    if (!paths.contains(path)) {
      throw ArgumentError.value(path, 'path', 'not in the snapshot');
    }
    final bytes = await File(p.joinAll([root.path, ...path.split('/')]))
        .readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> dispose() async {
    if (deleteOnDispose && root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}

/// Lists a local folder's kept files, without copying them.
class IoLocalFolderReader implements LocalFolderReader {
  /// Creates the reader.
  const new();

  @override
  Future<SourceSnapshot> open(String path) async {
    final root = Directory(path);
    if (!root.existsSync()) throw SourceNotFound(path);
    final paths = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      // Links are skipped: they may point outside the folder.
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .split(p.separator)
          .join('/');
      if (FileFilter.keeps(relative)) paths.add(relative);
    }
    return DirectorySnapshot(
      root: root,
      descriptor: LocalFolderDescriptor(name: p.basename(p.normalize(path))),
      paths: paths,
      deleteOnDispose: false,
    );
  }
}
