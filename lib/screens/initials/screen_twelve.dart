// screen_twelve.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

/// ODD ONE OUT
/// Always 4 options. 3 belong to the shown category, 1 doesn't — the
/// student taps the one that doesn't belong. Fixed 2x2 grid instead of
/// ScreenOne's responsive column count, since the exercise only ever has
/// exactly 4 options and a 2x2 layout reads clearest for that count.
class ScreenTwelve extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect)? onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

  const ScreenTwelve({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.taskId,
    this.onTaskComplete,
    this.currentTaskNumber = 1,
    this.totalTasks = 1,
    this.collectionName = 'content',
    this.isPracticeRound = false,
  });

  @override
  State<ScreenTwelve> createState() => _ScreenTwelveState();
}

class _ScreenTwelveState extends State<ScreenTwelve> with RetryableTask {
  String category = '';
  List<Map<String, dynamic>> options = [];
  int oddIndex = -1;
  int selectedIndex = -1;

  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color greyAccent = Color(0xFF81C784);

  @override
  void initState() {
    super.initState();
    _fetchTask();
  }

  Future<void> _fetchTask() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units')
          .doc(widget.unitId)
          .collection('lessons')
          .doc(widget.lessonId)
          .collection('activities')
          .doc(widget.activityId)
          .collection('tasks')
          .doc(widget.taskId)
          .get();

      if (doc.exists) {
        final taskData = doc.data();
        if (taskData != null && taskData['type'] == 'odd_one_out') {
          final data = taskData['data'] as Map<String, dynamic>? ?? {};

          setState(() {
            category = data['category'] ?? '';
            options = List<Map<String, dynamic>>.from(data['options'] ?? []);
            oddIndex = data['oddIndex'] ?? -1;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching task: $e');
    }
  }

  void _handleSelection(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  void _checkAnswer() {
    final bool isCorrect = selectedIndex == oddIndex;

    TaskFeedback.fire(isCorrect);

    if (!isCorrect &&
        offerRetry(
          context: context,
          onRetry: () => setState(() => selectedIndex = -1),
        )) {
      return;
    }

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      onContinue: () {
        widget.onTaskComplete?.call(isCorrect);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundGradient = LinearGradient(
      colors: [Color(0xFFE8F5E9), Colors.white],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: backgroundGradient),
          child: SafeArea(
            child: options.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ResponsiveActivityShell(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: _handleClose,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.black87,
                                  size: 28,
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(30),
                                  ),
                                  child: LinearProgressIndicator(
                                    value: widget.currentTaskNumber / widget.totalTasks,
                                    backgroundColor: Colors.blueGrey,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      greenPrimary,
                                    ),
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.category_outlined,
                                color: Colors.black87,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Tap the one that doesn\'t belong',
                          style: TextStyle(fontSize: 20, color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: GridView.builder(
                              itemCount: options.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 1,
                              ),
                              itemBuilder: (context, index) {
                                final option = options[index];
                                final isSelected = selectedIndex == index;
                                return GestureDetector(
                                  onTap: () => _handleSelection(index),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    decoration: BoxDecoration(
                                      color: isSelected ? greenPrimary : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected ? greenPrimary : greyAccent,
                                        width: 4,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: option['image'].toString().endsWith('.svg') &&
                                                !option['image'].toString().contains('f_png')
                                            ? SvgPicture.network(
                                                option['image'],
                                                fit: BoxFit.contain,
                                                placeholderBuilder: (context) =>
                                                    const CircularProgressIndicator(),
                                              )
                                            : CachedNetworkImage(
                                                imageUrl: option['image'],
                                                placeholder: (_, __) =>
                                                    const CircularProgressIndicator(),
                                                errorWidget: (_, __, ___) =>
                                                    const Icon(Icons.error),
                                                fit: BoxFit.contain,
                                              ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 20,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: selectedIndex == -1 ? null : _checkAnswer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: greenPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 5,
                              ),
                              child: const Text(
                                'Check',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}