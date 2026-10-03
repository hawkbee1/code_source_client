import 'package:code_source_client/code_source_client.dart';
import 'package:test/test.dart';

void main() {
  group(FileFilter, () {
    test('keeps Dart files, pubspec.yaml and analysis_options.yaml', () {
      expect(FileFilter.keeps('lib/main.dart'), isTrue);
      expect(FileFilter.keeps('packages/a/pubspec.yaml'), isTrue);
      expect(FileFilter.keeps('analysis_options.yaml'), isTrue);
    });

    test('drops other files', () {
      expect(FileFilter.keeps('README.md'), isFalse);
      expect(FileFilter.keeps('assets/logo.png'), isFalse);
      expect(FileFilter.keeps('pubspec.lock'), isFalse);
    });

    test('drops files in hidden and build folders', () {
      expect(FileFilter.keeps('.dart_tool/a.dart'), isFalse);
      expect(FileFilter.keeps('a/.git/b.dart'), isFalse);
      expect(FileFilter.keeps('build/web/main.dart'), isFalse);
      expect(FileFilter.keeps('lib/building.dart'), isTrue);
    });
  });
}
