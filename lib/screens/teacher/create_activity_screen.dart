import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedActivityScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final Color groupColor;
  final String? activityId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedActivityScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.groupColor,
    this.activityId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedActivityScreen> createState() =>
      _CreatePersonalizedActivityScreenState();
}

class _CreatePersonalizedActivityScreenState
    extends State<CreatePersonalizedActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database db = Database();

  late TextEditingController titleController;
  late TextEditingController orderController;
  late TextEditingController xpBaseController;

  bool isLoading = false;
  String? requiredActivityId;
  String difficulty = 'easy';
  List<Map<String, dynamic>> existingActivities = [];

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(
      text: widget.existingData?['title'] ?? '',
    );
    orderController = TextEditingController(
      text: widget.existingData?['order']?.toString() ?? '',
    );
    xpBaseController = TextEditingController(
      text: widget.existingData?['xpBase']?.toString() ?? '10',
    );
    requiredActivityId = widget.existingData?['requiredActivityId'];
    
    // Set initial difficulty based on XP
    final initialXp = int.tryParse(xpBaseController.text) ?? 25;
    difficulty = _getDifficultyFromXP(initialXp);
    
    // Listen to XP changes to update difficulty
    xpBaseController.addListener(() {
      final xp = int.tryParse(xpBaseController.text);
      if (xp != null) {
        setState(() {
          difficulty = _getDifficultyFromXP(xp);
        });
      }
    });
    
    _loadExistingActivities();
  }

  Future<void> _loadExistingActivities() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('personalizedContent')
          .doc(widget.contentId)
          .collection('units')
          .doc(widget.unitId)
          .collection('lessons')
          .doc(widget.lessonId)
          .collection('activities')
          .orderBy('order')
          .get();

      setState(() {
        existingActivities = snapshot.docs
            .where((doc) => doc.id != widget.activityId)
            .map(
              (doc) => {
                'id': doc.id,
                'title': doc.data()['title'] ?? 'Untitled',
                'order': doc.data()['order'] ?? 0,
              },
            )
            .toList();
      });
    } catch (e) {
      print('Error loading activities: $e');
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    orderController.dispose();
    xpBaseController.dispose();
    super.dispose();
  }

  String _getDifficultyFromXP(int xp) {
    if (xp >= 0 && xp <= 15) {
      return 'easy';
    } else if (xp >= 16 && xp <= 30) {
      return 'medium';
    } else if (xp >= 31 && xp <= 50) {
      return 'hard';
    }
    return 'easy';
  }

  Color _getDifficultyColor(String diff) {
    switch (diff) {
      case 'easy':
        return const Color(0xFF4CAF50); // Green
      case 'medium':
        return const Color(0xFFFFA726); // Orange
      case 'hard':
        return const Color(0xFFEF5350); // Red
      default:
        return Colors.grey;
    }
  }

  String _getDifficultyLabel(String diff) {
    switch (diff) {
      case 'easy':
        return '🟢 Easy (0-15 XP)';
      case 'medium':
        return '🟡 Medium (16-30 XP)';
      case 'hard':
        return '🔴 Hard (31-50 XP)';
      default:
        return 'Unknown';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final activityId =
          widget.activityId ??
          'activity_${DateTime.now().millisecondsSinceEpoch}';

      if (widget.activityId == null) {
        await db.createPersonalizedActivity(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: activityId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
          requiredActivityId: requiredActivityId,
          xpBase: int.parse(xpBaseController.text.trim()),
          difficulty: difficulty,
        );
      } else {
        // Dirty check (edit mode)
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origOrder = widget.existingData?['order']?.toString() ?? '';
        final origXp = widget.existingData?['xpBase']?.toString() ?? '10';
        final origRequired = widget.existingData?['requiredActivityId'] as String?;
        final noChanges =
            titleController.text.trim() == origTitle &&
            orderController.text.trim() == origOrder &&
            xpBaseController.text.trim() == origXp &&
            requiredActivityId == origRequired;
        if (noChanges) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No changes made'),
              backgroundColor: Colors.grey,
            ),
          );
          return;
        }
        await db.updatePersonalizedActivity(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: activityId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
          requiredActivityId: requiredActivityId,
          xpBase: int.parse(xpBaseController.text.trim()),
          difficulty: difficulty,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.activityId == null
                  ? '✅ Activity created successfully!'
                  : '✅ Activity updated successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.activityId != null ? 'Edit Activity' : 'Create Activity',
        ),
        backgroundColor: widget.groupColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section with group color accent
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.groupColor.withOpacity(0.1),
                      widget.groupColor.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.groupColor.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.groupColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.movie,
                        color: widget.groupColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.activityId != null ? 'Editing Activity' : 'New Activity',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.groupColor,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Groups multiple tasks together',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Title field
              TextFormField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Activity Title',
                  hintText: 'e.g., Listening Exercise',
                  prefixIcon: Icon(Icons.title, color: widget.groupColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              // Order field
              TextFormField(
                controller: orderController,
                decoration: InputDecoration(
                  labelText: 'Display Order',
                  hintText: '1, 2, 3...',
                  prefixIcon: Icon(Icons.sort, color: widget.groupColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an order number';
                  }
                  if (int.tryParse(value.trim()) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              // XP field
              TextFormField(
                controller: xpBaseController,
                decoration: InputDecoration(
                  labelText: 'Base XP Reward',
                  hintText: 'e.g., 25',
                  prefixIcon: Icon(Icons.stars, color: widget.groupColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Points earned upon completion (0-50)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter base XP';
                  }
                  if (int.tryParse(value.trim()) == null) {
                    return 'Please enter a valid number';
                  }
                  final xp = int.parse(value.trim());
                  if (xp < 0 || xp > 50) {
                    return 'XP must be between 0 and 50';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Difficulty indicator
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(difficulty).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getDifficultyColor(difficulty).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      difficulty == 'easy'
                          ? Icons.trending_down
                          : difficulty == 'medium'
                              ? Icons.trending_flat
                              : Icons.trending_up,
                      color: _getDifficultyColor(difficulty),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Difficulty Level',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getDifficultyLabel(difficulty),
                          style: TextStyle(
                            fontSize: 14,
                            color: _getDifficultyColor(difficulty),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Required activity dropdown
              DropdownButtonFormField<String>(
                value: requiredActivityId,
                decoration: InputDecoration(
                  labelText: 'Prerequisites (Optional)',
                  hintText: 'Select activity to unlock this one',
                  prefixIcon: Icon(Icons.lock, color: widget.groupColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: widget.groupColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Leave empty if this is the first activity',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('None (Always Unlocked)'),
                  ),
                  ...existingActivities.map((activity) {
                    return DropdownMenuItem<String>(
                      value: activity['id'],
                      child: Text('${activity['order']}. ${activity['title']}'),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    requiredActivityId = value;
                  });
                },
              ),
              const SizedBox(height: 32),
              // Submit button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.groupColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.activityId != null
                              ? 'UPDATE ACTIVITY'
                              : 'CREATE ACTIVITY',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
