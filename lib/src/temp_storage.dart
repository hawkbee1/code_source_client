import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/src/source_snapshot.dart';

/// Where fetched files are stored while they are analyzed.
abstract interface class TempStorage {
  /// Starts a new, empty snapshot.
  Future<SnapshotBuilder> create();
}

/// Collects the files of a snapshot being fetched.
abstract interface class SnapshotBuilder {
  /// Adds the file at [path] (relative, `/` separators).
  Future<void> addFile(String path, Uint8List bytes);

  /// Finishes the snapshot.
  Future<SourceSnapshot> build(SourceDescriptor descriptor);

  /// Throws away everything added (the fetch failed or was cancelled).
  Future<void> discard();
}

/// Keeps snapshots in memory: the web, and tests.
class MemoryTempStorage implements TempStorage {
  /// Creates the storage.
  const new();

  @override
  Future<SnapshotBuilder> create() async => _MemorySnapshotBuilder();
}

class _MemorySnapshotBuilder implements SnapshotBuilder {
  final _files = <String, Uint8List>{};

  @override
  Future<void> addFile(String path, Uint8List bytes) async =>
      _files[path] = bytes;

  @override
  Future<SourceSnapshot> build(SourceDescriptor descriptor) async =>
      MemorySnapshot(descriptor: descriptor, files: _files);

  @override
  Future<void> discard() async => _files.clear();
}

/// Opens a local folder as a snapshot (native platforms).
abstract interface class LocalFolderReader {
  /// Lists the kept files of the folder at [path], read in place.
  ///
  /// Throws `SourceNotFound` when the folder does not exist.
  Future<SourceSnapshot> open(String path);
}
