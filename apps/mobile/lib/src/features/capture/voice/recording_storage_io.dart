import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A fresh temp-file path for a new recording (mobile/desktop).
Future<String> newRecordingPath(String extension) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return p.join(dir.path, 'mindos-voice-$stamp.$extension');
}

/// Read the finished recording and delete the temp file: the bytes move into
/// the offline outbox and the file is no longer needed.
Future<Uint8List> takeRecording(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  try {
    await file.delete();
  } catch (_) {}
  return bytes;
}
