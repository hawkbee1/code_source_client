import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/code_source_client.dart';
import 'package:code_source_client/src/platform/platform_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../helpers/helpers.dart';

/// The snapshot of a fetch that must succeed, with every event before it.
Future<(SourceSnapshot, List<FetchEvent>)> _done(Stream<FetchEvent> s) async {
  final events = await s.toList();
  final done = events.last;
  if (done is! FetchDone) fail('expected FetchDone, got $done');
  return (done.snapshot, events);
}

/// The failure of a fetch that must fail.
Future<FetchFailure> _failure(Stream<FetchEvent> s) async {
  final last = (await s.toList()).last;
  if (last is! FetchFailed) fail('expected FetchFailed, got $last');
  return last.failure;
}

void main() {
  group(CodeSourceClient, () {
    late RecordingTempStorage storage;

    setUp(() => storage = RecordingTempStorage());

    CodeSourceClient client({
      http.Client? httpClient,
      bool gitSupported = true,
      LocalFolderReader? reader,
      bool localFoldersSupported = true,
      int maxArchiveBytes = CodeSourceClient.defaultMaxArchiveBytes,
      int maxExtractedBytes = CodeSourceClient.defaultMaxExtractedBytes,
    }) => CodeSourceClient(
      httpClient: httpClient ?? MockClient((_) async => http.Response('', 500)),
      tempStorage: storage,
      localFolderReader: reader,
      localFoldersSupported: localFoldersSupported,
      gitSupported: gitSupported,
      maxArchiveBytes: maxArchiveBytes,
      maxExtractedBytes: maxExtractedBytes,
    );

    test('uses the platform defaults when nothing is injected', () async {
      final defaults = CodeSourceClient();
      final (snapshot, _) = await _done(
        defaults.fetch(ZipBytesSource(fileName: 'a.zip', bytes: githubZip())),
      );

      expect(snapshot, isA<DirectorySnapshot>());
      await snapshot.dispose();
    });

    group('zip', () {
      test(
        'keeps the Dart files, strips the top folder, reports progress',
        () async {
          final (snapshot, events) = await _done(
            client().fetch(
              ZipBytesSource(fileName: 'r.zip', bytes: githubZip()),
            ),
          );

          expect(snapshot.paths, [
            'lib/main.dart',
            'lib/src/a.dart',
            'pubspec.yaml',
          ]);
          expect(await snapshot.readAsString('lib/src/a.dart'), 'class A {}');
          expect(snapshot.descriptor, const ZipDescriptor(fileName: 'r.zip'));
          expect(
            events.whereType<FetchProgress>().last,
            const FetchProgress(FetchPhase.extracting, done: 7, total: 7),
          );
        },
      );

      test('keeps paths as they are without a single top folder', () async {
        final (snapshot, _) = await _done(
          client().fetch(
            ZipBytesSource(
              fileName: 'a.zip',
              bytes: zipOf({'a/x.dart': '', 'b/y.dart': '', './c.dart': ''}),
            ),
          ),
        );

        expect(snapshot.paths, ['a/x.dart', 'b/y.dart', 'c.dart']);
      });

      test('does not strip the folder of a single top-level file', () async {
        final (snapshot, _) = await _done(
          client().fetch(
            ZipBytesSource(fileName: 'a.zip', bytes: zipOf({'main.dart': ''})),
          ),
        );

        expect(snapshot.paths, ['main.dart']);
      });

      test('normalizes Windows separators', () async {
        final (snapshot, _) = await _done(
          client().fetch(
            ZipBytesSource(
              fileName: 'a.zip',
              bytes: zipOf({r'lib\a.dart': '', 'lib/b.dart': ''}),
            ),
          ),
        );

        expect(snapshot.paths, ['lib/a.dart', 'lib/b.dart']);
      });

      for (final unsafe in ['../evil.dart', '/etc/evil.dart', 'C:/evil.dart']) {
        test('refuses the unsafe entry "$unsafe"', () async {
          final failure = await _failure(
            client().fetch(
              ZipBytesSource(fileName: 'a.zip', bytes: zipOf({unsafe: ''})),
            ),
          );

          expect(failure, isA<InvalidArchive>());
          expect(storage.builders.single.discarded, isTrue);
        });
      }

      test('fails with $InvalidArchive for bytes that are not a zip', () async {
        for (final bytes in [
          Uint8List.fromList([1]),
          Uint8List.fromList(utf8.encode('PK not really a zip')),
          // A real zip cut in the middle reads as an empty archive.
          Uint8List.sublistView(githubZip(), 0, 300),
        ]) {
          final failure = await _failure(
            client().fetch(ZipBytesSource(fileName: 'a.zip', bytes: bytes)),
          );

          expect(failure, isA<InvalidArchive>());
        }
      });

      test('fails with $InvalidArchive for a corrupt entry', () async {
        final bytes = zipOf({'r/lib/a.dart': 'class A { int x = 1; } ' * 200});
        for (var i = 45; i < 70; i++) {
          bytes[i] ^= 0xFF;
        }

        final failure = await _failure(
          client().fetch(ZipBytesSource(fileName: 'a.zip', bytes: bytes)),
        );

        expect(
          (failure as InvalidArchive).reason,
          startsWith('corrupt entry "r/lib/a.dart"'),
        );
        expect(storage.builders.single.discarded, isTrue);
      });

      test('fails with $InvalidArchive for an empty archive', () async {
        final failure = await _failure(
          client().fetch(ZipBytesSource(fileName: 'a.zip', bytes: zipOf({}))),
        );

        expect(failure, const InvalidArchive('the archive is empty'));
      });

      test('keeps a lone package folder such as lib', () async {
        final (snapshot, _) = await _done(
          client().fetch(
            ZipBytesSource(
              fileName: 'a.zip',
              bytes: zipOf({'lib/': '', 'lib/main.dart': ''}),
            ),
          ),
        );

        expect(snapshot.paths, ['lib/main.dart']);
      });

      test('reports unexpected errors as stream errors', () async {
        final broken = CodeSourceClient(tempStorage: _BrokenStorage());

        await expectLater(
          broken.fetch(ZipBytesSource(fileName: 'a.zip', bytes: githubZip())),
          emitsError(isA<StateError>()),
        );
      });

      test('fails with $ArchiveTooLarge above the archive limit', () async {
        final failure = await _failure(
          client(maxArchiveBytes: 10)
              .fetch(ZipBytesSource(fileName: 'a.zip', bytes: githubZip())),
        );

        expect(failure, const ArchiveTooLarge(10));
      });

      test('fails with $ArchiveTooLarge above the extracted limit', () async {
        final failure = await _failure(
          client(maxExtractedBytes: 15)
              .fetch(ZipBytesSource(fileName: 'a.zip', bytes: githubZip())),
        );

        expect(failure, const ArchiveTooLarge(15));
        expect(storage.builders.single.discarded, isTrue);
      });

      test('discards the snapshot when cancelled during extraction', () async {
        final completer = Completer<void>();
        late StreamSubscription<FetchEvent> subscription;
        subscription = client()
            .fetch(ZipBytesSource(fileName: 'a.zip', bytes: githubZip()))
            .listen((event) async {
              if (event is FetchProgress) {
                await subscription.cancel();
                completer.complete();
              }
            });
        await completer.future;
        // Let the fetch notice the cancellation and clean up.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(storage.builders.single.discarded, isTrue);
      });
    });

    group('git', () {
      http.StreamedResponse zipResponse(
        Uint8List bytes, {
        bool withLength = true,
      }) => http.StreamedResponse(
        Stream.fromIterable([
          for (var i = 0; i < bytes.length; i += 1000)
            bytes.sublist(i, i + 1000 > bytes.length ? bytes.length : i + 1000),
        ]),
        200,
        contentLength: withLength ? bytes.length : null,
      );

      test('downloads a GitHub zipball and records the commit', () async {
        final requests = <http.BaseRequest>[];
        final mock = MockClient.streaming((request, _) async {
          requests.add(request);
          return zipResponse(githubZip());
        });

        final (snapshot, events) = await _done(
          client(httpClient: mock)
              .fetch(const GitRepositorySource('https://github.com/o/r')),
        );

        expect(
          requests.single.url.toString(),
          'https://api.github.com/repos/o/r/zipball',
        );
        expect(requests.single.headers['User-Agent'], 'dart_code_3d');
        expect(snapshot.paths, hasLength(3));
        expect(
          snapshot.descriptor,
          const GitDescriptor(url: 'https://github.com/o/r', commit: 'abc1234'),
        );
        expect(
          events.whereType<FetchProgress>().first,
          FetchProgress(FetchPhase.downloading, total: githubZip().length),
        );
      });

      test('uses the requested ref, or the one in the URL', () async {
        final urls = <String>[];
        final mock = MockClient.streaming((request, _) async {
          urls.add(request.url.toString());
          return zipResponse(zipOf({'r-v1/lib/a.dart': ''}));
        });
        final git = client(httpClient: mock);

        final (tagged, _) = await _done(
          git.fetch(const GitRepositorySource('github.com/o/r', ref: 'v1')),
        );
        await _done(
          git.fetch(const GitRepositorySource('github.com/o/r/tree/dev')),
        );

        expect(urls, [
          'https://api.github.com/repos/o/r/zipball/v1',
          'https://api.github.com/repos/o/r/zipball/dev',
        ]);
        // "r-v1" has no commit hash.
        expect(
          tagged.descriptor,
          const GitDescriptor(url: 'github.com/o/r', ref: 'v1'),
        );
      });

      test('reports download progress every 256 KB', () async {
        // Pseudo-random text does not compress, so the archive stays big.
        final random = Random(1);
        final big = zipOf({
          'r/lib/a.dart': String.fromCharCodes(
            List.generate(600 * 1024, (_) => 33 + random.nextInt(90)),
          ),
          'r/lib/b.dart': 'class B {}',
        });
        final mock = MockClient.streaming(
          (_, _) async => zipResponse(big, withLength: false),
        );

        final (_, events) = await _done(
          client(httpClient: mock)
              .fetch(const GitRepositorySource('github.com/o/r')),
        );
        final downloads = events
            .whereType<FetchProgress>()
            .where((e) => e.phase == FetchPhase.downloading)
            .toList();

        expect(downloads.first.total, isNull);
        expect(downloads.last.done, big.length);
        expect(downloads.length, greaterThanOrEqualTo(2));
      });

      test('asks GitLab for the default branch first', () async {
        final urls = <String>[];
        final mock = MockClient.streaming((request, _) async {
          urls.add(request.url.toString());
          if (request.url.path.startsWith('/api/')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"default_branch": "develop"}')),
              200,
            );
          }
          return zipResponse(
            zipOf({'repo-develop-${'a' * 40}/lib/a.dart': ''}),
          );
        });

        final (snapshot, events) = await _done(
          client(httpClient: mock)
              .fetch(const GitRepositorySource('https://gitlab.com/g/repo')),
        );

        expect(urls, [
          'https://gitlab.com/api/v4/projects/g%2Frepo',
          'https://gitlab.com/g/repo/-/archive/develop/repo-develop.zip',
        ]);
        expect(events.first, const FetchProgress(FetchPhase.resolving));
        expect((snapshot.descriptor as GitDescriptor).commit, 'a' * 40);
      });

      test('fails with $NetworkFailure for an odd GitLab answer', () async {
        final mock = MockClient.streaming(
          (_, _) async =>
              http.StreamedResponse(Stream.value(utf8.encode('[]')), 200),
        );

        final failure = await _failure(
          client(httpClient: mock)
              .fetch(const GitRepositorySource('gitlab.com/g/repo')),
        );

        expect(failure, const NetworkFailure('unexpected answer from GitLab'));
      });

      test('fails with $InvalidGitUrl for an unknown host', () async {
        final failure = await _failure(
          client().fetch(const GitRepositorySource('https://example.com/o/r')),
        );

        expect(failure, const InvalidGitUrl('https://example.com/o/r'));
      });

      test('fails with $RepositoryNotFound on 404', () async {
        final failure = await _failure(
          client(httpClient: MockClient((_) async => http.Response('', 404)))
              .fetch(const GitRepositorySource('github.com/o/private')),
        );

        expect(failure, const RepositoryNotFound('github.com/o/private'));
      });

      test('fails with $RateLimited when GitHub limits requests', () async {
        final failure = await _failure(
          client(
            httpClient: MockClient(
              (_) async => http.Response(
                '',
                403,
                headers: {
                  'x-ratelimit-remaining': '0',
                  'x-ratelimit-reset': '1790000000',
                },
              ),
            ),
          ).fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(
          failure,
          RateLimited(
            resetAt: DateTime.fromMillisecondsSinceEpoch(
              1790000000 * 1000,
              isUtc: true,
            ),
          ),
        );
      });

      test('fails with $RateLimited without a reset time', () async {
        final failure = await _failure(
          client(
            httpClient: MockClient(
              (_) async => http.Response(
                '',
                429,
                headers: {'x-ratelimit-remaining': '0'},
              ),
            ),
          ).fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(failure, const RateLimited());
      });

      test('fails with $NetworkFailure on other statuses', () async {
        final failure = await _failure(
          client(httpClient: MockClient((_) async => http.Response('', 403)))
              .fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(
          failure,
          const NetworkFailure('api.github.com answered HTTP 403'),
        );
      });

      test(
        'fails with $NetworkFailure when the host cannot be reached',
        () async {
          final failure = await _failure(
            client(
              httpClient: MockClient(
                (_) async => throw http.ClientException('no route'),
              ),
            ).fetch(const GitRepositorySource('github.com/o/r')),
          );

          expect(failure, isA<NetworkFailure>());
        },
      );

      test('fails with $NetworkFailure when the download breaks', () async {
        final mock = MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream<List<int>>.error(const SocketException('reset')),
            200,
          ),
        );

        final failure = await _failure(
          client(httpClient: mock)
              .fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(
          (failure as NetworkFailure).details,
          contains('download interrupted'),
        );
      });

      test('fails with $ArchiveTooLarge from the announced size', () async {
        final mock = MockClient.streaming(
          (_, _) async => zipResponse(githubZip()),
        );

        final failure = await _failure(
          client(
            httpClient: mock,
            maxArchiveBytes: 100,
          ).fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(failure, const ArchiveTooLarge(100));
      });

      test('fails with $ArchiveTooLarge while downloading', () async {
        final mock = MockClient.streaming(
          (_, _) async => zipResponse(githubZip(), withLength: false),
        );

        final failure = await _failure(
          client(
            httpClient: mock,
            maxArchiveBytes: 100,
          ).fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(failure, const ArchiveTooLarge(100));
      });

      test('stops downloading when cancelled', () async {
        final chunks = StreamController<List<int>>();
        final mock = MockClient.streaming(
          (_, _) async => http.StreamedResponse(chunks.stream, 200),
        );
        final events = <FetchEvent>[];
        final subscription = client(httpClient: mock)
            .fetch(const GitRepositorySource('github.com/o/r'))
            .listen(events.add);
        await Future<void>.delayed(Duration.zero);

        await subscription.cancel();
        chunks.add([1, 2, 3]);
        await Future<void>.delayed(Duration.zero);
        await chunks.close();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(events.whereType<FetchDone>(), isEmpty);
        expect(storage.builders, isEmpty);
      });

      test('fails with $UnsupportedOnWeb where git is not supported', () async {
        final failure = await _failure(
          client(gitSupported: false)
              .fetch(const GitRepositorySource('github.com/o/r')),
        );

        expect(failure, const UnsupportedOnWeb('git repository'));
      });
    });

    group('local folder', () {
      late Directory folder;

      setUp(() async {
        folder = await Directory.systemTemp.createTemp('folder_test_');
        addTearDown(() => folder.delete(recursive: true));
        for (final (path, content) in [
          ('pubspec.yaml', 'name: app'),
          ('lib/main.dart', 'void main() {}'),
          ('lib/src/a.dart', 'class A {}'),
          ('.dart_tool/b.dart', ''),
          ('notes.txt', ''),
        ]) {
          await (File(
            '${folder.path}/$path',
          )..createSync(recursive: true)).writeAsString(content);
        }
        await Link('${folder.path}/lib/outside.dart').create('/etc/hostname');
      });

      test('lists the kept files in place, without links', () async {
        final (snapshot, events) = await _done(
          client(reader: const IoLocalFolderReader())
              .fetch(LocalFolderSource(folder.path)),
        );

        expect(events.first, const FetchProgress(FetchPhase.listing));
        expect(snapshot.paths, [
          'lib/main.dart',
          'lib/src/a.dart',
          'pubspec.yaml',
        ]);
        expect(await snapshot.readAsString('lib/main.dart'), 'void main() {}');
        expect(
          snapshot.descriptor,
          LocalFolderDescriptor(
            name: folder.uri.pathSegments.reversed.firstWhere(
              (s) => s.isNotEmpty,
            ),
          ),
        );
      });

      test('disposes the snapshot when cancelled while listing', () async {
        final events = <FetchEvent>[];
        late StreamSubscription<FetchEvent> subscription;
        subscription = client(reader: const IoLocalFolderReader())
            .fetch(LocalFolderSource(folder.path))
            .listen((event) {
              events.add(event);
              unawaited(subscription.cancel());
            });
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(events, [const FetchProgress(FetchPhase.listing)]);
        expect(folder.existsSync(), isTrue);
      });

      test('never deletes the user folder on dispose', () async {
        final (snapshot, _) = await _done(
          client(reader: const IoLocalFolderReader())
              .fetch(LocalFolderSource(folder.path)),
        );

        await snapshot.dispose();

        expect(folder.existsSync(), isTrue);
      });

      test('fails with $SourceNotFound for a missing folder', () async {
        final failure = await _failure(
          client(reader: const IoLocalFolderReader())
              .fetch(const LocalFolderSource('/no/such/folder')),
        );

        expect(failure, const SourceNotFound('/no/such/folder'));
      });

      test(
        'fails with $UnsupportedOnWeb where folders are unsupported',
        () async {
          final failure = await _failure(
            client(localFoldersSupported: false)
                .fetch(LocalFolderSource(folder.path)),
          );

          expect(failure, const UnsupportedOnWeb('local folder'));
        },
      );
    });
  });

  group(DirectoryTempStorage, () {
    late Directory parent;

    setUp(() async {
      parent = await Directory.systemTemp.createTemp('storage_test_');
      addTearDown(() => parent.delete(recursive: true));
    });

    test('stores files in a temp directory deleted on dispose', () async {
      final builder = await DirectoryTempStorage(parent: parent).create();
      await builder.addFile('lib/a.dart', Uint8List.fromList(utf8.encode('A')));
      final snapshot = await builder.build(
        const ZipDescriptor(fileName: 'a.zip'),
      ) as DirectorySnapshot;

      expect(snapshot.paths, ['lib/a.dart']);
      expect(await snapshot.readAsString('lib/a.dart'), 'A');
      expect(() => snapshot.readAsString('lib/b.dart'), throwsArgumentError);
      await snapshot.dispose();
      await snapshot.dispose();
      expect(snapshot.root.existsSync(), isFalse);
    });

    test('deletes the temp directory when discarded', () async {
      final builder = await DirectoryTempStorage(parent: parent).create();
      await builder.addFile('a.dart', Uint8List(0));

      await builder.discard();
      await builder.discard();

      expect(parent.listSync(), isEmpty);
    });
  });
}

class _BrokenStorage implements TempStorage {
  @override
  Future<SnapshotBuilder> create() async => throw StateError('disk full');
}
