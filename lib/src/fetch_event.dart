import 'package:code_source_client/src/source_snapshot.dart';
import 'package:equatable/equatable.dart';

/// Why getting the code failed.
sealed class FetchFailure extends Equatable implements Exception {
  const new();

  /// A message for the user, in English (the app localizes by type).
  String get message;

  @override
  String toString() => 'FetchFailure: $message';
}

/// The local folder does not exist.
class SourceNotFound extends FetchFailure {
  /// Creates the failure for [path].
  const new(this.path);

  /// The missing folder.
  final String path;

  @override
  String get message => 'Folder not found: $path';

  @override
  List<Object?> get props => [path];
}

/// The text is not a GitHub or GitLab repository URL.
class InvalidGitUrl extends FetchFailure {
  /// Creates the failure for [input].
  const new(this.input);

  /// What the user entered.
  final String input;

  @override
  String get message =>
      'Not a GitHub or GitLab repository URL: "$input". Example: '
      'https://github.com/owner/repository';

  @override
  List<Object?> get props => [input];
}

/// The host answered 404: the repository or ref does not exist, or it is
/// private (hosts answer 404 to hide private repositories).
class RepositoryNotFound extends FetchFailure {
  /// Creates the failure for [url].
  const new(this.url);

  /// The repository URL.
  final String url;

  @override
  String get message =>
      'Repository not found or private: $url. Private repositories come in '
      'a later version.';

  @override
  List<Object?> get props => [url];
}

/// The host refuses more requests for now (GitHub's anonymous rate limit).
class RateLimited extends FetchFailure {
  /// Creates the failure; [resetAt] is when requests are allowed again.
  const new({this.resetAt});

  /// When the limit resets, if the host said so.
  final DateTime? resetAt;

  @override
  String get message => resetAt == null
      ? 'Too many downloads from this host. Try again later.'
      : 'Too many downloads from this host. Try again after '
            '${resetAt!.toLocal()}.';

  @override
  List<Object?> get props => [resetAt];
}

/// The download failed: no connection, an unexpected status, a cut stream.
class NetworkFailure extends FetchFailure {
  /// Creates the failure with technical [details].
  const new(this.details);

  /// What went wrong, for the error details box.
  final String details;

  @override
  String get message => 'Download failed: $details';

  @override
  List<Object?> get props => [details];
}

/// The archive, or the code extracted from it, exceeds the size limit.
class ArchiveTooLarge extends FetchFailure {
  /// Creates the failure for a limit of [limitBytes].
  const new(this.limitBytes);

  /// The limit that was exceeded.
  final int limitBytes;

  @override
  String get message =>
      'The code is larger than the '
      '${(limitBytes / (1024 * 1024)).round()} MB limit.';

  @override
  List<Object?> get props => [limitBytes];
}

/// The archive is not a valid zip, or contains unsafe paths.
class InvalidArchive extends FetchFailure {
  /// Creates the failure with the [reason].
  const new(this.reason);

  /// What is wrong with the archive.
  final String reason;

  @override
  String get message => 'Invalid archive: $reason';

  @override
  List<Object?> get props => [reason];
}

/// The source cannot be used on this platform (web).
class UnsupportedOnWeb extends FetchFailure {
  /// Creates the failure for a source described by [sourceKind].
  const new(this.sourceKind);

  /// The kind of source, e.g. `git repository`.
  final String sourceKind;

  @override
  String get message =>
      'A $sourceKind cannot be read in a browser. Pick a zip file instead.';

  @override
  List<Object?> get props => [sourceKind];
}

/// What a fetch is doing.
enum FetchPhase {
  /// Looking up the repository (e.g. its default branch).
  resolving,

  /// Downloading the archive; progress counts bytes.
  downloading,

  /// Extracting the archive; progress counts entries.
  extracting,

  /// Listing a local folder.
  listing,
}

/// Something that happened while getting the code.
sealed class FetchEvent extends Equatable {
  const new();
}

/// Progress: [done] out of [total] (null when unknown) in [phase].
class FetchProgress extends FetchEvent {
  /// Creates a progress event.
  const new(this.phase, {this.done = 0, this.total});

  /// What the fetch is doing.
  final FetchPhase phase;

  /// Bytes or entries done so far.
  final int done;

  /// Total bytes or entries, when known.
  final int? total;

  @override
  List<Object?> get props => [phase, done, total];
}

/// The code is ready to analyze. Dispose the [snapshot] when done.
class FetchDone extends FetchEvent {
  /// Creates the final success event.
  const new(this.snapshot);

  /// The fetched files.
  final SourceSnapshot snapshot;

  @override
  List<Object?> get props => [snapshot];
}

/// Getting the code failed.
class FetchFailed extends FetchEvent {
  /// Creates the final failure event.
  const new(this.failure);

  /// Why it failed.
  final FetchFailure failure;

  @override
  List<Object?> get props => [failure];
}
