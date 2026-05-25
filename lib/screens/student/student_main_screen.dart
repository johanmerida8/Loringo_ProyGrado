import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/screens/initials/activity_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_play_screen.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:lottie/lottie.dart';

/// Student Main Screen with Bottom Navigation
/// Shows: Home (Activities), Group Info, Settings
class StudentMainScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentAvatar;

  const StudentMainScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentAvatar,
  });

  @override
  State<StudentMainScreen> createState() => _StudentMainScreenState();
}

class _StudentMainScreenState extends State<StudentMainScreen> {
  int _currentIndex = 0;
  String? groupId;
  String? groupName;
  
  // Biometric state
  bool isBiometricSupported = false;
  bool isBiometricEnabled = false;
  List<BiometricType> availableBiometrics = [];
  String biometricTypeName = 'Biometrics';

  @override
  void initState() {
    super.initState();
    _loadStudentGroup();
    _initBiometrics();
  }

  Future<void> _loadStudentGroup() async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();

      if (studentDoc.exists) {
        final studentData = studentDoc.data();
        final fetchedGroupId = studentData?['groupId'] as String?;

        if (fetchedGroupId != null) {
          final groupDoc = await FirebaseFirestore.instance
              .collection('teacherGroups')
              .doc(fetchedGroupId)
              .get();

          if (groupDoc.exists) {
            final groupData = groupDoc.data();
            setState(() {
              groupId = fetchedGroupId;
              groupName = groupData?['name'] ?? 'Unknown Group';
            });
          }
        }
      }
    } catch (e) {
      print('Error loading student group: $e');
    }
  }

  Future<void> _initBiometrics() async {
    try {
      final isSupported = await BiometricService.isDeviceSupported();
      final canCheck = await BiometricService.canCheckBiometrics();
      final available = await BiometricService.getAvailableBiometrics();
      final isEnabled = await BiometricService.isBiometricEnabled(widget.studentId);

      setState(() {
        isBiometricSupported = isSupported && canCheck;
        availableBiometrics = available;
        biometricTypeName = BiometricService.getBiometricTypeName(available);
        isBiometricEnabled = isEnabled;
      });
    } catch (e) {
      print('Error initializing biometrics: $e');
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Verify biometric before enabling
      final authenticated = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric login',
      );

      if (authenticated) {
        await BiometricService.setBiometricEnabled(
          userId: widget.studentId,
          enabled: true,
        );
        setState(() => isBiometricEnabled = true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $biometricTypeName login enabled'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Authentication failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      await BiometricService.setBiometricEnabled(
        userId: widget.studentId,
        enabled: false,
      );
      setState(() => isBiometricEnabled = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$biometricTypeName login disabled'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F5E9), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: IndexedStack(
          index: _currentIndex,
          children: [
            // Home Tab - Activities
            _buildActivitiesTab(),
            // Group Tab - Student Info
            _buildGroupTab(),
            // League Tab
            _buildLeagueTab(),
            // Settings Tab
            _buildSettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          AppNavItem(icon: Icons.home_rounded, label: 'Home'),
          AppNavItem(icon: Icons.groups_rounded, label: 'Group'),
          AppNavItem(icon: Icons.emoji_events_rounded, label: 'League'),
          AppNavItem(icon: Icons.settings_rounded, label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildActivitiesTab() {
    return SafeArea(
      child: Column(
        children: [
          // Loringo Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            child: Row(
              children: [
                const Text(
                  "Loringo",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.settings,
                    color: Color(0xFF4CAF50),
                  ),
                  onSelected: (value) async {
                    if (value == 'logout') {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Logout'),
                          content: const Text('Are you sure you want to logout?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await StudentAuthService.clearStudentLogin();
                                if (context.mounted) {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginOrRegister(),
                                    ),
                                    (route) => false,
                                  );
                                }
                              },
                              child: const Text(
                                'Logout',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: Colors.redAccent,
                        ),
                        title: Text('Logout'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // User Info Card
          Container(
            margin: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF4CAF50),
                  backgroundImage: widget.studentAvatar != null
                      ? AssetImage(widget.studentAvatar!)
                      : null,
                  child: widget.studentAvatar == null
                      ? const Icon(Icons.person, color: Colors.white, size: 30)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Hello, ${widget.studentName}!',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        groupName ?? 'Loading...',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Activities List
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadAssignedContent(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_rounded,
                              size: 100,
                              color: Color(0xFF4CAF50),
                            ),
                            SizedBox(height: 24),
                            Text(
                              'No Activities Available',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Contact your teacher to add learning activities',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final activities = snapshot.data!;

                  // Pre-pass: count items per unit and record unit order
                  final Map<String, int> unitItemCounts = {};
                  final List<String> unitOrder = [];
                  for (final item in activities) {
                    final uid = item['unitId'] as String? ?? '';
                    if (!unitItemCounts.containsKey(uid)) {
                      unitOrder.add(uid);
                      unitItemCounts[uid] = 0;
                    }
                    unitItemCounts[uid] = unitItemCounts[uid]! + 1;
                  }

                  final List<String> mascots = [
                    'assets/animation/animation.json',
                    'assets/animation/animation3.json',
                    'assets/animation/animation1.json',
                    'assets/animation/animation2.json',
                  ];

                  int activityIndex = 0;
                  final Map<String, int> unitProgress = {};
                  final List<Widget> activityWidgets = [];

                  for (final item in activities) {
                    final uid = item['unitId'] as String? ?? '';
                    final count = unitItemCounts[uid] ?? 0;
                    final progress = unitProgress[uid] ?? 0;
                    final midPoint = count ~/ 2;
                    final unitOrdinal = unitOrder.indexOf(uid) + 1;
                    final mascotPath =
                        mascots[(unitOrdinal - 1) % mascots.length];

                    final bool isLeft = activityIndex % 2 == 0;
                    final int levelNum = activityIndex + 1;
                    activityIndex++;

                    final bool isUnlocked = item['isUnlocked'] ?? false;
                    final String itemType = item['type'] ?? 'activity';
                    final bool isQuiz = itemType == 'quiz';
                    final bool isCompleted = item['isCompleted'] ?? false;
                    final int stars = item['stars'] ?? 0;

                    activityWidgets.add(Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: isLeft
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.end,
                        children: [
                          Column(
                            children: [
                              GestureDetector(
                                onTap: isUnlocked
                                    ? () {
                                        if (isQuiz) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => QuizPlayScreen(
                                                contentId: item['contentId'],
                                                unitId: item['unitId'],
                                                lessonId: item['lessonId'],
                                                quizId: item['quizId'],
                                                quizTitle: item['title'],
                                                collectionName:
                                                    'personalizedContent',
                                                studentId: widget.studentId,
                                              ),
                                            ),
                                          );
                                        } else {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ActivityPlayScreen(
                                                contentId: item['contentId'],
                                                unitId: item['unitId'],
                                                lessonId: item['lessonId'],
                                                activityId: item['activityId'],
                                                activityTitle: item['title'],
                                                studentId: widget.studentId,
                                                xpBase: item['xpBase'] ?? 100,
                                                bonusXP: item['bonusXP'] ?? 0,
                                                collectionName:
                                                    'personalizedContent',
                                              ),
                                            ),
                                          ).then((_) => setState(() {}));
                                        }
                                      }
                                    : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: isUnlocked
                                        ? (isQuiz
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFFFB74D),
                                                  Color(0xFFFF9800),
                                                ],
                                              )
                                            : const LinearGradient(
                                                colors: [
                                                  Color(0xFF4CAF50),
                                                  Color(0xFF81C784),
                                                ],
                                              ))
                                        : LinearGradient(
                                            colors: [
                                              Colors.grey[400]!,
                                              Colors.grey[600]!,
                                            ],
                                          ),
                                    border: Border.all(
                                        color: Colors.white, width: 4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 12,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  width: 80,
                                  height: 80,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isUnlocked
                                              ? (isQuiz
                                                  ? Icons.quiz
                                                  : Icons.star)
                                              : Icons.lock,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        const SizedBox(height: 4),
                                        if (isQuiz && isCompleted)
                                          Text(
                                            _getStarDisplay(stars),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          )
                                        else
                                          Text(
                                            isQuiz
                                                ? 'Quiz'
                                                : 'Level $levelNum',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 140,
                                child: Text(
                                  item['title'],
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isUnlocked
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ));

                    // Insert mascot at midpoint of each unit; skip empty units
                    if (count > 0 && progress == midPoint) {
                      activityWidgets.add(Center(
                        child: Lottie.asset(mascotPath,
                            width: 130, height: 130),
                      ));
                    }

                    unitProgress[uid] = progress + 1;
                  }

                  return SingleChildScrollView(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      children: activityWidgets,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Student Avatar
              CircleAvatar(
                radius: 60,
                backgroundColor: const Color(0xFF4CAF50),
                backgroundImage: widget.studentAvatar != null
                    ? AssetImage(widget.studentAvatar!)
                    : null,
                child: widget.studentAvatar == null
                    ? const Icon(Icons.person, size: 60, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 24),

              // Student Name
              Text(
                widget.studentName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Student',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 40),

              // Group Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withOpacity(0.3),
                      offset: const Offset(0, 4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.groups_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'My Group',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      groupName ?? 'No group assigned',
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Motivational Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: const Offset(0, 4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      size: 48,
                      color: Color(0xFFFE5D26),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Keep Learning!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFE5D26),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You\'re doing great! Complete more activities to improve your skills.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildLeagueTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('students')
              .doc(widget.studentId)
              .snapshots(),
          builder: (context, studentSnap) {
            // Also stream progress for activity/quiz counts
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('students')
                  .doc(widget.studentId)
                  .collection('progress')
                  .snapshots(),
              builder: (context, progressSnap) {
                final int totalXP = studentSnap.hasData && studentSnap.data!.exists
                    ? (((studentSnap.data!.data() as Map<String, dynamic>)['xp']) as num? ?? 0).toInt()
                    : 0;

                int activitiesCompleted = 0;
                int quizzesCompleted = 0;
                if (progressSnap.hasData) {
                  for (final doc in progressSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['isCompleted'] == true) {
                      if (data.containsKey('activityId')) {
                        activitiesCompleted++;
                      } else if (data.containsKey('quizId')) {
                        quizzesCompleted++;
                      }
                    }
                  }
                }

            // League level thresholds
            final leagueData = _getLeagueLevel(totalXP);
            final String leagueName = leagueData['name'] as String;
            final int leagueMin = leagueData['min'] as int;
            final int leagueMax = leagueData['max'] as int;
            final Color leagueColor = leagueData['color'] as Color;
            final String? leagueImage = leagueData['image'] as String?;
            final double progress = leagueMax > leagueMin
                ? ((totalXP - leagueMin) / (leagueMax - leagueMin)).clamp(0.0, 1.0)
                : 1.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                leagueColor,
                                leagueColor.withOpacity(0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: leagueColor.withOpacity(0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: leagueImage != null
                              ? Image.asset(
                                  leagueImage,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.contain,
                                )
                              : Icon(Icons.shield_rounded,
                                  size: 52, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          leagueName,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: leagueColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.studentName,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // XP Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total XP',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: leagueColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                leagueName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: leagueColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$totalXP',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: leagueColor,
                                height: 1,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8, left: 6),
                              child: Text(
                                'XP',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Progress bar to next league
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$leagueMin XP',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            Text(
                              leagueMax == 999999
                                  ? 'Max League'
                                  : '$leagueMax XP',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 12,
                            backgroundColor: Colors.grey[200],
                            valueColor:
                                AlwaysStoppedAnimation<Color>(leagueColor),
                          ),
                        ),
                        if (leagueMax < 999999) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${leagueMax - totalXP} XP to next league',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: _leagueStat(
                          icon: Icons.star_rounded,
                          label: 'Activities',
                          value: '$activitiesCompleted',
                          color: const Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _leagueStat(
                          icon: Icons.quiz_rounded,
                          label: 'Quizzes',
                          value: '$quizzesCompleted',
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _leagueStat(
                          icon: Icons.bolt_rounded,
                          label: 'Total',
                          value: '${activitiesCompleted + quizzesCompleted}',
                          color: const Color(0xFFFF9800),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // League Tiers info
                  const Text(
                    'League Tiers',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._leagueTiers().map((tier) {
                    final bool isCurrent = tier['name'] == leagueName;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? (tier['color'] as Color).withOpacity(0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: isCurrent
                            ? Border.all(
                                color: (tier['color'] as Color).withOpacity(0.5),
                                width: 2)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: (tier['image'] as String?) != null
                                ? Image.asset(
                                    tier['image'] as String,
                                    fit: BoxFit.contain,
                                  )
                                : Icon(Icons.shield_rounded,
                                    color: tier['color'] as Color, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tier['name'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isCurrent
                                        ? tier['color'] as Color
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  tier['range'] as String,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: tier['color'] as Color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _leagueStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Map<String, dynamic> _getLeagueLevel(int xp) {
    for (final tier in _leagueTiers()) {
      if (xp >= (tier['min'] as int) && xp < (tier['max'] as int)) {
        return tier;
      }
    }
    return _leagueTiers().last;
  }

  List<Map<String, dynamic>> _leagueTiers() => [
        {
          'name': 'Starter',
          'min': 0,
          'max': 200,
          'range': '0 – 199 XP',
          'color': const Color(0xFF9E9E9E),
          'image': null,
        },
        {
          'name': 'Bronze',
          'min': 200,
          'max': 500,
          'range': '200 – 499 XP',
          'color': const Color(0xFFCD7F32),
          'image': 'assets/leagues/bronze-league.png',
        },
        {
          'name': 'Silver',
          'min': 500,
          'max': 1000,
          'range': '500 – 999 XP',
          'color': const Color(0xFF78909C),
          'image': 'assets/leagues/silver-league.png',
        },
        {
          'name': 'Gold',
          'min': 1000,
          'max': 2000,
          'range': '1000 – 1999 XP',
          'color': const Color(0xFFFFB300),
          'image': 'assets/leagues/gold-league.png',
        },
        {
          'name': 'Platinum',
          'min': 2000,
          'max': 4000,
          'range': '2000 – 3999 XP',
          'color': const Color(0xFF00BCD4),
          'image': 'assets/leagues/platinum-league.png',
        },
        {
          'name': 'Diamond',
          'min': 4000,
          'max': 999999,
          'range': '4000+ XP',
          'color': const Color(0xFF1565C0),
          'image': 'assets/leagues/diamond-league.png',
        },
      ];

  Widget _buildSettingsTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(height: 40),

            // Biometric Authentication Toggle
            if (isBiometricSupported)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    availableBiometrics.contains(BiometricType.face)
                        ? Icons.face_rounded
                        : Icons.fingerprint_rounded,
                    color: const Color(0xFF4CAF50),
                  ),
                ),
                title: Text(
                  '$biometricTypeName Login',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text('Quick and secure login'),
                trailing: Switch(
                  value: isBiometricEnabled,
                  onChanged: _toggleBiometric,
                  activeColor: const Color(0xFF4CAF50),
                ),
              ),

            if (isBiometricSupported)
              const SizedBox(height: 16),

            // Refresh Button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF4CAF50),
                ),
              ),
              title: const Text(
                'Refresh',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('Reload your activities'),
              onTap: () {
                setState(() {
                  _loadStudentGroup();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Refreshed!'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Logout Button
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.red,
                ),
              ),
              title: const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
              subtitle: const Text('Return to login screen'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context); // Close dialog
                          
                          // Clear student login state
                          await StudentAuthService.clearStudentLogin();
                          
                          // Navigate to login screen
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginOrRegister(),
                              ),
                              (route) => false,
                            );
                          }
                        },
                        child: const Text(
                          'Logout',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const Spacer(),

            // Version Info
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.school_rounded,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loringo Student',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      )
      )
    );
  }

  Future<List<Map<String, dynamic>>> _loadAssignedContent() async {
    try {
      List<Map<String, dynamic>> allItems = [];

      if (groupId == null) {
        return [];
      }

      // Get approved content assigned to this group
      final contentSnap = await FirebaseFirestore.instance
          .collection('personalizedContent')
          .where('assignedTo', arrayContains: groupId)
          .where('status', isEqualTo: 'approved')
          .get();

      // Sort by order
      final contentDocs = contentSnap.docs.toList()
        ..sort((a, b) {
          final ao = (a.data()['order'] as num? ?? 0).toInt();
          final bo = (b.data()['order'] as num? ?? 0).toInt();
          return ao.compareTo(bo);
        });

      // Load student progress from Firebase
      Set<String> completedActivities = {};
      Map<String, dynamic> completedQuizzes = {};

      try {
        final progressSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .doc(widget.studentId)
            .collection('progress')
            .get();

        for (var progressDoc in progressSnapshot.docs) {
          final progressData = progressDoc.data();
          if (progressData['isCompleted'] == true) {
            if (progressData.containsKey('activityId')) {
              completedActivities.add(progressData['activityId']);
            } else if (progressData.containsKey('quizId')) {
              completedQuizzes[progressData['quizId']] = {
                'stars': progressData['stars'] ?? 0,
                'score': progressData['score'] ?? 0,
              };
            }
          }
        }
      } catch (e) {
        print('Error loading student progress: $e');
      }

      for (final contentDoc in contentDocs) {
        final contentId = contentDoc.id;

        final unitsSnap = await FirebaseFirestore.instance
            .collection('personalizedContent')
            .doc(contentId)
            .collection('units')
            .orderBy('order')
            .get();

        for (final unitDoc in unitsSnap.docs) {
          final unitId = unitDoc.id;

          List<String> unitActivityIds = [];
          int unitActivitiesCompleted = 0;

          final lessonsSnap = await FirebaseFirestore.instance
              .collection('personalizedContent')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('lessons')
              .orderBy('order')
              .get();

          for (final lessonDoc in lessonsSnap.docs) {
            final lessonId = lessonDoc.id;
            final lessonData = lessonDoc.data();

            final activitiesSnap = await FirebaseFirestore.instance
                .collection('personalizedContent')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('activities')
                .orderBy('order')
                .get();

            for (final activityDoc in activitiesSnap.docs) {
              final activityData = activityDoc.data();
              final activityId = activityDoc.id;
              final requiredActivityId = activityData['requiredActivityId'];

              unitActivityIds.add(activityId);

              final isCompleted = completedActivities.contains(activityId);
              if (isCompleted) unitActivitiesCompleted++;

              bool isUnlocked = true;
              if (requiredActivityId != null && requiredActivityId.isNotEmpty) {
                isUnlocked = completedActivities.contains(requiredActivityId);
              }

              allItems.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'lessonTitle': lessonData['title'] ?? 'Untitled Lesson',
                'activityId': activityId,
                'title': activityData['title'] ?? 'Untitled Activity',
                'order': activityData['order'] ?? 0,
                'difficulty': activityData['difficulty'] ?? 'medium',
                'xpBase': activityData['xpBase'] ?? 100,
                'isUnlocked': isUnlocked,
                'isCompleted': isCompleted,
                'requiredActivityId': requiredActivityId,
                'bonusXP': null,
                'deadline': null,
              });
            }

            final quizzesSnap = await FirebaseFirestore.instance
                .collection('personalizedContent')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('quizzes')
                .get();

            for (final quizDoc in quizzesSnap.docs) {
              final quizData = quizDoc.data();
              final quizId = quizDoc.id;

              final bool isQuizUnlocked =
                  unitActivitiesCompleted == unitActivityIds.length &&
                      unitActivityIds.isNotEmpty;

              final bool isCompleted = completedQuizzes.containsKey(quizId);
              final int stars =
                  isCompleted ? (completedQuizzes[quizId]['stars'] ?? 0) : 0;

              allItems.add({
                'type': 'quiz',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'quizId': quizId,
                'title': quizData['title'] ?? 'Lesson Quiz',
                'description':
                    quizData['description'] ?? 'Test your lesson knowledge',
                'isUnlocked': isQuizUnlocked,
                'isCompleted': isCompleted,
                'stars': stars,
                'bonusXP': null,
                'deadline': null,
              });
            }
          }

          // Load unit-level quizzes (at units/{unitId}/quizzes)
          final unitQuizzesSnap = await FirebaseFirestore.instance
              .collection('personalizedContent')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('quizzes')
              .get();

          for (final quizDoc in unitQuizzesSnap.docs) {
            final quizData = quizDoc.data();
            final quizId = quizDoc.id;

            // Unit quiz unlocks only when all activities in the unit are done
            final bool isQuizUnlocked =
                unitActivitiesCompleted == unitActivityIds.length &&
                    unitActivityIds.isNotEmpty;

            final bool isCompleted = completedQuizzes.containsKey(quizId);
            final int stars =
                isCompleted ? (completedQuizzes[quizId]['stars'] ?? 0) : 0;

            allItems.add({
              'type': 'quiz',
              'contentId': contentId,
              'unitId': unitId,
              'lessonId': '', // empty = unit-level quiz
              'quizId': quizId,
              'title': quizData['title'] ?? 'Unit Quiz',
              'description':
                  quizData['description'] ?? 'Complete to unlock next unit',
              'isUnlocked': isQuizUnlocked,
              'isCompleted': isCompleted,
              'stars': stars,
              'bonusXP': null,
              'deadline': null,
            });
          }
        }
      }

      return allItems;
    } catch (e) {
      print('Error loading assigned content: $e');
      return [];
    }
  }

  String _getStarDisplay(int stars) {
    switch (stars) {
      case 3:
        return '⭐⭐⭐';
      case 2:
        return '⭐⭐';
      case 1:
        return '⭐';
      default:
        return '';
    }
  }
}
