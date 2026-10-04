import 'package:equatable/equatable.dart';

/// A git hosting service the MVP downloads from.
enum GitHost {
  /// github.com
  github,

  /// gitlab.com
  gitlab,
}

/// A parsed GitHub or GitLab repository URL.
class GitUrl extends Equatable {
  /// Creates a URL for [path] (`owner/repo`, or `group/sub/repo` on GitLab)
  /// on [host].
  const new({required this.host, required this.path, this.ref});

  /// Parses [input], or returns null when it is not a GitHub or GitLab
  /// repository URL.
  ///
  /// Accepts `https://github.com/o/r(.git)`, `git@github.com:o/r.git`,
  /// `ssh://git@github.com/o/r.git`, `github.com/o/r`, the same for
  /// gitlab.com, and `…/tree/<ref>` (GitHub) or `…/-/tree/<ref>` (GitLab)
  /// browser URLs, which set [ref].
  static GitUrl? tryParse(String input) {
    var rest = input.trim();
    rest = rest.replaceFirst(RegExp('^(https?|ssh)://'), '');
    rest = rest.replaceFirst(RegExp('^git@'), '');
    rest = rest.replaceFirst(RegExp('^www.'), '');
    final hostMatch = RegExp(r'^(github\.com|gitlab\.com)[:/]')
        .firstMatch(rest);
    if (hostMatch == null) return null;
    final host = hostMatch.group(1) == 'github.com'
        ? GitHost.github
        : GitHost.gitlab;
    var segments = rest
        .substring(hostMatch.end)
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    String? ref;
    final treeMarker = host == GitHost.github ? ['tree'] : ['-', 'tree'];
    for (var i = 0; i + treeMarker.length < segments.length; i++) {
      if (_startsWithAt(segments, treeMarker, i)) {
        ref = segments.sublist(i + treeMarker.length).join('/');
        segments = segments.sublist(0, i);
        break;
      }
    }
    if (segments.isNotEmpty && segments.last.endsWith('.git')) {
      final last = segments.removeLast();
      segments.add(last.substring(0, last.length - 4));
    }
    final validLength = host == GitHost.github
        ? segments.length == 2
        : segments.length >= 2;
    final valid = RegExp(r'^[A-Za-z0-9_.-]+$');
    if (!validLength || !segments.every(valid.hasMatch)) return null;
    return GitUrl(host: host, path: segments.join('/'), ref: ref);
  }

  static bool _startsWithAt(List<String> list, List<String> part, int at) {
    for (var i = 0; i < part.length; i++) {
      if (list[at + i] != part[i]) return false;
    }
    return true;
  }

  /// The hosting service.
  final GitHost host;

  /// `owner/repo` (GitHub) or `group[/subgroup…]/repo` (GitLab).
  final String path;

  /// The branch or tag found in a browser URL, if any.
  final String? ref;

  /// The repository's name (last path segment).
  String get name => path.split('/').last;

  /// URL of the zip archive at [ref], or at the default branch when [ref] is
  /// null (GitHub only; GitLab needs the default branch name first).
  Uri archiveUri({String? ref}) {
    final pathSegments = path.split('/');
    switch (host) {
      case GitHost.github:
        return Uri(
          scheme: 'https',
          host: 'api.github.com',
          pathSegments: ['repos', ...pathSegments, 'zipball', ?ref],
        );
      case GitHost.gitlab:
        final branch = ref ?? (throw ArgumentError.notNull('ref'));
        return Uri(
          scheme: 'https',
          host: 'gitlab.com',
          pathSegments: [
            ...pathSegments,
            '-',
            'archive',
            branch,
            '$name-${branch.replaceAll('/', '-')}.zip',
          ],
        );
    }
  }

  /// URL of GitLab's project API, which tells the default branch.
  Uri get gitlabProjectUri => Uri(
    scheme: 'https',
    host: 'gitlab.com',
    pathSegments: ['api', 'v4', 'projects', path],
  );

  @override
  List<Object?> get props => [host, path, ref];
}
