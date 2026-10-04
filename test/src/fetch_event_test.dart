import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/code_source_client.dart';
import 'package:test/test.dart';

void main() {
  group(FetchFailure, () {
    test('every failure has a user message', () {
      final failures = <FetchFailure, String>{
        const SourceNotFound('/x'): 'Folder not found: /x',
        const InvalidGitUrl('foo'): 'Not a GitHub or GitLab repository URL',
        const RepositoryNotFound('https://github.com/o/r'):
            'Private repositories come in a later version',
        const RateLimited(): 'Try again later.',
        RateLimited(resetAt: DateTime.utc(2026)): 'Try again after',
        const NetworkFailure('boom'): 'Download failed: boom',
        const ArchiveTooLarge(500 * 1024 * 1024): '500 MB limit',
        const InvalidArchive('bad'): 'Invalid archive: bad',
        const UnsupportedOnWeb('git repository'):
            'A git repository cannot be read in a browser',
      };
      for (final MapEntry(key: failure, value: expected) in failures.entries) {
        expect(failure.message, contains(expected));
        expect(failure.toString(), 'FetchFailure: ${failure.message}');
      }
    });

    test('supports value equality', () {
      expect(const InvalidArchive('a'), const InvalidArchive('a'));
      expect(const SourceNotFound('a'), isNot(const SourceNotFound('b')));
    });
  });

  group(FetchEvent, () {
    test('supports value equality', () {
      expect(
        const FetchProgress(FetchPhase.downloading, done: 1, total: 2),
        const FetchProgress(FetchPhase.downloading, done: 1, total: 2),
      );
      // Built at runtime: identical constants would skip the props
      // comparison.
      final reason = ['a'].single;
      expect(
        FetchFailed(InvalidArchive(reason)),
        FetchFailed(InvalidArchive(reason)),
      );
    });
  });

  group(CodeSource, () {
    test('supports value equality', () {
      expect(const LocalFolderSource('/a'), const LocalFolderSource('/a'));
      expect(const LocalFolderSource('/a').props, ['/a']);
      expect(
        const GitRepositorySource('u', ref: 'r'),
        const GitRepositorySource('u', ref: 'r'),
      );
      expect(const GitRepositorySource('u', ref: 'r').props, ['u', 'r']);
      final bytes = Uint8List(1);
      expect(ZipBytesSource(fileName: 'a.zip', bytes: bytes).props, [
        'a.zip',
        bytes,
      ]);
    });
  });

  group(FetchDone, () {
    test('compares by snapshot', () {
      final snapshot = MemorySnapshot(
        descriptor: const ZipDescriptor(fileName: 'a.zip'),
        files: const {},
      );

      expect(FetchDone(snapshot), FetchDone(snapshot));
      expect(FetchDone(snapshot).props, [snapshot]);
    });
  });
}
