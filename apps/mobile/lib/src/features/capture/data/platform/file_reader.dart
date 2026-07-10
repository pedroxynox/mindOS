// Platform-conditional reader for locally recorded audio bytes.
// Native uses dart:io; web has no local audio file path, so it throws.
export 'file_reader_unsupported.dart'
    if (dart.library.io) 'file_reader_io.dart'
    if (dart.library.js_interop) 'file_reader_web.dart';
