import 'package:flutter/material.dart';
import 'package:loringo_app/components/image_dialog.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/utils/image_service.dart';

class CreatePersonalizedTaskScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;
  final String? taskId;
  final Map<String, dynamic>? existingData;

  const CreatePersonalizedTaskScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.groupColor,
    this.taskId,
    this.existingData,
  });

  @override
  State<CreatePersonalizedTaskScreen> createState() => _CreatePersonalizedTaskScreenState();
}

class _CreatePersonalizedTaskScreenState extends State<CreatePersonalizedTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final Database db = Database();
  final imageService = ImageService();

  late TextEditingController questionController;
  late TextEditingController orderController;

  String selectedType = 'image_select';
  bool isLoading = false;

  // image_select: dynamic 3-4 options
  List<Map<String, dynamic>> options = [
    {'text': '', 'image': '', 'isCorrect': false},
    {'text': '', 'image': '', 'isCorrect': false},
    {'text': '', 'image': '', 'isCorrect': false},
  ];
  List<TextEditingController> textControllers = [];
  List<TextEditingController> imageControllers = [];
  List<Map<String, dynamic>?> pickedImages = [null, null, null];
  Map<String, dynamic>? reversePickedImage;

  // complete_the_chat: 3-4 options
  List<Map<String, dynamic>> completeChatOptions = [
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
  ];
  List<TextEditingController> completeChatControllers = [];

  // arrange: 3-6 word tiles
  List<String> arrangeWords = ['', '', ''];
  List<TextEditingController> arrangeControllers = [];

  // fill_blank: 3-4 options
  List<Map<String, dynamic>> fillBlankOptions = [
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
  ];
  List<TextEditingController> fillBlankControllers = [];

  // image_select_reverse: one image + 3-4 text options
  late TextEditingController imageUrlController;
  List<Map<String, dynamic>> reverseOptions = [
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
    {'text': '', 'isCorrect': false},
  ];
  List<TextEditingController> reverseOptionControllers = [];

  final List<String> taskTypes = [
    'image_select',
    'image_select_reverse',
    'complete_the_chat',
    'fill_blank',
    'arrange',
  ];

  String _getDisplayName(String taskType) {
    switch (taskType) {
      case 'image_select':
        return 'Image Select';
      case 'image_select_reverse':
        return 'Image Select Reverse';
      case 'complete_the_chat':
        return 'Complete the Chat';
      case 'fill_blank':
        return 'Fill in the Blank';
      case 'arrange':
        return 'Sentence Arrange';
      default:
        return taskType;
    }
  }

  @override
  void initState() {
    super.initState();
    questionController = TextEditingController(
      text: widget.existingData?['question'] ?? '',
    );
    orderController = TextEditingController(
      text: widget.existingData?['order']?.toString() ?? '',
    );
    selectedType = widget.existingData?['type'] ?? 'image_select';

    for (int i = 0; i < 3; i++) {
      textControllers.add(TextEditingController());
      imageControllers.add(TextEditingController());
      completeChatControllers.add(TextEditingController());
      arrangeControllers.add(TextEditingController());
      fillBlankControllers.add(TextEditingController());
    }

    imageUrlController = TextEditingController();
    for (int i = 0; i < 3; i++) {
      reverseOptionControllers.add(TextEditingController());
    }

    if (widget.existingData != null) {
      _loadExistingTaskData();
    }
  }

  void _loadExistingTaskData() {
    final data = widget.existingData!['data'] as Map<String, dynamic>?;
    if (data == null) return;

    if (selectedType == 'image_select') {
      questionController.text = data['word'] ?? '';
      final opts = data['options'] as List<dynamic>?;
      if (opts != null) {
        options.clear();
        for (var c in textControllers) c.dispose();
        textControllers.clear();
        for (var c in imageControllers) c.dispose();
        imageControllers.clear();
        pickedImages.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          options.add({'text': o['text'] ?? '', 'image': o['image'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
          textControllers.add(TextEditingController(text: o['text'] ?? ''));
          imageControllers.add(TextEditingController(text: o['image'] ?? ''));
          pickedImages.add(null);
        }
      }
    } else if (selectedType == 'image_select_reverse') {
      imageUrlController.text = data['image'] ?? '';
      questionController.text = data['question'] ?? widget.existingData!['question'] ?? '';
      final opts = data['options'] as List<dynamic>?;
      if (opts != null) {
        reverseOptions.clear();
        for (var c in reverseOptionControllers) c.dispose();
        reverseOptionControllers.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          reverseOptions.add({'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
          reverseOptionControllers.add(TextEditingController(text: o['text'] ?? ''));
        }
      }
    } else if (selectedType == 'fill_blank') {
      questionController.text = data['question'] ?? '';
      final opts = data['options'] as List<dynamic>?;
      if (opts != null) {
        fillBlankOptions.clear();
        for (var c in fillBlankControllers) c.dispose();
        fillBlankControllers.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          fillBlankOptions.add({'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
          fillBlankControllers.add(TextEditingController(text: o['text'] ?? ''));
        }
      }
    } else if (selectedType == 'arrange') {
      questionController.text = data['question'] ?? '';
      final answer = data['answer'] as List<dynamic>?;
      if (answer != null) {
        arrangeWords.clear();
        for (var c in arrangeControllers) c.dispose();
        arrangeControllers.clear();
        for (final word in answer) {
          arrangeWords.add(word.toString());
          arrangeControllers.add(TextEditingController(text: word.toString()));
        }
      }
    } else if (selectedType == 'complete_the_chat') {
      questionController.text = data['question'] ?? '';
      final opts = data['options'] as List<dynamic>?;
      if (opts != null) {
        completeChatOptions.clear();
        for (var c in completeChatControllers) c.dispose();
        completeChatControllers.clear();
        for (final opt in opts) {
          final o = opt as Map<String, dynamic>;
          completeChatOptions.add({'text': o['text'] ?? '', 'isCorrect': o['isCorrect'] ?? false});
          completeChatControllers.add(TextEditingController(text: o['text'] ?? ''));
        }
      }
    }
  }

  @override
  void dispose() {
    questionController.dispose();
    orderController.dispose();
    for (var c in textControllers) c.dispose();
    for (var c in imageControllers) c.dispose();
    for (var c in completeChatControllers) c.dispose();
    for (var c in arrangeControllers) c.dispose();
    for (var c in fillBlankControllers) c.dispose();
    imageUrlController.dispose();
    for (var c in reverseOptionControllers) c.dispose();
    super.dispose();
  }

  // image_select add/remove (min 3, max 4)
  void _addImageSelectOption() {
    if (options.length < 4) {
      setState(() {
        options.add({'text': '', 'image': '', 'isCorrect': false});
        textControllers.add(TextEditingController());
        imageControllers.add(TextEditingController());
        pickedImages.add(null);
      });
    }
  }

  void _removeImageSelectOption(int index) {
    if (options.length > 3) {
      setState(() {
        options.removeAt(index);
        textControllers[index].dispose();
        textControllers.removeAt(index);
        imageControllers[index].dispose();
        imageControllers.removeAt(index);
        pickedImages.removeAt(index);
      });
    }
  }

  // complete_the_chat add/remove (min 3, max 4)
  void _addCompleteChatOption() {
    if (completeChatOptions.length < 4) {
      setState(() {
        completeChatOptions.add({'text': '', 'isCorrect': false});
        completeChatControllers.add(TextEditingController());
      });
    }
  }

  void _removeCompleteChatOption(int index) {
    if (completeChatOptions.length > 3) {
      setState(() {
        completeChatOptions.removeAt(index);
        completeChatControllers[index].dispose();
        completeChatControllers.removeAt(index);
      });
    }
  }

  // arrange add/remove (min 3, max 6)
  void _addArrangeWord() {
    if (arrangeWords.length < 6) {
      setState(() {
        arrangeWords.add('');
        arrangeControllers.add(TextEditingController());
      });
    }
  }

  void _removeArrangeWord(int index) {
    if (arrangeWords.length > 3) {
      setState(() {
        arrangeWords.removeAt(index);
        arrangeControllers[index].dispose();
        arrangeControllers.removeAt(index);
      });
    }
  }

  // fill_blank add/remove (min 3, max 4)
  void _addFillBlankOption() {
    if (fillBlankOptions.length < 4) {
      setState(() {
        fillBlankOptions.add({'text': '', 'isCorrect': false});
        fillBlankControllers.add(TextEditingController());
      });
    }
  }

  void _removeFillBlankOption(int index) {
    if (fillBlankOptions.length > 3) {
      setState(() {
        fillBlankOptions.removeAt(index);
        fillBlankControllers[index].dispose();
        fillBlankControllers.removeAt(index);
      });
    }
  }

  // image_select_reverse add/remove (min 3, max 4)
  void _addReverseOption() {
    if (reverseOptions.length < 4) {
      setState(() {
        reverseOptions.add({'text': '', 'isCorrect': false});
        reverseOptionControllers.add(TextEditingController());
      });
    }
  }

  void _removeReverseOption(int index) {
    if (reverseOptions.length > 3) {
      setState(() {
        reverseOptions.removeAt(index);
        reverseOptionControllers[index].dispose();
        reverseOptionControllers.removeAt(index);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedType == 'image_select') {
      bool hasCorrect = false;
      for (int i = 0; i < options.length; i++) {
        final hasImage = pickedImages[i] != null || imageControllers[i].text.trim().isNotEmpty;
        if (textControllers[i].text.trim().isEmpty || !hasImage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Option ${i + 1} must have text and image')),
          );
          return;
        }
        if (options[i]['isCorrect'] == true) hasCorrect = true;
      }
      if (!hasCorrect) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please mark at least one option as correct')),
        );
        return;
      }
    }

    if (selectedType == 'image_select_reverse') {
      final hasImage = reversePickedImage != null || imageUrlController.text.trim().isNotEmpty;
      if (!hasImage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image is required')),
        );
        return;
      }
      bool hasCorrect = false;
      int filledOptions = 0;
      for (int i = 0; i < reverseOptions.length; i++) {
        if (reverseOptionControllers[i].text.isNotEmpty) filledOptions++;
        if (reverseOptions[i]['isCorrect'] == true) hasCorrect = true;
      }
      if (filledOptions < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must provide at least 3 options')),
        );
        return;
      }
      if (!hasCorrect) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please mark at least one option as correct')),
        );
        return;
      }
    }

    if (selectedType == 'fill_blank') {
      bool hasCorrect = false;
      int filledOptions = 0;
      for (int i = 0; i < fillBlankOptions.length; i++) {
        if (fillBlankControllers[i].text.isNotEmpty) filledOptions++;
        if (fillBlankOptions[i]['isCorrect'] == true) hasCorrect = true;
      }
      if (filledOptions < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must provide at least 3 options')),
        );
        return;
      }
      if (!hasCorrect) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please mark at least one option as correct')),
        );
        return;
      }
    }

    if (selectedType == 'arrange') {
      int filledWords = 0;
      for (int i = 0; i < arrangeWords.length; i++) {
        if (arrangeControllers[i].text.isNotEmpty) filledWords++;
      }
      if (filledWords < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must provide at least 3 words to arrange')),
        );
        return;
      }
    }

    if (selectedType == 'complete_the_chat') {
      bool hasCorrect = false;
      int filledOptions = 0;
      for (int i = 0; i < completeChatOptions.length; i++) {
        if (completeChatControllers[i].text.isNotEmpty) filledOptions++;
        if (completeChatOptions[i]['isCorrect'] == true) hasCorrect = true;
      }
      if (filledOptions < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must provide at least 3 options')),
        );
        return;
      }
      if (!hasCorrect) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please mark at least one option as correct')),
        );
        return;
      }
    }

    setState(() => isLoading = true);

    try {
      final taskId = widget.taskId ?? 'task_${DateTime.now().millisecondsSinceEpoch}';
      Map<String, dynamic> data = {};

      if (selectedType == 'image_select') {
        data['word'] = questionController.text.trim();
        data['options'] = [];
        for (int i = 0; i < options.length; i++) {
          final imageUrl = pickedImages[i] != null
              ? (pickedImages[i]!['displayUrl'] ?? pickedImages[i]!['imageUrl'])
              : imageControllers[i].text.trim();
          data['options'].add({
            'text': textControllers[i].text.trim(),
            'image': imageUrl,
            'isCorrect': options[i]['isCorrect'],
          });
        }
      } else if (selectedType == 'image_select_reverse') {
        final imageUrl = reversePickedImage != null
            ? (reversePickedImage!['displayUrl'] ?? reversePickedImage!['imageUrl'])
            : imageUrlController.text.trim();
        data['image'] = imageUrl;
        data['options'] = [];
        for (int i = 0; i < reverseOptions.length; i++) {
          if (reverseOptionControllers[i].text.isNotEmpty) {
            data['options'].add({
              'text': reverseOptionControllers[i].text.trim(),
              'isCorrect': reverseOptions[i]['isCorrect'],
            });
          }
        }
      } else if (selectedType == 'fill_blank') {
        data['question'] = questionController.text.trim();
        data['options'] = [];
        for (int i = 0; i < fillBlankOptions.length; i++) {
          if (fillBlankControllers[i].text.isNotEmpty) {
            data['options'].add({
              'text': fillBlankControllers[i].text.trim(),
              'isCorrect': fillBlankOptions[i]['isCorrect'],
            });
          }
        }
      } else if (selectedType == 'complete_the_chat') {
        data['question'] = questionController.text.trim();
        data['options'] = [];
        for (int i = 0; i < completeChatOptions.length; i++) {
          if (completeChatControllers[i].text.isNotEmpty) {
            data['options'].add({
              'text': completeChatControllers[i].text.trim(),
              'isCorrect': completeChatOptions[i]['isCorrect'],
            });
          }
        }
      } else if (selectedType == 'arrange') {
        data['question'] = questionController.text.trim();
        data['answer'] = [];
        for (int i = 0; i < arrangeWords.length; i++) {
          if (arrangeControllers[i].text.isNotEmpty) {
            data['answer'].add(arrangeControllers[i].text.trim());
          }
        }
      }

      // Dirty check in edit mode
      if (widget.taskId != null) {
        final orig = widget.existingData!;
        final origData = orig['data'] as Map<String, dynamic>? ?? {};
        final noChanges =
            selectedType == (orig['type'] as String? ?? '') &&
            questionController.text.trim() == (orig['question'] as String? ?? '') &&
            orderController.text.trim() == (orig['order']?.toString() ?? '') &&
            data.toString() == origData.toString();
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

        await db.updatePersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskId,
          type: selectedType,
          question: questionController.text.trim(),
          order: int.parse(orderController.text.trim()),
          data: data,
        );
      } else {
        await db.createPersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskId,
          type: selectedType,
          question: questionController.text.trim(),
          order: int.parse(orderController.text.trim()),
          data: data,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.taskId != null
                ? 'Changes saved'
                : 'Task created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.taskId != null ? 'Edit Task' : 'Create Task'),
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
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Task Type',
                  border: OutlineInputBorder(),
                ),
                items: taskTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(_getDisplayName(type)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedType = value!);
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: questionController,
                decoration: InputDecoration(
                  labelText: selectedType == 'image_select'
                      ? 'Word (e.g., "The colour Red")'
                      : selectedType == 'image_select_reverse'
                      ? 'Question (e.g., "What action is shown?")'
                      : selectedType == 'complete_the_chat'
                      ? 'Question (e.g., "What color is the sky?")'
                      : selectedType == 'arrange'
                      ? 'Sentence (e.g., "It\'s sunny outside")'
                      : selectedType == 'fill_blank'
                      ? 'Question (e.g., "I __ tired.")'
                      : 'Question',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: orderController,
                decoration: const InputDecoration(
                  labelText: 'Order',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // --- image_select (3-4 options, dynamic) ---
              if (selectedType == 'image_select') ...[
                const Divider(thickness: 2),
                Row(
                  children: [
                    const Text(
                      'Options (3-4 required)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (options.length < 4)
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)),
                        onPressed: _addImageSelectOption,
                        tooltip: 'Add option (max 4)',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(options.length, (index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Option ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Spacer(),
                            Checkbox(
                              value: options[index]['isCorrect'],
                              activeColor: const Color(0xFF4CAF50),
                              onChanged: (value) {
                                setState(() => options[index]['isCorrect'] = value ?? false);
                              },
                            ),
                            const Text('Correct'),
                            if (options.length > 3)
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () => _removeImageSelectOption(index),
                                tooltip: 'Remove',
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: textControllers[index],
                          decoration: const InputDecoration(
                            labelText: 'Text (e.g., "Red")',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: imageControllers[index],
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Image',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.image),
                              tooltip: 'Select from library',
                              onPressed: () async {
                                final selected = await showDialog(
                                  context: context,
                                  builder: (context) => SelectImageDialog(singleSelect: false),
                                );
                                if (selected != null) {
                                  setState(() {
                                    pickedImages[index] = selected as Map<String, dynamic>;
                                    imageControllers[index].text = selected['name'] ?? 'Selected';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Image selected successfully'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // --- image_select_reverse (one image + 3-4 text options) ---
              if (selectedType == 'image_select_reverse') ...[
                const Divider(thickness: 2),
                const Text(
                  'Image',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: imageUrlController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Image',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload),
                      onPressed: () async {
                        final selected = await showDialog(
                          context: context,
                          builder: (context) => SelectImageDialog(singleSelect: true),
                        );
                        if (selected != null) {
                          setState(() {
                            reversePickedImage = selected as Map<String, dynamic>;
                            imageUrlController.text = selected['name'] ?? 'Selected';
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Text Options (3-4 required)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (reverseOptions.length < 4)
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)),
                        onPressed: _addReverseOption,
                        tooltip: 'Add option (max 4)',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(reverseOptions.length, (index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Option ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Spacer(),
                            Checkbox(
                              value: reverseOptions[index]['isCorrect'],
                              activeColor: const Color(0xFF4CAF50),
                              onChanged: (value) {
                                setState(() => reverseOptions[index]['isCorrect'] = value ?? false);
                              },
                            ),
                            const Text('Correct'),
                            if (reverseOptions.length > 3)
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeReverseOption(index),
                                tooltip: 'Remove',
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: reverseOptionControllers[index],
                          decoration: const InputDecoration(
                            labelText: 'Text (e.g., "Stand up")',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // --- complete_the_chat (3-4 options) ---
              if (selectedType == 'complete_the_chat') ...[
                const Divider(thickness: 2),
                Row(
                  children: [
                    const Text(
                      'Options (3-4 required)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (completeChatOptions.length < 4)
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)),
                        onPressed: _addCompleteChatOption,
                        tooltip: 'Add option',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(completeChatOptions.length, (index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Option ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Spacer(),
                            Checkbox(
                              value: completeChatOptions[index]['isCorrect'],
                              onChanged: (value) {
                                setState(() => completeChatOptions[index]['isCorrect'] = value ?? false);
                              },
                            ),
                            const Text('Correct'),
                            if (completeChatOptions.length > 3)
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () => _removeCompleteChatOption(index),
                                tooltip: 'Remove option',
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: completeChatControllers[index],
                          decoration: const InputDecoration(
                            labelText: 'Text (e.g., "It is blue")',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // --- fill_blank (3-4 options, no subtitle) ---
              if (selectedType == 'fill_blank') ...[
                const Divider(thickness: 2),
                Row(
                  children: [
                    const Text(
                      'Options (3-4)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (fillBlankOptions.length < 4)
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)),
                        onPressed: _addFillBlankOption,
                        tooltip: 'Add option (max 4)',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(fillBlankOptions.length, (index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Option ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Spacer(),
                            Checkbox(
                              value: fillBlankOptions[index]['isCorrect'],
                              onChanged: (value) {
                                setState(() => fillBlankOptions[index]['isCorrect'] = value ?? false);
                              },
                            ),
                            const Text('Correct'),
                            if (fillBlankOptions.length > 3)
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () => _removeFillBlankOption(index),
                                tooltip: 'Remove option',
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: fillBlankControllers[index],
                          decoration: InputDecoration(
                            labelText: 'Option ${index + 1} (e.g., "is", "are", "am")',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // --- arrange / Sentence Arrange (3-6 word tiles, no subtitle) ---
              if (selectedType == 'arrange') ...[
                const Divider(thickness: 2),
                Row(
                  children: [
                    const Text(
                      'Word Tiles (3-6 words)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (arrangeWords.length < 6)
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF4CAF50)),
                        onPressed: _addArrangeWord,
                        tooltip: 'Add word (max 6)',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(arrangeWords.length, (index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: arrangeControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Word ${index + 1} (e.g., "It\'s")',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                        if (arrangeWords.length > 3)
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () => _removeArrangeWord(index),
                            tooltip: 'Remove word',
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                const Text(
                  'Words should be in the correct sentence order.',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],

              if (selectedType != 'image_select' &&
                  selectedType != 'image_select_reverse' &&
                  selectedType != 'fill_blank' &&
                  selectedType != 'arrange' &&
                  selectedType != 'complete_the_chat')
                const Text(
                  'Note: Task data should be managed directly in Firebase Console for now.',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.groupColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                          widget.taskId != null ? 'Update' : 'Create',
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