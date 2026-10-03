// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:code_source_client/code_source_client.dart';

void main() {
  group('CodeSourceClient', () {
    test('can be instantiated', () {
      expect(CodeSourceClient(), isNotNull);
    });
  });
}
