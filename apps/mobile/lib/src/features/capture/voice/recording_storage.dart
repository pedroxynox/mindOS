// Platform-conditional temporary storage for a recording in progress.
// Native writes a temp file; the web gets a blob: URL from MediaRecorder.
export 'recording_storage_unsupported.dart'
    if (dart.library.io) 'recording_storage_io.dart'
    if (dart.library.js_interop) 'recording_storage_web.dart';
