// ============================================================================
// Content Models
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class Content {
  final String id;
  final String title;
  final String description;
  final String ageGroup;
  final int order;
  final String status;
  final bool isActive;
  final DateTime createdAt;
  final List<String> assignedTo;
  final String teacherId;

  const Content({
    required this.id,
    required this.title,
    required this.description,
    required this.ageGroup,
    required this.order,
    required this.status,
    required this.isActive,
    required this.createdAt,
    required this.assignedTo,
    required this.teacherId,
  });

  factory Content.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Content(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      ageGroup: data['ageGroup'] ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      status: data['status'] ?? 'pending',
      isActive: data['isActive'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      assignedTo: List<String>.from(data['assignedTo'] ?? []),
      teacherId: data['teacherId'] ?? '',
    );
  }

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}

class Unit {
  final String id;
  final String title;
  final int order;
  final DateTime createdAt;
  final List<Lesson> lessons;

  const Unit({
    required this.id,
    required this.title,
    required this.order,
    required this.createdAt,
    required this.lessons,
  });

  factory Unit.fromFirestore(DocumentSnapshot doc, {List<Lesson> lessons = const []}) {
    final data = doc.data() as Map<String, dynamic>;
    return Unit(
      id: doc.id,
      title: data['title'] ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lessons: lessons,
    );
  }
}

class Lesson {
  final String id;
  final String title;
  final int order;
  final DateTime createdAt;
  final List<Activity> activities;

  const Lesson({
    required this.id,
    required this.title,
    required this.order,
    required this.createdAt,
    required this.activities,
  });

  factory Lesson.fromFirestore(DocumentSnapshot doc, {List<Activity> activities = const []}) {
    final data = doc.data() as Map<String, dynamic>;
    return Lesson(
      id: doc.id,
      title: data['title'] ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      activities: activities,
    );
  }
}

class Activity {
  final String id;
  final String title;
  final int order;
  final int xpBase;
  final String difficulty;
  final String? requiredActivityId;
  final DateTime createdAt;
  final List<Task> tasks;

  const Activity({
    required this.id,
    required this.title,
    required this.order,
    required this.xpBase,
    required this.difficulty,
    this.requiredActivityId,
    required this.createdAt,
    required this.tasks,
  });

  factory Activity.fromFirestore(DocumentSnapshot doc, {List<Task> tasks = const []}) {
    final data = doc.data() as Map<String, dynamic>;
    return Activity(
      id: doc.id,
      title: data['title'] ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      xpBase: (data['xpBase'] as num?)?.toInt() ?? 100,
      difficulty: data['difficulty'] ?? 'easy',
      requiredActivityId: data['requiredActivityId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      tasks: tasks,
    );
  }

  bool get hasRequiredActivity => requiredActivityId != null && requiredActivityId!.isNotEmpty;
}

class Task {
  final String id;
  final String type;
  final String question;
  final int order;
  final Map<String, dynamic> data;

  const Task({
    required this.id,
    required this.type,
    required this.question,
    required this.order,
    required this.data,
  });

  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      type: data['type'] ?? '',
      question: data['question'] ?? '',
      order: (data['order'] as num?)?.toInt() ?? 0,
      data: Map<String, dynamic>.from(data['data'] ?? {}),
    );
  }
}