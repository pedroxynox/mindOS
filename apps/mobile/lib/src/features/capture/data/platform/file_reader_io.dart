import 'dart:io';

/// Read the bytes of a locally recorded audio file (mobile/desktop).
Future<List<int>> readLocalFileBytes(String localPath) =>
    File(localPath).readAsBytes();
