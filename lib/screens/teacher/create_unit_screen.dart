import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class CreatePersonalizedUnitScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String? unitId;
  final Map<String, dynamic>? existingData;
  final Color groupColor; // Add this

  const CreatePersonalizedUnitScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.groupColor, // Add this
    this.unitId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedUnitScreen> createState() =>
      _CreatePersonalizedUnitScreenState();
}

class _CreatePersonalizedUnitScreenState
    extends State<CreatePersonalizedUnitScreen> {
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
      final unitId =
          widget.unitId ?? 'unit_${DateTime.now().millisecondsSinceEpoch}';

      if (widget.unitId != null) {
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
        await db.updatePersonalizedUnit(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: unitId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
        );
      } else {
        // Create new
        await db.createPersonalizedUnit(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: unitId,
          title: titleController.text.trim(),
          order: int.parse(orderController.text.trim()),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.unitId != null
                  ? '✅ Unit updated successfully!'
                  : '✅ Unit created successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.unitId != null ? 'Edit Unit' : 'Create Unit'),
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
                        Icons.layers,
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
                            widget.unitId != null ? 'Edit Unit' : 'New Unit',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: widget.groupColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Define the unit structure',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
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
                  labelText: 'Unit Title',
                  hintText: 'e.g., Introduction to Numbers',
                  prefixIcon: Icon(Icons.title, color: widget.groupColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.groupColor, width: 2),
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
                  labelText: 'Order',
                  hintText: '1, 2, 3...',
                  prefixIcon: Icon(Icons.sort, color: widget.groupColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.groupColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Order is required' : null,
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.unitId != null ? 'Update Unit' : 'Create Unit',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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