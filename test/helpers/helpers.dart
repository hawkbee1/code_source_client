import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/code_source_client.dart';

/// A zip holding [files] (path → text); paths ending with `/` are folders.
Uint8List zipOf(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.add(
      key.endsWith('/')
          ? ArchiveFile.directory(key)
          : ArchiveFile.bytes(key, utf8.encode(value)),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A zip like GitHub's zipball of `o/r` at commit `abc1234`.
Uint8List githubZip() => zipOf({
  'o-r-abc1234/': '',
  'o-r-abc1234/pubspec.yaml': 'name: r',
  'o-r-abc1234/lib/main.dart': 'void main() {}',
  'o-r-abc1234/lib/src/a.dart': 'class A {}',
  'o-r-abc1234/README.md': '# r',
  'o-r-abc1234/.dart_tool/x.dart': 'class Hidden {}',
  'o-r-abc1234/build/y.dart': 'class Built {}',
});

/// Memory storage that records what happened to its builders.
class RecordingTempStorage implements TempStorage {
  /// Builders created so far.
  final builders = <RecordingBuilder>[];

  @override
  Future<SnapshotBuilder> create() async {
    final builder = RecordingBuilder();
    builders.add(builder);
    return builder;
  }
}

/// A memory snapshot builder that records whether it was discarded.
class RecordingBuilder implements SnapshotBuilder {
  final _inner = const MemoryTempStorage();
  late final Future<SnapshotBuilder> _builder = _inner.create();

  /// Whether [discard] was called.
  bool discarded = false;

  @override
  Future<void> addFile(String path, Uint8List bytes) async =>
      await (await _builder).addFile(path, bytes);

  @override
  Future<SourceSnapshot> build(SourceDescriptor descriptor) async =>
      await (await _builder).build(descriptor);

  @override
  Future<void> discard() async {
    discarded = true;
    await (await _builder).discard();
  }
}
