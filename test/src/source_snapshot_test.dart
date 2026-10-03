import 'dart:convert';
import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/code_source_client.dart';
import 'package:test/test.dart';

void main() {
  group(MemorySnapshot, () {
    late MemorySnapshot snapshot;

    setUp(() {
      snapshot = MemorySnapshot(
        descriptor: const ZipDescriptor(fileName: 'a.zip'),
        files: {
          'lib/b.dart': Uint8List.fromList(utf8.encode('class B {}')),
          'lib/a.dart': Uint8List.fromList([0x63, 0xFF, 0x64]),
        },
      );
    });

    test('lists its paths sorted', () {
      expect(snapshot.paths, ['lib/a.dart', 'lib/b.dart']);
    });

    test('reads files as UTF-8, replacing malformed bytes', () async {
      expect(await snapshot.readAsString('lib/b.dart'), 'class B {}');
      expect(await snapshot.readAsString('lib/a.dart'), 'c�d');
    });

    test('throws $ArgumentError for a path outside the snapshot', () {
      expect(() => snapshot.readAsString('nope.dart'), throwsArgumentError);
    });

    test('forgets its files when disposed', () async {
      await snapshot.dispose();

      expect(() => snapshot.readAsString('lib/b.dart'), throwsArgumentError);
    });
  });
}
