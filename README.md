# code_source_client

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

Gets the Dart source code that [dart_code_3D](https://github.com/hawkbee1/dart_code_3d)
analyzes, into a **snapshot**. Getting the code is separate from analyzing it: the
engine only ever sees a `SourceSnapshot`. Pure Dart, works on the web.

## Part of hawkbee

This repository is a git submodule of the
[hawkbee](https://github.com/hawkbee1/hawkbee) monorepo and **only builds inside it**:

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

## Sources

| Source | Native platforms | Web |
|---|---|---|
| `LocalFolderSource(path)` | read in place, nothing copied; links are not followed | unsupported (`UnsupportedOnWeb`) |
| `ZipBytesSource(fileName:, bytes:)` | extracted into a temporary directory | extracted into memory |
| `GitRepositorySource(url, ref:)` | public GitHub/GitLab archive over HTTPS, no git binary | unsupported: browsers block the download (no CORS) |

Accepted repository URLs: `https://github.com/o/r(.git)`, `git@github.com:o/r.git`,
`ssh://git@github.com/o/r.git`, `github.com/o/r`, browser URLs with `/tree/<ref>`, and
the same for gitlab.com (with subgroups and `/-/tree/<ref>`). Without a ref, GitHub's
default branch is downloaded directly; GitLab's is looked up first. The commit is read
from the archive's top folder.

Only `.dart` files, `pubspec.yaml` and `analysis_options.yaml` are kept, outside hidden
folders and `build/`. A single wrapping top folder is stripped (`AltMe-main/…`), unless
it is a package folder such as `lib/`.

## Usage

```dart
final client = CodeSourceClient();
await for (final event in client.fetch(
  const GitRepositorySource('https://github.com/TalaoDAO/AltMe'),
)) {
  switch (event) {
    case FetchProgress(:final phase, :final done, :final total):
      print('$phase $done/${total ?? '?'}');
    case FetchDone(:final snapshot):
      print(snapshot.paths.length);
      await snapshot.dispose(); // deletes the temporary folder
    case FetchFailed(:final failure):
      print(failure.message);
  }
}
```

Cancelling the subscription stops the fetch and deletes what was stored. Failures are
typed (`SourceNotFound`, `InvalidGitUrl`, `RepositoryNotFound` (also private repos),
`RateLimited`, `NetworkFailure`, `ArchiveTooLarge`, `InvalidArchive`, `UnsupportedOnWeb`).
Zip entries with absolute paths or `..` are refused, and archives and extracted code are
capped (500 MB each by default).

## Running tests

```sh
very_good test --coverage
```

The real GitHub downloads in `test/network/` are skipped by default; run them with the
Very Good CLI MCP test tool (`tags: network`, `run_skipped: true`). Measured on
2026-10-03: flutter_scene 0.23.0 in 1.5 s (12.7 MB, 914 Dart files), AltMe in 3.1 s
(64.6 MB, 1,347 Dart files).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
