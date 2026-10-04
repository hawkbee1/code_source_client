import 'package:code_source_client/src/temp_storage.dart';

/// Browsers have no file system: snapshots stay in memory.
TempStorage defaultTempStorage() => const MemoryTempStorage();

/// Browsers cannot read a local folder.
LocalFolderReader? defaultLocalFolderReader() => null;

/// Browsers block downloads from GitHub and GitLab (no CORS headers).
const bool gitSupportedByDefault = false;
