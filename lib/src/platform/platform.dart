// Platform defaults: a temp directory and local folders on native
// platforms; memory only, no local folders and no git downloads on the web.
export 'platform_web.dart' if (dart.library.io) 'platform_io.dart';
