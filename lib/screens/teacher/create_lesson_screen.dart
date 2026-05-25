import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedLessonScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final Color groupColor;
  final String? lessonId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedLessonScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.groupColor,
    this.lessonId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedLessonScreen> createState() =>
      _CreatePersonalizedLessonScreenState();
}

class _CreatePersonalizedLessonScreenState
    extends State<CreatePersonalizedLessonScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database db = Database();

  late TextEditingController titleController;
  late TextEditingController orderController;

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(
      text: widget.existingData?['title'] ?? '',
    );
    orderController = TextEditingController(
      text: widget.existingData?['order']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    orderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final lessonId =
          widget.lessonId ?? 'lesson_${DateTime.now().millisecondsSinceEpoch}';

      if (widget.lessonId != null) {
        // Dirty check
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origOrder = widget.existingData?['order']?.toString() ?? '';
        if (titleController.text.trim() == origTitle &&
            orderController.text.trim() == origOrder) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No changes made'),
              backgroundColor: Colors.grey,
            ),
          );
          return;
        }
        // Update existing
        await db.updatePersonalizedLesson(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: lessonId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Lesson updated successfully')),
          );
        }
      } else {
        // Create new
        await db.createPersonalizedLesson(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: lessonId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Lesson created successfully')),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.lessonId == null ? 'Create Lesson' : 'Edit Lesson'),
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
                        Icons.school,
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
                            widget.lessonId != null ? 'Editing Lesson' : 'New Lesson',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.groupColor,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Create engaging lessons with tasks',
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
                  labelText: 'Lesson Title',
                  hintText: 'e.g., Past Tense Basics',
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
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Title is required' : null,
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
                  helperText: 'Lessons appear in numeric order',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Order is required';
                  if (int.tryParse(value!) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
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
                          widget.lessonId != null
                              ? 'UPDATE LESSON'
                              : 'CREATE LESSON',
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
