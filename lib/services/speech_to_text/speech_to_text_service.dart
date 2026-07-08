import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_permissions.dart';
import 'speech_recognition_result.dart';

class SpeechToTextService {
  static final SpeechToTextService _instance = SpeechToTextService._internal();
  factory SpeechToTextService() => _instance;
  SpeechToTextService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isAvailable = false;
  bool _isListening = false;
  String _lastRecognizedText = '';

  double _currentSoundLevel = 0.0;
  double get currentSoundLevel => _currentSoundLevel;
  
  // Para evitar múltiples errores de volumen bajo
  bool _hasShownLowVolumeWarning = false;
  
  // Callbacks
  VoidCallback? onListeningStart;
  VoidCallback? onListeningStop;
  Function(String)? onPartialResult;
  Function(SpeechRecognitionResult)? onFinalResult;
  Function(String)? onError;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get lastRecognizedText => _lastRecognizedText;

  /// Initialize speech recognition
  Future<bool> initialize() async {
    // First check permission
    final hasPermission = await SpeechPermissions.isMicrophonePermissionGranted();
    if (!hasPermission) {
      debugPrint('Microphone permission not granted');
      return false;
    }

    // Initialize speech recognition
    _isAvailable = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech recognition error: ${error.errorMsg}');
        _isListening = false;
        onError?.call(error.errorMsg);
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'notListening' && _isListening) {
          _isListening = false;
          onListeningStop?.call();
        }
      },
    );
    
    return _isAvailable;
  }

  /// Start listening for speech
  Future<void> startListening({String targetPhrase = '', String localeId = 'en_US'}) async {
    if (!_isAvailable) {
      final initialized = await initialize();
      if (!initialized) {
        onError?.call('Speech recognition not available');
        return;
      }
    }

    if (_isListening) return;

    // Reset warning flag
    _hasShownLowVolumeWarning = false;
    _currentSoundLevel = 0.0;
    
    _isListening = true;
    onListeningStart?.call();
    
    await _speech.listen(
      onResult: (result) {
        // Reset warning flag when we get any result (means speech is detected)
        _hasShownLowVolumeWarning = false;
        
        if (!result.finalResult) {
          _lastRecognizedText = result.recognizedWords;
          onPartialResult?.call(result.recognizedWords);
        } else {
          _lastRecognizedText = result.recognizedWords;
          _isListening = false;
          
          final isCorrect = _matchesTarget(result.recognizedWords, targetPhrase);
          final accuracy = _calculateAccuracy(result.recognizedWords, targetPhrase);
          
          final speechResult = SpeechRecognitionResult(
            recognizedText: result.recognizedWords,
            isCorrect: isCorrect,
            accuracy: accuracy,
          );
          
          onFinalResult?.call(speechResult);
          onListeningStop?.call();
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      localeId: localeId,
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      onSoundLevelChange: (level) {
        _currentSoundLevel = level;
        // ✅ Solo mostrar advertencia una vez y cuando no hay resultados
        if (!_hasShownLowVolumeWarning && level < 0.05 && _isListening && _lastRecognizedText.isEmpty) {
          _hasShownLowVolumeWarning = true;
          // Usar onError solo para errores reales, no para advertencias
          // Mejor manejarlo con un callback separado o simplemente no mostrar SnackBar
          debugPrint('Volume too low: $level');
        }
      },
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      onListeningStop?.call();
    }
  }

  /// Cancel listening without processing
  Future<void> cancelListening() async {
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      onListeningStop?.call();
    }
  }

  bool _matchesTarget(String spokenText, String targetPhrase) {
    if (targetPhrase.isEmpty) return true;
    if (spokenText.isEmpty) return false;
    final normalizedSpoken = _normalizeText(spokenText);
    final normalizedTarget = _normalizeText(targetPhrase);
    return normalizedSpoken == normalizedTarget;
  }

  double _calculateAccuracy(String spokenText, String targetPhrase) {
    if (targetPhrase.isEmpty) return 1.0;
    if (spokenText.isEmpty) return 0.0;
    
    final normalizedSpoken = _normalizeText(spokenText);
    final normalizedTarget = _normalizeText(targetPhrase);
    
    if (normalizedSpoken == normalizedTarget) return 1.0;
    
    final spokenWords = normalizedSpoken.split(' ');
    final targetWords = normalizedTarget.split(' ');
    
    int matches = 0;
    for (int i = 0; i < spokenWords.length && i < targetWords.length; i++) {
      if (spokenWords[i] == targetWords[i]) matches++;
    }
    
    return matches / targetWords.length;
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void dispose() {
    _speech.stop();
  }
}