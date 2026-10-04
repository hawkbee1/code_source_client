/// Which files a snapshot keeps: only what the engine reads.
abstract final class FileFilter {
  /// File names kept besides `.dart` files.
  static const keptFileNames = {'pubspec.yaml', 'analysis_options.yaml'};

  /// Whether a file at [path] (relative, `/` separators) is kept: a `.dart`
  /// file, `pubspec.yaml` or `analysis_options.yaml`, outside skipped folders.
  static bool keeps(String path) {
    final segments = path.split('/');
    if (segments.take(segments.length - 1).any(skipsFolder)) return false;
    final name = segments.last;
    return name.endsWith('.dart') || keptFileNames.contains(name);
  }

  /// Whether a folder named [name] is skipped with everything inside:
  /// hidden folders (`.git`, `.dart_tool`, …) and `build`.
  static bool skipsFolder(String name) =>
      name.startsWith('.') || name == 'build';
}
