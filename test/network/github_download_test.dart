// Real downloads, skipped by default (see dart_test.yaml). They check the
// client against GitHub and print the numbers recorded in the session log.
@Tags(['network', 'skip_very_good_optimization'])
library;

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/code_source_client.dart';
import 'package:test/test.dart';

Future<void> _fetchAndReport(GitRepositorySource source, int minFiles) async {
  final watch = Stopwatch()..start();
  var downloaded = 0;
  late SourceSnapshot snapshot;
  await for (final event in CodeSourceClient().fetch(source)) {
    switch (event) {
      case FetchProgress(phase: FetchPhase.downloading, :final done):
        downloaded = done;
      case FetchProgress():
        break;
      case FetchDone(snapshot: final done):
        snapshot = done;
      case FetchFailed(:final failure):
        fail('$failure');
    }
  }
  final dartFiles = snapshot.paths.where((p) => p.endsWith('.dart')).length;
  // Recorded in the session log.
  // ignore: avoid_print
  print(
    '${source.url}@${source.ref ?? 'default'}: ${watch.elapsedMilliseconds} '
    'ms, ${(downloaded / 1e6).toStringAsFixed(1)} MB downloaded, '
    '${snapshot.paths.length} files kept ($dartFiles Dart), commit '
    '${(snapshot.descriptor as GitDescriptor).commit}',
  );
  expect(dartFiles, greaterThan(minFiles));
  await snapshot.dispose();
}

void main() {
  group('GitHub download', () {
    test('fetches flutter_scene at flutter_scene-0.23.0', () async {
      await _fetchAndReport(
        const GitRepositorySource(
          'https://github.com/bdero/flutter_scene',
          ref: 'flutter_scene-0.23.0',
        ),
        500,
      );
    });

    test('fetches AltMe at its default branch', () async {
      await _fetchAndReport(
        const GitRepositorySource('https://github.com/TalaoDAO/AltMe'),
        1000,
      );
    });
  });
}
