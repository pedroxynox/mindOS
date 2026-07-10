/// Web has no local audio-file path (voice capture is not offered on web yet),
/// so reading local audio bytes is unsupported.
Future<List<int>> readLocalFileBytes(String localPath) {
  throw UnsupportedError('Local audio files are not available on the web.');
}
