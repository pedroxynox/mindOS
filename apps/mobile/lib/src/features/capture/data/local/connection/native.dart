import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native (mobile/desktop) connection: a file-backed SQLite database opened
/// lazily off the UI isolate in the app documents directory.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mindos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
