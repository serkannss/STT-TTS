import 'dart:io';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/elevenlabs_service.dart';
import '../platform/recorder.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _textController = TextEditingController();
  final _record = AudioRecorder();
  late final AppRecorder _appRecorder;
  final _player = AudioPlayer();
  final _service = ElevenLabsService();

  bool _isRecording = false;
  String? _recordPath;
  String _transcript = '';
  bool _busy = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _textController.dispose();
    _player.dispose();
    _timer?.cancel();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    _appRecorder = createRecorder();
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _ensurePermissions() async {
    if (kIsWeb) {
      // Web'de storage izni yok; mikrofon izni tarayici prompt'u ile gelir
      return;
    }
    final mic = await Permission.microphone.request();
    if (mic.isDenied) throw Exception('Mikrofon izni gerekli');
  }

  Future<void> _toggleRecord() async {
    try {
      await _ensurePermissions();
      if (!_isRecording) {
        await _appRecorder.start();
        _elapsed = Duration.zero;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _elapsed += const Duration(seconds: 1));
        });
        setState(() => _isRecording = true);
      } else {
        final rec = await _appRecorder.stopAndGetBytes();
        setState(() => _isRecording = false);
        _timer?.cancel();
        if (rec != null) {
          setState(() => _busy = true);
          try {
            final text = await _service.speechBytesToText(bytes: rec.bytes, mimeType: rec.mimeType);
            if (!mounted) return;
            setState(() => _transcript = text);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transkripsiyon hatasi: $e')));
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kayit hatasi: $e')));
    }
  }

  Future<void> _doTranscribe() async {
    if (_recordPath == null) return;
    setState(() => _busy = true);
    try {
      final text = await _service.speechToText(audioFile: File(_recordPath!));
      setState(() => _transcript = text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transkripsiyon hatasi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doTts() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await _service.textToSpeech(text: text);
      if (kIsWeb) {
        final dataUri = 'data:audio/mpeg;base64,' + base64Encode(bytes);
        await _player.play(UrlSource(dataUri));
      } else {
        await _player.play(BytesSource(bytes));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('TTS hatasi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('ElevenLabs Voice Studio'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D1B33), Color(0xFF2C235C), Color(0xFF0B3A5F)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
                child: Column(
                  children: [
                Card(
                  color: const Color(0xFFF2F5FA),
                  elevation: 10,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Metinden Sese', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _textController,
                          decoration: const InputDecoration(
                            labelText: 'Metninizi yazın',
                            prefixIcon: Icon(Icons.text_fields),
                            border: OutlineInputBorder(),
                          ),
                          minLines: 2,
                          maxLines: 6,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _doTts,
                                icon: const Icon(Icons.volume_up),
                                label: const Text('Metni Sese Çevir'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Card(
                  color: const Color(0xFFF2F5FA),
                  elevation: 10,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Sesten Metne', style: Theme.of(context).textTheme.titleLarge),
                            Row(children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _isRecording ? Colors.red.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Row(children: [
                                    Icon(_isRecording ? Icons.fiber_manual_record : Icons.mic_none, size: 16, color: _isRecording ? Colors.red : Colors.blue),
                                    const SizedBox(width: 6),
                                    Text(_isRecording ? 'Kayıtta' : 'Hazır'),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_isRecording)
                                Text(_formatDuration(_elapsed), style: Theme.of(context).textTheme.bodyMedium),
                            ])
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isRecording ? Colors.red : Theme.of(context).colorScheme.primary).withOpacity(0.35),
                                  blurRadius: 20,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(24),
                                backgroundColor: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _busy ? null : _toggleRecord,
                              child: Icon(_isRecording ? Icons.stop : Icons.mic, size: 36),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFE6EEF8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          height: 140,
                          child: SingleChildScrollView(
                            child: Text(
                              _transcript.isEmpty ? 'Transkripsiyon burada görünecek' : _transcript,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _transcript.isEmpty
                                    ? null
                                    : () async {
                                        await Clipboard.setData(ClipboardData(text: _transcript));
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopyalandı')));
                                      },
                                icon: const Icon(Icons.copy),
                                label: const Text('Kopyala'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _transcript.isEmpty
                                    ? null
                                    : () { setState(() => _transcript = ''); },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Temizle'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


