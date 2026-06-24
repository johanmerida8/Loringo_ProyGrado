/// Model for speech recognition results
class SpeechRecognitionResult {
  final String recognizedText;
  final bool isCorrect;
  final double accuracy;
  final DateTime timestamp;
  
  SpeechRecognitionResult({
    required this.recognizedText,
    required this.isCorrect,
    required this.accuracy,
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