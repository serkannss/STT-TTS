import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class ElevenLabsService {
  ElevenLabsService();

  String get _apiKey {
    final v = dotenv.env['ELEVENLABS_API_KEY']?.trim();
    return (v == null || v.isEmpty) ? '' : v;
  }
  String get _voiceId {
    final v = dotenv.env['ELEVENLABS_VOICE_ID']?.trim();
    return (v == null || v.isEmpty) ? 'rSuyucEH95GpZEfLV0AM' : v;
  }
  String get _sttModel {
    final raw = dotenv.env['ELEVENLABS_STT_MODEL']?.trim();
    if (raw == null || raw.isEmpty) return 'scribe_v1';
    final lower = raw.toLowerCase();
    if (lower == 'whisper-1' || lower == 'whisper_turbo' || lower == 'whisper-turbo') {
      return 'scribe_v1';
    }
    return raw;
  }

  Future<Uint8List> textToSpeech({required String text, String? voiceId}) async {
    final selectedVoiceId = voiceId ?? _voiceId;
    final url = Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$selectedVoiceId/stream');

    final response = await http.post(
      url,
      headers: {
        'xi-api-key': _apiKey,
        'accept': 'audio/mpeg',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'text': text,
        'model_id': 'eleven_multilingual_v2',
        'output_format': 'mp3_44100_128',
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.75
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS failed: ${response.statusCode} ${response.body}');
    }

    // Web'de dosya sistemi yok; bayt olarak dondurup UI'da cal
    if (kIsWeb) {
      return response.bodyBytes;
    }

    // Mobil/desktop icin de bayt dondur; UI evrensel BytesSource kullanir
    return response.bodyBytes;
  }

  Future<String> speechToText({required File audioFile, String? model}) async {
    final selectedModel = model ?? _sttModel;
    final url = Uri.parse('https://api.elevenlabs.io/v1/speech-to-text');

    final request = http.MultipartRequest('POST', url)
      ..headers['xi-api-key'] = _apiKey
      ..headers['accept'] = 'application/json'
      ..fields['model_id'] = selectedModel
      ..fields['language'] = 'tr'
      ..fields['translate'] = 'true'
      ..fields['target_language'] = 'tr'
      ..fields['task'] = 'transcribe'
      ..fields['initial_prompt'] = 'Lutfen yalnizca Turkce olarak transkribe et.'
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('STT failed: ${streamed.statusCode} $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['text'] as String? ?? decoded['transcript'] as String? ?? '';
  }

  Future<String> speechBytesToText({required Uint8List bytes, required String mimeType, String? model}) async {
    final selectedModel = model ?? _sttModel;
    final url = Uri.parse('https://api.elevenlabs.io/v1/speech-to-text');

    final request = http.MultipartRequest('POST', url)
      ..headers['xi-api-key'] = _apiKey
      ..headers['accept'] = 'application/json'
      ..fields['model_id'] = selectedModel
      // Force Turkish recognition; avoid auto language switching
      ..fields['language'] = 'tr'
      ..fields['translate'] = 'true'
      ..fields['target_language'] = 'tr'
      ..fields['task'] = 'transcribe'
      ..fields['initial_prompt'] = 'Lutfen yalnizca Turkce olarak transkribe et.'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: mimeType.contains('ogg') ? 'input.ogg' : (mimeType.contains('webm') ? 'input.webm' : 'input.m4a'),
        contentType: MediaType.parse(mimeType),
      ));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      // Surface server error details to caller for debugging
      throw Exception('STT failed: ${streamed.statusCode} $body');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['text'] as String? ?? decoded['transcript'] as String? ?? '';
  }
}


