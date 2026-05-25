import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final Database _db = Database();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome to Admin Dashboard',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage and oversee all system content',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          
          // Stats Grid
          const Text(
            'System Statistics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              // Total Images
              FutureBuilder<int>(
                future: _db.getTotalImagesCount(),
                builder: (context, snapshot) {
                  return _buildStatCard(
                    'Total Images',
                    snapshot.data?.toString() ?? '0',
                    Icons.image,
                    Colors.blue,
                    isLoading: snapshot.connectionState == ConnectionState.waiting,
                  );
                },
              ),
              
              // Categories
              StreamBuilder<int>(
                stream: _db.getCategoriesCountStream(),
                builder: (context, snapshot) {
                  return _buildStatCard(
                    'Categories',
                    snapshot.data?.toString() ?? '0',
                    Icons.folder,
                    Colors.orange,
                    isLoading: snapshot.connectionState == ConnectionState.waiting,
                  );
                },
              ),

              // Approved Content
              StreamBuilder<int>(
                stream: _db.getApprovedContentCountStream(),
                builder: (context, snapshot) {
                  return _buildStatCard(
                    'Approved Content',
                    snapshot.data?.toString() ?? '0',
                    Icons.check_circle,
                    Colors.green,
                    isLoading: snapshot.connectionState == ConnectionState.waiting,
                  );
                },
              ),
              
              // Pending Approval
              StreamBuilder<int>(
                stream: _db.getPendingContentCountStream(),
                builder: (context, snapshot) {
                  return _buildStatCard(
                    'Pending Approval',
                    snapshot.data?.toString() ?? '0',
                    Icons.hourglass_bottom,
                    Colors.amber,
                    isLoading: snapshot.connectionState == ConnectionState.waiting,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Coming Soon Message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dashboard updates in real-time',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isLoading = false,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),  // Reduced from 16
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),  // Reduced from 40
            const SizedBox(height: 8),  // Reduced from 12
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,  // Reduced from 28
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 6),  // Reduced from 8
            Text(
              title,
              style: TextStyle(
                fontSize: 13,  // Reduced from 14
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}