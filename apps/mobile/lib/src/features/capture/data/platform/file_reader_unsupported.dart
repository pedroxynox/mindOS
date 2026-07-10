/// Fallback when neither dart:io nor dart:js_interop is available.
Future<List<int>> readLocalFileBytes(String localPath) {
  throw UnsupportedError('Reading local files is unsupported on this platform.');
}
