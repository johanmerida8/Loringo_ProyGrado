/// Model for speech recognition results
class SpeechRecognitionResult {
  final String recognizedText;
  final bool isCorrect;
  final double accuracy;
  final DateTime timestamp;

  /// Target words not heard. Non-empty with [isCorrect] = "almost perfect".
  final List<String> missedWords;

  /// Target words that passed only approximately ("gross" for "grass").
  final List<String> approximateWords;

  /// The recognizer's own confidence in what it heard, 0..1 (`-1` = the
  /// device doesn't report one).
  final double confidence;

  /// Below this confidence an otherwise exact answer is not called "perfect":
  /// the recognizer may have corrected a mispronounced word to the likely one.
  static const double lowConfidenceThreshold = 0.7;

  /// Text-wise perfect, but the recognizer wasn't confident (only when the
  /// device reports a confidence at all).
  bool get isLowConfidence =>
      isCorrect &&
      !isImperfect &&
      confidence >= 0 &&
      confidence < lowConfidenceThreshold;

  bool get isPartial => isCorrect && missedWords.isNotEmpty;

  /// Passed, but not exactly (a word missing or only approximate).
  bool get isImperfect =>
      isCorrect && (missedWords.isNotEmpty || approximateWords.isNotEmpty);

  SpeechRecognitionResult({
    required this.recognizedText,
    required this.isCorrect,
    required this.accuracy,
    this.missedWords = const [],
    this.approximateWords = const [],
    this.confidence = -1,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Create from JSON
  factory SpeechRecognitionResult.fromJson(Map<String, dynamic> json) {
    return SpeechRecognitionResult(
      recognizedText: json['recognizedText'] ?? '',
      isCorrect: json['isCorrect'] ?? false,
      accuracy: (json['accuracy'] ?? 0.0).toDouble(),
      timestamp: DateTime.tryParse(json['timestamp'] ?? ''),
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'recognizedText': recognizedText,
      'isCorrect': isCorrect,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  @override
  String toString() {
    return 'SpeechRecognitionResult(recognizedText: $recognizedText, isCorrect: $isCorrect, accuracy: $accuracy)';
  }
}