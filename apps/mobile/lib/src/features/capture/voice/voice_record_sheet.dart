import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/presence_orb.dart';
import 'voice_recorder.dart';

/// Factory for the recorder (overridden in widget tests with a fake).
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>((ref) {
  return PluginVoiceRecorder.new;
});

/// Longest voice note we accept (the server limit is ~10 MB).
const maxVoiceNote = Duration(minutes: 5);

/// Bottom sheet that records a voice note: the presence sphere listens, a
/// timer runs, and "Guardar" returns the [RecordedAudio] (null if cancelled).
class VoiceRecordSheet extends ConsumerStatefulWidget {
  const VoiceRecordSheet({super.key});

  @override
  ConsumerState<VoiceRecordSheet> createState() => _VoiceRecordSheetState();
}

class _VoiceRecordSheetState extends ConsumerState<VoiceRecordSheet> {
  late final VoiceRecorder _recorder = ref.read(voiceRecorderFactoryProvider)();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _recorder.start();
      if (!mounted) return;
      setState(() => _recording = true);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed >= maxVoiceNote) _finish();
      });
    } on MicrophoneUnavailable catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pude empezar a grabar. Inténtalo de nuevo.');
      }
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    RecordedAudio? audio;
    try {
      audio = await _recorder.stop();
    } catch (_) {
      audio = null;
    }
    if (!mounted) return;
    if (audio == null) {
      setState(() {
        _finishing = false;
        _recording = false;
        _error = 'No se grabó nada. Inténtalo de nuevo.';
      });
      return;
    }
    Navigator.of(context).pop(audio);
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String get _clock {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PresenceOrb(
              size: 96,
              state: _error != null
                  ? OrbState.alert
                  : _recording
                      ? OrbState.listening
                      : OrbState.idle,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? (_recording ? 'Te escucho…' : 'Preparando el micrófono…'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            if (_error == null)
              Text(
                _clock,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            if (_error == null)
              Text(
                'Habla con naturalidad. mindOS transcribe tu nota y no guarda el audio.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _finishing ? null : _cancel,
                    child: Text(_error != null ? 'Cerrar' : 'Cancelar'),
                  ),
                ),
                if (_error == null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _recording && !_finishing ? _finish : null,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
