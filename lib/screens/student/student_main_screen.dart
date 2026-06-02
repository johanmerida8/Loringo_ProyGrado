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

  // ── Liga / recompensa ────────────────────────────────────────────────────
  // Recompensa del docente para el tier actual del estudiante.
  // Vacío si no hay recompensa configurada o la liga está bloqueada.
  String _leagueReward = '';

  // true solo cuando este estudiante tiene el mayor XP dentro de su liga
  // en su grupo. Se recalcula cada vez que entra al tab de liga.
  bool _isLeagueWinner = false;

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

            // Una vez que tenemos el groupId, calculamos el estado de liga
            await _loadLeagueStatus(fetchedGroupId);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading student group: $e');
    }
  }

  // ==========================================================================
  // _loadLeagueStatus
  //
  // Determina si el estudiante es el #1 de su liga y cuál es su recompensa.
  //
  // LÓGICA:
  //   1. Lee el XP actual del estudiante desde Firestore.
  //   2. Determina en qué liga está (mismo algoritmo que _getLeagueLevel).
  //   3. Si la liga no tiene recompensa (rewardLocked), sale — no hay nada
  //      que mostrar.
  //   4. Lee todos los estudiantes del mismo grupo con whereIn([groupId]).
  //   5. Filtra los que están en el mismo rango de XP (misma liga).
  //   6. El estudiante es ganador si su XP es el mayor del grupo en esa liga.
  //   7. Carga la recompensa del docente desde leagueRewards/config.
  // ==========================================================================
  Future<void> _loadLeagueStatus(String gid) async {
    try {
      // 1. XP actual del estudiante
      final myDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (!myDoc.exists) return;

      final myXp = ((myDoc.data()?['xp'] as num?) ?? 0).toInt();

      // 2. Liga actual
      final myTier = _getTierForXp(myXp);
      final tierKey    = myTier['key']          as String;
      final tierMin    = myTier['min']           as int;
      final tierMax    = myTier['max']           as int;
      final isLocked   = myTier['rewardLocked']  as bool;

      // 3. Ligas sin recompensa — no hay nada que mostrar
      if (isLocked) {
        if (mounted) setState(() { _leagueReward = ''; _isLeagueWinner = false; });
        return;
      }

      // 4. Todos los estudiantes del grupo
      final groupSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('groupId', isEqualTo: gid)
          .get();

      // 5. Filtra la misma liga
      final sameLeague = groupSnap.docs
          .where((d) {
            final xp = ((d.data()['xp'] as num?) ?? 0).toInt();
            return xp >= tierMin && xp < tierMax;
          })
          .toList()
        ..sort((a, b) {
          final ax = ((a.data()['xp'] as num?) ?? 0).toInt();
          final bx = ((b.data()['xp'] as num?) ?? 0).toInt();
          return bx.compareTo(ax); // Mayor XP primero
        });

      // 6. ¿Es este estudiante el #1?
      final isWinner = sameLeague.isNotEmpty &&
          sameLeague.first.id == widget.studentId;

      // 7. Recompensa del docente
      String reward = '';
      if (isWinner) {
        final rewardDoc = await FirebaseFirestore.instance
            .collection('teacherGroups')
            .doc(gid)
            .collection('leagueRewards')
            .doc('config')
            .get();
        if (rewardDoc.exists) {
          reward = (rewardDoc.data()?[tierKey] as String?) ?? '';
        }
      }

      if (mounted) {
        setState(() {
          _isLeagueWinner = isWinner && reward.isNotEmpty;
          _leagueReward   = reward;
        });
      }
    } catch (e) {
      debugPrint('Error loading league status: $e');
    }
  }

  /// Misma lógica que _getLeagueLevel — devuelve el tier para un XP dado.
  /// Duplicada aquí para no depender de kLeagueTiers del archivo del docente.
  Map<String, dynamic> _getTierForXp(int xp) {
    for (final t in _leagueTiers()) {
      if (xp >= (t['min'] as int) && xp < (t['max'] as int)) return t;
    }
    return _leagueTiers().last;
  }

  Future<void> _initBiometrics() async {
    try {
      final isSupported = await BiometricService.isDeviceSupported();
      final canCheck    = await BiometricService.canCheckBiometrics();
      final available   = await BiometricService.getAvailableBiometrics();
      final isEnabled   = await BiometricService.isBiometricEnabled(widget.studentId);

      setState(() {
        isBiometricSupported = isSupported && canCheck;
        availableBiometrics  = available;
        biometricTypeName    = BiometricService.getBiometricTypeName(available);
        isBiometricEnabled   = isEnabled;
      });
    } catch (e) {
      debugPrint('Error initializing biometrics: $e');
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final authenticated = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric login',
      );
      if (authenticated) {
        await BiometricService.setBiometricEnabled(
            userId: widget.studentId, enabled: true);
        setState(() => isBiometricEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ $biometricTypeName login enabled'),
            backgroundColor: Colors.green,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Authentication failed'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } else {
      await BiometricService.setBiometricEnabled(
          userId: widget.studentId, enabled: false);
      setState(() => isBiometricEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$biometricTypeName login disabled'),
          backgroundColor: Colors.grey,
        ));
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
            _buildActivitiesTab(),
            _buildGroupTab(),
            _buildLeagueTab(),
            _buildSettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          AppNavItem(icon: Icons.home_rounded,         label: 'Home'),
          AppNavItem(icon: Icons.groups_rounded,       label: 'Group'),
          AppNavItem(icon: Icons.emoji_events_rounded, label: 'League'),
          AppNavItem(icon: Icons.settings_rounded,     label: 'Settings'),
        ],
      ),
    );
  }

  // ==========================================================================
  // _buildActivitiesTab — sin cambios
  // ==========================================================================
  Widget _buildActivitiesTab() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Text("Loringo",
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50))),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.settings, color: Color(0xFF4CAF50)),
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
                                child: const Text('Cancel')),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await StudentAuthService.clearStudentLogin();
                                if (context.mounted) {
                                  Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const LoginOrRegister()),
                                      (route) => false);
                                }
                              },
                              child: const Text('Logout',
                                  style: TextStyle(color: Colors.red)),
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
                        leading: Icon(Icons.logout, color: Colors.redAccent),
                        title: Text('Logout'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF4CAF50),
                  backgroundImage: widget.studentAvatar != null
                      ? AssetImage(widget.studentAvatar!) : null,
                  child: widget.studentAvatar == null
                      ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Hello, ${widget.studentName}!',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      const SizedBox(height: 8),
                      Text(groupName ?? 'Loading...',
                          style: const TextStyle(fontSize: 16, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                            Icon(Icons.assignment_rounded, size: 100,
                                color: Color(0xFF4CAF50)),
                            SizedBox(height: 24),
                            Text('No Activities Available',
                                style: TextStyle(fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4CAF50))),
                            SizedBox(height: 12),
                            Text('Contact your teacher to add learning activities',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }

                  final activities = snapshot.data!;
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
                    final uid       = item['unitId'] as String? ?? '';
                    final count     = unitItemCounts[uid] ?? 0;
                    final progress  = unitProgress[uid] ?? 0;
                    final midPoint  = count ~/ 2;
                    final unitOrdinal = unitOrder.indexOf(uid) + 1;
                    final mascotPath  = mascots[(unitOrdinal - 1) % mascots.length];
                    final bool isLeft = activityIndex % 2 == 0;
                    final int levelNum = activityIndex + 1;
                    activityIndex++;

                    final bool isUnlocked  = item['isUnlocked'] ?? false;
                    final String itemType  = item['type'] ?? 'activity';
                    final bool isQuiz      = itemType == 'quiz';
                    final bool isCompleted = item['isCompleted'] ?? false;
                    final int stars        = item['stars'] ?? 0;

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
                                        Navigator.push(context,
                                            MaterialPageRoute(
                                                builder: (_) => QuizPlayScreen(
                                                  contentId:    item['contentId'],
                                                  unitId:       item['unitId'],
                                                  lessonId:     item['lessonId'],
                                                  quizId:       item['quizId'],
                                                  quizTitle:    item['title'],
                                                  collectionName: 'quizzes', // ✅ Updated to 'quizzes'
                                                  studentId:    widget.studentId,
                                                )));
                                      } else {
                                        Navigator.push(context,
                                            MaterialPageRoute(
                                                builder: (_) => ActivityPlayScreen(
                                                  contentId:    item['contentId'],
                                                  unitId:       item['unitId'],
                                                  lessonId:     item['lessonId'],
                                                  activityId:   item['activityId'],
                                                  activityTitle: item['title'],
                                                  studentId:    widget.studentId,
                                                  xpBase:       item['xpBase'] ?? 100,
                                                  bonusXP:      item['bonusXP'] ?? 0,
                                                  collectionName: 'content',
                                                  isPreview:    false,
                                                ))).then((_) => setState(() {}));
                                      }
                                    }
                                  : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: isUnlocked
                                        ? (isQuiz
                                            ? const LinearGradient(colors: [Color(0xFFFFB74D), Color(0xFFFF9800)])
                                            : const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF81C784)]))
                                        : LinearGradient(colors: [Colors.grey[400]!, Colors.grey[600]!]),
                                    border: Border.all(color: Colors.white, width: 4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 12, offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  width: 80, height: 80,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isUnlocked ? (isQuiz ? Icons.quiz : Icons.star) : Icons.lock,
                                          color: Colors.white, size: 28,
                                        ),
                                        const SizedBox(height: 4),
                                        if (isQuiz && isCompleted)
                                          Text(_getStarDisplay(stars),
                                              style: const TextStyle(color: Colors.white, fontSize: 16))
                                        else
                                          Text(isQuiz ? 'Quiz' : 'Level $levelNum',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12)),
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
                                    fontSize: 16, fontWeight: FontWeight.w600,
                                    color: isUnlocked ? Colors.black87 : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ));

                    if (count > 0 && progress == midPoint) {
                      activityWidgets.add(Center(
                        child: Lottie.asset(mascotPath, width: 130, height: 130),
                      ));
                    }
                    unitProgress[uid] = progress + 1;
                  }

                  return SingleChildScrollView(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(children: activityWidgets),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // _buildGroupTab — sin cambios
  // ==========================================================================
  Widget _buildGroupTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
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
                CircleAvatar(
                  radius: 60,
                  backgroundColor: const Color(0xFF4CAF50),
                  backgroundImage: widget.studentAvatar != null
                      ? AssetImage(widget.studentAvatar!) : null,
                  child: widget.studentAvatar == null
                      ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
                ),
                const SizedBox(height: 24),
                Text(widget.studentName,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50))),
                const SizedBox(height: 8),
                const Text('Student',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 40),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                        offset: const Offset(0, 4), blurRadius: 8)],
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.groups_rounded, size: 48, color: Colors.white),
                      const SizedBox(height: 16),
                      const Text('My Group',
                          style: TextStyle(fontSize: 18, color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(groupName ?? 'No group assigned',
                          style: const TextStyle(fontSize: 24, color: Colors.white,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        offset: const Offset(0, 4), blurRadius: 8)],
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.emoji_events_rounded, size: 48,
                          color: Color(0xFFFE5D26)),
                      const SizedBox(height: 16),
                      const Text('Keep Learning!',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                              color: Color(0xFFFE5D26))),
                      const SizedBox(height: 8),
                      Text(
                        'You\'re doing great! Complete more activities to improve your skills.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // _buildLeagueTab
  //
  // NUEVO: Banner de ganador justo debajo del header de liga.
  // Solo aparece cuando _isLeagueWinner == true y hay recompensa configurada.
  //
  // El banner muestra:
  //   🏆 You're #1 in [League]!
  //   Prize: [recompensa del docente]
  //
  // Diseño dorado consistente con el badge "Winner" en la pantalla del docente.
  // ==========================================================================
  Widget _buildLeagueTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('students')
              .doc(widget.studentId)
              .snapshots(),
          builder: (context, studentSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('students')
                  .doc(widget.studentId)
                  .collection('progress')
                  .snapshots(),
              builder: (context, progressSnap) {
                final int totalXP = studentSnap.hasData && studentSnap.data!.exists
                    ? (((studentSnap.data!.data() as Map<String, dynamic>)['xp'])
                            as num? ??
                        0)
                        .toInt()
                    : 0;

                int activitiesCompleted = 0;
                int quizzesCompleted    = 0;
                if (progressSnap.hasData) {
                  for (final doc in progressSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['isCompleted'] == true) {
                      if (data.containsKey('activityId')) activitiesCompleted++;
                      else if (data.containsKey('quizId')) quizzesCompleted++;
                    }
                  }
                }

                final leagueData  = _getLeagueLevel(totalXP);
                final String leagueName  = leagueData['name']  as String;
                final int    leagueMin   = leagueData['min']   as int;
                final int    leagueMax   = leagueData['max']   as int;
                final Color  leagueColor = leagueData['color'] as Color;
                final String? leagueImage = leagueData['image'] as String?;
                final double progress = leagueMax > leagueMin
                    ? ((totalXP - leagueMin) / (leagueMax - leagueMin))
                        .clamp(0.0, 1.0)
                    : 1.0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header de liga ────────────────────────────
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [leagueColor, leagueColor.withOpacity(0.6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: leagueColor.withOpacity(0.35),
                                    blurRadius: 20, offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: leagueImage != null
                                  ? Image.asset(leagueImage,
                                      width: 64, height: 64, fit: BoxFit.contain)
                                  : Icon(Icons.shield_rounded,
                                      size: 52, color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            Text(leagueName,
                                style: TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold,
                                    color: leagueColor)),
                            const SizedBox(height: 4),
                            Text(widget.studentName,
                                style: const TextStyle(
                                    fontSize: 15, color: Colors.grey)),
                          ],
                        ),
                      ),

                      // ── NUEVO: Banner de ganador ──────────────────
                      // Visible solo cuando el estudiante es #1 en su liga
                      // y el docente configuró una recompensa.
                      if (_isLeagueWinner && _leagueReward.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _WinnerBanner(
                          leagueName: leagueName,
                          reward:     _leagueReward,
                          color:      leagueColor,
                        ),
                      ],

                      const SizedBox(height: 32),

                      // ── XP Card ───────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.07),
                              blurRadius: 12, offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total XP',
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.grey,
                                        fontWeight: FontWeight.w600)),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: leagueColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(leagueName,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: leagueColor)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$totalXP',
                                    style: TextStyle(
                                        fontSize: 48, fontWeight: FontWeight.bold,
                                        color: leagueColor, height: 1)),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8, left: 6),
                                  child: Text('XP',
                                      style: TextStyle(
                                          fontSize: 20, fontWeight: FontWeight.w600,
                                          color: Colors.grey)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$leagueMin XP',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                                Text(
                                  leagueMax == 999999 ? 'Max League' : '$leagueMax XP',
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
                              Text('${leagueMax - totalXP} XP to next league',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600])),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Stats ─────────────────────────────────────
                      Row(
                        children: [
                          Expanded(child: _leagueStat(
                              icon: Icons.star_rounded,
                              label: 'Activities',
                              value: '$activitiesCompleted',
                              color: const Color(0xFF4CAF50))),
                          const SizedBox(width: 12),
                          Expanded(child: _leagueStat(
                              icon: Icons.quiz_rounded,
                              label: 'Quizzes',
                              value: '$quizzesCompleted',
                              color: const Color(0xFF7C3AED))),
                          const SizedBox(width: 12),
                          Expanded(child: _leagueStat(
                              icon: Icons.bolt_rounded,
                              label: 'Total',
                              value: '${activitiesCompleted + quizzesCompleted}',
                              color: const Color(0xFFFF9800))),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ── League Tiers ──────────────────────────────
                      const Text('League Tiers',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold,
                              color: Colors.black87)),
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
                                    color: (tier['color'] as Color)
                                        .withOpacity(0.5),
                                    width: 2)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36, height: 36,
                                child: (tier['image'] as String?) != null
                                    ? Image.asset(tier['image'] as String,
                                        fit: BoxFit.contain)
                                    : Icon(Icons.shield_rounded,
                                        color: tier['color'] as Color,
                                        size: 26),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tier['name'] as String,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isCurrent
                                                ? tier['color'] as Color
                                                : Colors.black87)),
                                    Text(tier['range'] as String,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey)),
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
                                  child: const Text('YOU',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
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
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Map<String, dynamic> _getLeagueLevel(int xp) {
    for (final tier in _leagueTiers()) {
      if (xp >= (tier['min'] as int) && xp < (tier['max'] as int)) return tier;
    }
    return _leagueTiers().last;
  }

  List<Map<String, dynamic>> _leagueTiers() => [
    {'name': 'Starter',  'min': 0,    'max': 200,    'range': '0 – 199 XP',
     'color': const Color(0xFF9E9E9E), 'image': null,
     'rewardLocked': true},
    {'name': 'Bronze',   'min': 200,  'max': 500,    'range': '200 – 499 XP',
     'color': const Color(0xFFCD7F32),
     'image': 'assets/leagues/bronze-league.png', 'rewardLocked': true},
    {'name': 'Silver',   'min': 500,  'max': 1000,   'range': '500 – 999 XP',
     'color': const Color(0xFF78909C),
     'image': 'assets/leagues/silver-league.png', 'rewardLocked': false},
    {'name': 'Gold',     'min': 1000, 'max': 2000,   'range': '1000 – 1999 XP',
     'color': const Color(0xFFFFB300),
     'image': 'assets/leagues/gold-league.png',   'rewardLocked': false},
    {'name': 'Platinum', 'min': 2000, 'max': 4000,   'range': '2000 – 3999 XP',
     'color': const Color(0xFF00BCD4),
     'image': 'assets/leagues/platinum-league.png', 'rewardLocked': false},
    {'name': 'Diamond',  'min': 4000, 'max': 999999, 'range': '4000+ XP',
     'color': const Color(0xFF1565C0),
     'image': 'assets/leagues/diamond-league.png', 'rewardLocked': false},
  ];

  // ==========================================================================
  // _buildSettingsTab — sin cambios
  // ==========================================================================
  Widget _buildSettingsTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Settings',
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50))),
              const SizedBox(height: 40),
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
                          ? Icons.face_rounded : Icons.fingerprint_rounded,
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  title: Text('$biometricTypeName Login',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Quick and secure login'),
                  trailing: Switch(
                    value: isBiometricEnabled,
                    onChanged: _toggleBiometric,
                    activeColor: const Color(0xFF4CAF50),
                  ),
                ),
              if (isBiometricSupported) const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Color(0xFF4CAF50)),
                ),
                title: const Text('Refresh',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: const Text('Reload your activities'),
                onTap: () {
                  setState(() { _loadStudentGroup(); });
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Refreshed!'),
                          duration: Duration(seconds: 1)));
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.red),
                ),
                title: const Text('Logout',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600,
                        color: Colors.red)),
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
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await StudentAuthService.clearStudentLogin();
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LoginOrRegister()),
                                  (route) => false);
                            }
                          },
                          child: const Text('Logout',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.school_rounded, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('Loringo Student',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey[600],
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Version 1.0.0',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // _loadAssignedContent — sin cambios
  // ==========================================================================
  Future<List<Map<String, dynamic>>> _loadAssignedContent() async {
    try {
      if (groupId == null) return [];
      
      final contentSnap = await FirebaseFirestore.instance
          .collection('content')
          .where('assignedTo', arrayContains: groupId)
          .where('status', isEqualTo: 'approved')
          .get();

      final contentDocs = contentSnap.docs.toList()
        ..sort((a, b) {
          final ao = (a.data()['order'] as num? ?? 0).toInt();
          final bo = (b.data()['order'] as num? ?? 0).toInt();
          return ao.compareTo(bo);
        });

      Set<String> completedActivities = {};
      Map<String, dynamic> completedQuizzes = {};

      try {
        final progressSnapshot = await FirebaseFirestore.instance
            .collection('students').doc(widget.studentId)
            .collection('progress').get();
        for (var d in progressSnapshot.docs) {
          final pd = d.data();
          if (pd['isCompleted'] == true) {
            if (pd.containsKey('activityId')) completedActivities.add(pd['activityId']);
            else if (pd.containsKey('quizId')) {
              completedQuizzes[pd['quizId']] = {
                'stars': pd['stars'] ?? 0, 'score': pd['score'] ?? 0
              };
            }
          }
        }
      } catch (e) { debugPrint('Error loading progress: $e'); }

      final List<Map<String, dynamic>> allItems = [];

      for (final contentDoc in contentDocs) {
        final contentId = contentDoc.id;
        final unitsSnap = await FirebaseFirestore.instance
            .collection('content').doc(contentId)
            .collection('units').orderBy('order').get();

        for (final unitDoc in unitsSnap.docs) {
          final unitId = unitDoc.id;
          List<String> unitActivityIds = [];
          int unitActivitiesCompleted = 0;

          final lessonsSnap = await FirebaseFirestore.instance
              .collection('content').doc(contentId)
              .collection('units').doc(unitId)
              .collection('lessons').orderBy('order').get();

          for (final lessonDoc in lessonsSnap.docs) {
            final lessonId   = lessonDoc.id;
            final lessonData = lessonDoc.data();

            final activitiesSnap = await FirebaseFirestore.instance
                .collection('content').doc(contentId)
                .collection('units').doc(unitId)
                .collection('lessons').doc(lessonId)
                .collection('activities').orderBy('order').get();

            for (final actDoc in activitiesSnap.docs) {
              final actData           = actDoc.data();
              final activityId        = actDoc.id;
              final requiredActivityId = actData['requiredActivityId'];
              unitActivityIds.add(activityId);
              final isCompleted = completedActivities.contains(activityId);
              if (isCompleted) unitActivitiesCompleted++;
              bool isUnlocked = true;
              if (requiredActivityId != null && requiredActivityId.isNotEmpty) {
                isUnlocked = completedActivities.contains(requiredActivityId);
              }
              allItems.add({
                'type': 'activity', 'contentId': contentId,
                'unitId': unitId, 'lessonId': lessonId,
                'lessonTitle': lessonData['title'] ?? 'Untitled Lesson',
                'activityId': activityId,
                'title': actData['title'] ?? 'Untitled Activity',
                'order': actData['order'] ?? 0,
                'difficulty': actData['difficulty'] ?? 'medium',
                'xpBase': actData['xpBase'] ?? 100,
                'isUnlocked': isUnlocked, 'isCompleted': isCompleted,
                'requiredActivityId': requiredActivityId,
                'bonusXP': null, 'deadline': null,
              });
            }

            // ✅ Load lesson quizzes from root 'quizzes' collection
            final lessonQuizzesSnap = await FirebaseFirestore.instance
                .collection('quizzes')
                .where('type', isEqualTo: 'lesson')
                .where('contentId', isEqualTo: contentId)
                .where('unitId', isEqualTo: unitId)
                .where('lessonId', isEqualTo: lessonId)
                .get();

            for (final qDoc in lessonQuizzesSnap.docs) {
              final qData = qDoc.data() as Map<String, dynamic>;
              final quizId = qDoc.id;
              final isQuizUnlocked = unitActivitiesCompleted == unitActivityIds.length
                  && unitActivityIds.isNotEmpty;
              final isCompleted = completedQuizzes.containsKey(quizId);
              final stars = isCompleted ? (completedQuizzes[quizId]['stars'] ?? 0) : 0;
              allItems.add({
                'type': 'quiz', 'contentId': contentId,
                'unitId': unitId, 'lessonId': lessonId,
                'quizId': quizId, 'title': qData['title'] ?? 'Lesson Quiz',
                'description': qData['description'] ?? 'Test your lesson knowledge',
                'isUnlocked': isQuizUnlocked, 'isCompleted': isCompleted,
                'stars': stars, 'bonusXP': null, 'deadline': null,
              });
            }
          }

          // ✅ Load unit quizzes from root 'quizzes' collection
          final unitQuizzesSnap = await FirebaseFirestore.instance
              .collection('quizzes')
              .where('type', isEqualTo: 'unit')
              .where('contentId', isEqualTo: contentId)
              .where('unitId', isEqualTo: unitId)
              .get();

          for (final qDoc in unitQuizzesSnap.docs) {
            final qData = qDoc.data() as Map<String, dynamic>;
            final quizId = qDoc.id;
            final isQuizUnlocked = unitActivitiesCompleted == unitActivityIds.length
                && unitActivityIds.isNotEmpty;
            final isCompleted = completedQuizzes.containsKey(quizId);
            final stars = isCompleted ? (completedQuizzes[quizId]['stars'] ?? 0) : 0;
            allItems.add({
              'type': 'quiz', 'contentId': contentId,
              'unitId': unitId, 'lessonId': '',
              'quizId': quizId, 'title': qData['title'] ?? 'Unit Quiz',
              'description': qData['description'] ?? 'Complete to unlock next unit',
              'isUnlocked': isQuizUnlocked, 'isCompleted': isCompleted,
              'stars': stars, 'bonusXP': null, 'deadline': null,
            });
          }
        }
      }
      return allItems;
    } catch (e) {
      debugPrint('Error loading assigned content: $e');
      return [];
    }
  }

  String _getStarDisplay(int stars) {
    switch (stars) {
      case 3: return '⭐⭐⭐';
      case 2: return '⭐⭐';
      case 1: return '⭐';
      default: return '';
    }
  }
}

// =============================================================================
// _WinnerBanner
//
// Banner dorado que aparece en el tab de liga del estudiante cuando es el #1.
// Diseño consistente con el badge "Winner" de la pantalla del docente:
//   • Borde dorado de 2px
//   • Fondo amarillo muy suave
//   • Sombra dorada
//   • Trophy emoji + texto motivacional + recompensa
// =============================================================================
class _WinnerBanner extends StatelessWidget {
  final String leagueName;
  final String reward;
  final Color  color;

  const _WinnerBanner({
    required this.leagueName,
    required this.reward,
    required this.color,
  });

  static const Color _gold = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),      // fondo dorado suave
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold, width: 2),
        boxShadow: [
          BoxShadow(
            color: _gold.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Trofeo animado con contenedor dorado
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.4), width: 1.5),
            ),
            child: const Center(
              child: Text('🏆', style: TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\'re #1 in $leagueName!',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF795548), // marrón dorado
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Prize: ',
                      style: TextStyle(
                        fontSize: 13, color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        reward,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF795548),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}