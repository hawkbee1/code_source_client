import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Where the code to analyze comes from.
sealed class CodeSource extends Equatable {
  const new();
}

/// A folder on this device, read in place (native platforms only).
class LocalFolderSource extends CodeSource {
  /// Creates a source for the folder at [path].
  const new(this.path);

  /// Absolute path of the folder.
  final String path;

  @override
  List<Object?> get props => [path];
}

/// A zip file the user picked (every platform, the web included).
class ZipBytesSource extends CodeSource {
  /// Creates a source from the [bytes] of the zip file named [fileName].
  const new({required this.fileName, required this.bytes});

  /// Name of the zip file, shown to the user.
  final String fileName;

  /// Content of the zip file.
  final Uint8List bytes;

  @override
  List<Object?> get props => [fileName, bytes];
}

/// A public git repository on GitHub or GitLab, downloaded as an archive
/// (native platforms only: browsers block those downloads).
class GitRepositorySource extends CodeSource {
  /// Creates a source for the repository at [url], at [ref] (a branch or
  /// tag) or at its default branch when [ref] is null.
  const new(this.url, {this.ref});

  /// Repository URL as entered by the user (https, ssh or host/owner/repo).
  final String url;

  /// Branch or tag, or null for the default branch.
  final String? ref;

  @override
  List<Object?> get props => [url, ref];
}
