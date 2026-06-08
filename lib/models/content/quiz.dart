// ============================================================================
// Quiz Models
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class Quiz {
  final String id;
  final String title;
  final String type; // 'lesson' or 'unit'
  final String contentId;
  final String unitId;
  final String? lessonId;
  final int xpReward;
  final int passingScore;
  final bool isGraded;
  final int totalQuestions;
  final List<String>? questionIds; // For lesson quizzes
  final DateTime createdAt;
  final List<QuizQuestion>? questions; // For unit quizzes

  const Quiz({
    required this.id,
    required this.title,
    required this.type,
    required this.contentId,
    required this.unitId,
    this.lessonId,
    required this.xpReward,
    required this.passingScore,
    required this.isGraded,
    required this.totalQuestions,
    this.questionIds,
    required this.createdAt,
    this.questions,
  });

  factory Quiz.fromFirestore(DocumentSnapshot doc, {List<QuizQuestion>? questions}) {
    final data = doc.data() as Map<String, dynamic>;
    return Quiz(
      id: doc.id,
      title: data['title'] ?? '',
      type: data['type'] ?? 'lesson',
      contentId: data['contentId'] ?? '',
      unitId: data['unitId'] ?? '',
      lessonId: data['lessonId'],
      xpReward: (data['xpReward'] as num?)?.toInt() ?? 0,
      passingScore: (data['passingScore'] as num?)?.toInt() ?? 0,
      isGraded: data['isGraded'] ?? false,
      totalQuestions: (data['totalQuestions'] as num?)?.toInt() ?? 0,
      questionIds: data['questionIds'] != null ? List<String>.from(data['questionIds']) : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      questions: questions,
    );
  }

  bool get isLessonQuiz => type == 'lesson';
  bool get isUnitQuiz => type == 'unit';
  bool get hasQuestions => questions != null && questions!.isNotEmpty;
}

class QuizQuestion {
  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final int order;

  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.order,
  });

  factory QuizQuestion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QuizQuestion(
      id: doc.id,
      question: data['question'] ?? '',
      options: List<String>.from(data['options'] ?? []),
      correctIndex: (data['correctIndex'] as num?)?.toInt() ?? 0,
      order: (data['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class QuizAnswer {
  final int questionIndex;
  final int selectedIndex;
  final int correctIndex;
  final bool isCorrect;

  const QuizAnswer({
    required this.questionIndex,
    required this.selectedIndex,
    required this.correctIndex,
    required this.isCorrect,
  });

  factory QuizAnswer.fromMap(Map<String, dynamic> map) {
    return QuizAnswer(
      questionIndex: map['questionIndex'] as int? ?? 0,
      selectedIndex: map['selectedIndex'] as int? ?? -1,
      correctIndex: map['correctIndex'] as int? ?? 0,
      isCorrect: map['isCorrect'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'questionIndex': questionIndex,
      'selectedIndex': selectedIndex,
      'correctIndex': correctIndex,
      'isCorrect': isCorrect,
    };
  }
}

class QuizProgress {
  final String quizId;
  final int score;
  final int totalQuestions;
  final int stars;
  final int xpEarned;
  final DateTime completedAt;
  final DateTime lastAttemptAt;
  final int attempts;
  final bool isCompleted;
  final List<QuizAnswer>? answers;

  const QuizProgress({
    required this.quizId,
    required this.score,
    required this.totalQuestions,
    required this.stars,
    required this.xpEarned,
    required this.completedAt,
    required this.lastAttemptAt,
    required this.attempts,
    required this.isCompleted,
    this.answers,
  });

  factory QuizProgress.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final answersList = data['answers'] as List?;
    return QuizProgress(
      quizId: data['quizId'] ?? '',
      score: (data['score'] as num?)?.toInt() ?? 0,
      totalQuestions: (data['totalQuestions'] as num?)?.toInt() ?? 0,
      stars: (data['stars'] as num?)?.toInt() ?? 0,
      xpEarned: (data['xpEarned'] as num?)?.toInt() ?? 0,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastAttemptAt: (data['lastAttemptAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      attempts: (data['attempts'] as num?)?.toInt() ?? 1,
      isCompleted: data['isCompleted'] ?? false,
      answers: answersList?.map((a) => QuizAnswer.fromMap(a as Map<String, dynamic>)).toList(),
    );
  }

  int get percent => totalQuestions == 0 ? 0 : (score / totalQuestions * 100).round();
}