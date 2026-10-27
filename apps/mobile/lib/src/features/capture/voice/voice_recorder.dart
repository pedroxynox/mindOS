import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

import 'recording_storage.dart';

/// A finished voice note, ready for the offline outbox.
class RecordedAudio {
  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
  });

  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
}

/// Thrown when the microphone cannot be used (no permission / no device).
class MicrophoneUnavailable implements Exception {
  const MicrophoneUnavailable(this.message);
  final String message;
}

/// Records a voice note. Abstract so widget tests can use a fake (no mic).
abstract class VoiceRecorder {
  Future<void> start();

  /// Stop and return the recording, or null if nothing was captured.
  Future<RecordedAudio?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// One container/codec we can record in, with its MIME type and extension.
class _Format {
  const _Format(this.encoder, this.mimeType, this.extension);
  final AudioEncoder encoder;
  final String mimeType;
  final String extension;
}

/// [VoiceRecorder] on the `record` plugin: Opus/WebM in browsers that support
/// it (AAC/MP4 on Safari), AAC/M4A on mobile — all formats the speech-to-text
/// API accepts (ADR-021).
class PluginVoiceRecorder implements VoiceRecorder {
  PluginVoiceRecorder() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  final Stopwatch _clock = Stopwatch();
  _Format? _format;

  static const _web = [
    _Format(AudioEncoder.opus, 'audio/webm', 'webm'),
    _Format(AudioEncoder.aacLc, 'audio/mp4', 'm4a'),
    _Format(AudioEncoder.wav, 'audio/wav', 'wav'),
  ];
  static const _native = [
    _Format(AudioEncoder.aacLc, 'audio/mp4', 'm4a'),
    _Format(AudioEncoder.wav, 'audio/wav', 'wav'),
  ];

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw const MicrophoneUnavailable(
        'Necesito permiso para usar el micrófono. Actívalo en tu navegador o en los ajustes.',
      );
    }
    _Format? chosen;
    for (final f in kIsWeb ? _web : _native) {
      if (await _recorder.isEncoderSupported(f.encoder)) {
        chosen = f;
        break;
      }
    }
    if (chosen == null) {
      throw const MicrophoneUnavailable(
          'Este dispositivo no puede grabar audio en un formato compatible.');
    }
    _format = chosen;
    final path = await newRecordingPath(chosen.extension);
    await _recorder.start(
      RecordConfig(encoder: chosen.encoder, numChannels: 1, bitRate: 64000),
      path: path,
    );
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<RecordedAudio?> stop() async {
    _clock.stop();
    final location = await _recorder.stop();
    final format = _format;
    if (location == null || location.isEmpty || format == null) return null;
    final bytes = await takeRecording(location);
    if (bytes.isEmpty) return null;
    return RecordedAudio(
      bytes: bytes,
      mimeType: format.mimeType,
      durationMs: _clock.elapsedMilliseconds,
    );
  }

  @override
  Future<void> cancel() async {
    _clock.stop();
    await _recorder.cancel();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
