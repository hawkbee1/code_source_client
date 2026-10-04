import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_source_client/src/code_source.dart';
import 'package:code_source_client/src/fetch_event.dart';
import 'package:code_source_client/src/git_url.dart';
import 'package:code_source_client/src/platform/platform.dart' as platform;
import 'package:code_source_client/src/source_snapshot.dart';
import 'package:code_source_client/src/temp_storage.dart';
import 'package:code_source_client/src/zip_extractor.dart';
import 'package:http/http.dart' as http;

/// Gets the code of a [CodeSource] into a [SourceSnapshot].
///
/// Getting the code is separate from analyzing it: the engine only sees the
/// snapshot. Local folders are read in place; zips and git archives are
/// extracted into temporary storage (a temp directory, or memory on the web),
/// keeping only the files the engine reads.
class CodeSourceClient {
  /// Creates a client. Every dependency defaults to the platform's; tests
  /// inject their own. [localFoldersSupported] and [gitSupported] set to
  /// false reproduce the web, where neither source works.
  new({
    http.Client? httpClient,
    TempStorage? tempStorage,
    LocalFolderReader? localFolderReader,
    bool? localFoldersSupported,
    bool? gitSupported,
    this.maxArchiveBytes = defaultMaxArchiveBytes,
    this.maxExtractedBytes = defaultMaxExtractedBytes,
  }) : _http = httpClient ?? http.Client(),
       _tempStorage = tempStorage ?? platform.defaultTempStorage(),
       _localFolderReader = (localFoldersSupported ?? true)
           ? localFolderReader ?? platform.defaultLocalFolderReader()
           : null,
       _gitSupported = gitSupported ?? platform.gitSupportedByDefault;

  /// Default limit of a downloaded or picked archive: 500 MB.
  static const int defaultMaxArchiveBytes = 500 * 1024 * 1024;

  /// Default limit of the files kept from an archive: 500 MB.
  static const int defaultMaxExtractedBytes = 500 * 1024 * 1024;

  /// `User-Agent` sent to hosts (GitHub's API requires one).
  static const userAgent = 'dart_code_3d';

  /// Largest archive accepted, in bytes.
  final int maxArchiveBytes;

  /// Largest total size of the kept files of an archive, in bytes.
  final int maxExtractedBytes;

  final http.Client _http;
  final TempStorage _tempStorage;
  final LocalFolderReader? _localFolderReader;
  final bool _gitSupported;

  /// Fetches [source].
  ///
  /// Emits [FetchProgress] events, then exactly one [FetchDone] (the caller
  /// owns and must dispose the snapshot) or [FetchFailed]. Cancelling the
  /// subscription stops the fetch and deletes what was stored.
  Stream<FetchEvent> fetch(CodeSource source) {
    var cancelled = false;
    late final StreamController<FetchEvent> controller;
    void emit(FetchEvent event) {
      if (!cancelled) controller.add(event);
    }

    controller = StreamController<FetchEvent>(
      onListen: () async {
        try {
          final snapshot = await _fetch(source, emit, () => cancelled);
          if (cancelled) {
            await snapshot.dispose();
          } else {
            controller.add(FetchDone(snapshot));
          }
        } on _Cancelled {
          // Nothing to report: nobody listens any more.
        } on FetchFailure catch (failure) {
          emit(FetchFailed(failure));
          // A bug, not an expected failure: hand it to the caller as an error
          // rather than losing it.
        } on Object catch (error, stackTrace) {
          if (!cancelled) controller.addError(error, stackTrace);
        } finally {
          await controller.close();
        }
      },
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }

  Future<SourceSnapshot> _fetch(
    CodeSource source,
    void Function(FetchEvent) emit,
    bool Function() isCancelled,
  ) async {
    switch (source) {
      case LocalFolderSource(:final path):
        final reader =
            _localFolderReader ??
            (throw const UnsupportedOnWeb('local folder'));
        emit(const FetchProgress(FetchPhase.listing));
        return await reader.open(path);
      case ZipBytesSource(:final fileName, :final bytes):
        if (bytes.length > maxArchiveBytes) {
          throw ArchiveTooLarge(maxArchiveBytes);
        }
        final (snapshot, _) = await _extract(
          bytes,
          (_) => ZipDescriptor(fileName: fileName),
          emit,
          isCancelled,
        );
        return snapshot;
      case GitRepositorySource(:final url, :final ref):
        if (!_gitSupported) throw const UnsupportedOnWeb('git repository');
        return await _fetchGit(url, ref, emit, isCancelled);
    }
  }

  Future<SourceSnapshot> _fetchGit(
    String input,
    String? requestedRef,
    void Function(FetchEvent) emit,
    bool Function() isCancelled,
  ) async {
    final gitUrl = GitUrl.tryParse(input) ?? (throw InvalidGitUrl(input));
    final ref = requestedRef ?? gitUrl.ref;
    var archiveRef = ref;
    if (gitUrl.host == GitHost.gitlab && archiveRef == null) {
      emit(const FetchProgress(FetchPhase.resolving));
      archiveRef = await _gitlabDefaultBranch(gitUrl, input);
    }
    final bytes = await _download(
      gitUrl.archiveUri(ref: archiveRef),
      input,
      emit,
      isCancelled,
    );
    final (snapshot, _) = await _extract(
      bytes,
      (top) => GitDescriptor(url: input, ref: ref, commit: _commitFrom(top)),
      emit,
      isCancelled,
    );
    return snapshot;
  }

  Future<(SourceSnapshot, String?)> _extract(
    Uint8List bytes,
    SourceDescriptor Function(String? topFolder) describe,
    void Function(FetchEvent) emit,
    bool Function() isCancelled,
  ) async {
    final builder = await _tempStorage.create();
    try {
      final top = await extractZip(
        bytes,
        builder,
        maxExtractedBytes: maxExtractedBytes,
        isCancelled: isCancelled,
        onProgress: (done, total) => emit(
          FetchProgress(FetchPhase.extracting, done: done, total: total),
        ),
      );
      if (isCancelled()) throw const _Cancelled();
      return (await builder.build(describe(top)), top);
    } on Object {
      await builder.discard();
      rethrow;
    }
  }

  Future<String> _gitlabDefaultBranch(GitUrl gitUrl, String input) async {
    final response = await _send(gitUrl.gitlabProjectUri, input);
    final body = await response.stream.bytesToString();
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      return json['default_branch']! as String;
      // A malformed answer can fail in several ways; all mean the same.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      throw const NetworkFailure('unexpected answer from GitLab');
    }
  }

  Future<Uint8List> _download(
    Uri uri,
    String input,
    void Function(FetchEvent) emit,
    bool Function() isCancelled,
  ) async {
    final response = await _send(uri, input);
    final total = response.contentLength;
    if (total != null && total > maxArchiveBytes) {
      throw ArchiveTooLarge(maxArchiveBytes);
    }
    final bytes = BytesBuilder(copy: false);
    var reported = 0;
    emit(FetchProgress(FetchPhase.downloading, total: total));
    try {
      await for (final chunk in response.stream) {
        if (isCancelled()) throw const _Cancelled();
        bytes.add(chunk);
        if (bytes.length > maxArchiveBytes) {
          throw ArchiveTooLarge(maxArchiveBytes);
        }
        // Report at most every 256 KB so the UI is not flooded.
        if (bytes.length - reported >= 256 * 1024) {
          reported = bytes.length;
          emit(
            FetchProgress(
              FetchPhase.downloading,
              done: bytes.length,
              total: total,
            ),
          );
        }
      }
    } on FetchFailure {
      rethrow;
    } on _Cancelled {
      rethrow;
    } on Exception catch (e) {
      throw NetworkFailure('download interrupted ($e)');
    }
    emit(
      FetchProgress(FetchPhase.downloading, done: bytes.length, total: total),
    );
    return bytes.takeBytes();
  }

  Future<http.StreamedResponse> _send(Uri uri, String input) async {
    final http.StreamedResponse response;
    try {
      response = await _http.send(
        http.Request('GET', uri)..headers['User-Agent'] = userAgent,
      );
    } on Exception catch (e) {
      throw NetworkFailure('could not reach ${uri.host} ($e)');
    }
    final status = response.statusCode;
    if (status == 200) return response;
    if (status == 404) throw RepositoryNotFound(input);
    final remaining = response.headers['x-ratelimit-remaining'];
    if ((status == 403 || status == 429) && remaining == '0') {
      final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
      throw RateLimited(
        resetAt: reset == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true),
      );
    }
    throw NetworkFailure('${uri.host} answered HTTP $status');
  }

  /// The commit in an archive's top folder: GitHub names it
  /// `<owner>-<repo>-<sha7>`, GitLab `<repo>-<ref>-<sha40>`.
  static String? _commitFrom(String? topFolder) {
    if (topFolder == null) return null;
    final last = topFolder.split('-').last;
    return RegExp(r'^[0-9a-f]{7,40}$').hasMatch(last) ? last : null;
  }
}

class _Cancelled implements Exception {
  const new();
}
