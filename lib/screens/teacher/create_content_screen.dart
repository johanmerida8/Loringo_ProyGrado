// create_content_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedContentScreen extends StatefulWidget {
  final String? contentId;
  final Map<String, dynamic>? existingData;
  final Color groupColor;

  const CreatePersonalizedContentScreen({
    super.key,
    this.contentId,
    this.existingData,
    this.groupColor = const Color(0xFF4CAF50),
  });

  @override
  State<CreatePersonalizedContentScreen> createState() =>
      _CreatePersonalizedContentScreenState();
}

class _CreatePersonalizedContentScreenState
    extends State<CreatePersonalizedContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = Database();

  late TextEditingController titleController;
  late TextEditingController descriptionController;
  late TextEditingController orderController;
  String selectedAgeGroup = '5-6 years';
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(
      text: widget.existingData?['title'] ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.existingData?['description'] ?? '',
    );
    orderController = TextEditingController(
      text: widget.existingData?['order']?.toString() ?? '',
    );
    selectedAgeGroup = widget.existingData?['ageGroup'] ?? '5-6 years';
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    orderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final teacherId = FirebaseAuth.instance.currentUser?.uid;
      if (teacherId == null) {
        throw Exception('No user authenticated');
      }

      final contentId =
          widget.contentId ??
          'personal_content_${DateTime.now().millisecondsSinceEpoch}';

      if (widget.contentId != null) {
        // Dirty check — skip save if nothing changed
        final origTitle = widget.existingData?['title'] as String? ?? '';
        final origDesc = widget.existingData?['description'] as String? ?? '';
        final origAge = widget.existingData?['ageGroup'] as String? ?? '5-6 years';
        final origOrder = widget.existingData?['order']?.toString() ?? '';
        final noChanges =
            titleController.text.trim() == origTitle &&
            descriptionController.text.trim() == origDesc &&
            selectedAgeGroup == origAge &&
            orderController.text.trim() == origOrder;
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

        await _db.updatePersonalizedContent(
          contentId: contentId,
          title: titleController.text.trim(),
          description: descriptionController.text.trim(),
          ageGroup: selectedAgeGroup,
          order: int.parse(orderController.text.trim()),
        );
      } else {
        await _db.createPersonalizedContent(
          contentId: contentId,
          title: titleController.text.trim(),
          description: descriptionController.text.trim(),
          ageGroup: selectedAgeGroup,
          order: int.parse(orderController.text.trim()),
          teacherId: teacherId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.contentId != null
                  ? 'Content updated successfully!'
                  : 'Content created successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
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
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.contentId != null ? 'Edit Content' : 'Create New Content',
        ),
        backgroundColor: widget.groupColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create your content here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g., Present Tense Verbs, Numbers 1-100',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Brief description of the content',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Description is required' : null,
              ),
              const SizedBox(height: 20),
              Text(
                'Age Group',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('5-6 years'),
                value: '5-6 years',
                groupValue: selectedAgeGroup,
                onChanged: (value) {
                  setState(() => selectedAgeGroup = value!);
                },
                activeColor: widget.groupColor,
              ),
              RadioListTile<String>(
                title: const Text('7-8 years'),
                value: '7-8 years',
                groupValue: selectedAgeGroup,
                onChanged: (value) {
                  setState(() => selectedAgeGroup = value!);
                },
                activeColor: widget.groupColor,
              ),
              RadioListTile<String>(
                title: const Text('9+ years'),
                value: '9+ years',
                groupValue: selectedAgeGroup,
                onChanged: (value) {
                  setState(() => selectedAgeGroup = value!);
                },
                activeColor: widget.groupColor,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: orderController,
                decoration: InputDecoration(
                  labelText: 'Order',
                  hintText: 'Display order (1, 2, 3...)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.sort),
                ),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Order is required' : null,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.groupColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          widget.contentId != null ? 'Update' : 'Create',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}