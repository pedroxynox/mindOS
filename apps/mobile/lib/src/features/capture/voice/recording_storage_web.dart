import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The web recorder ignores the path (MediaRecorder keeps audio in memory).
Future<String> newRecordingPath(String extension) async => '';

/// Read the finished recording from its `blob:` URL.
Future<Uint8List> takeRecording(String blobUrl) async {
  final res = await http.get(Uri.parse(blobUrl));
  return res.bodyBytes;
}
