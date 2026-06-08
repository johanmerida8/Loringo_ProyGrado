import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';

class SelectImageDialog extends StatefulWidget {
  final bool singleSelect;
  const SelectImageDialog({super.key, this.singleSelect = true});

  @override
  State<SelectImageDialog> createState() => _SelectImageDialogState();
}

class _SelectImageDialogState extends State<SelectImageDialog> with SingleTickerProviderStateMixin {
  final Database _db = Database();
  final String _teacherId = FirebaseAuth.instance.currentUser!.uid;
  static const Color _green = Color(0xFF4CAF50);

  List<Map<String, dynamic>> _adminCategories = [];
  List<Map<String, dynamic>> _teacherCategories = [];
  List<Map<String, dynamic>> _images = [];
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  bool _isLoadingCategories = true;
  bool _isLoadingImages = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCategories();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadCategories() async {
    try {
      final results = await Future.wait([
        _db.getAdminCategories(),
        _db.getTeacherCategories(_teacherId),
      ]);
      setState(() { _adminCategories = results[0]; _teacherCategories = results[1]; _isLoadingCategories = false; });
    } catch (_) { setState(() => _isLoadingCategories = false); }
  }

  Future<void> _loadImages(String categoryId) async {
    setState(() { _isLoadingImages = true; _images = []; });
    try {
      // reads from mediaLibrary/{categoryId}/imageItems
      final imgs = await _db.getImagesByCategory(categoryId);
      setState(() { _images = imgs; _isLoadingImages = false; });
    } catch (_) { setState(() => _isLoadingImages = false); }
  }

  void _openCategory(String categoryId, String categoryName) {
    setState(() { _selectedCategoryId = categoryId; _selectedCategoryName = categoryName; });
    _loadImages(categoryId);
  }

  void _back() => setState(() { _selectedCategoryId = null; _selectedCategoryName = null; _images = []; });

  Widget _buildCategoryList(List<Map<String, dynamic>> categories) {
    if (categories.isEmpty) return const Center(child: Text('No categories yet', style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (_, index) {
        final cat = categories[index];
        // Field is now 'categoryName'
        final catName = cat['categoryName'] as String? ?? '';
        return ListTile(
          leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.folder_rounded, color: _green, size: 20)),
          title: Text(catName),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          onTap: () => _openCategory(cat['id'] as String, catName),
        );
      },
    );
  }

  Widget _buildImageGrid() {
    return Column(children: [
      Container(
        color: Colors.grey[100],
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          Expanded(child: Text(_selectedCategoryName ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
        ]),
      ),
      Expanded(
        child: _isLoadingImages
            ? const Center(child: CircularProgressIndicator(color: _green))
            : _images.isEmpty
                ? const Center(child: Text('No images in this category'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                    itemCount: _images.length,
                    itemBuilder: (_, index) {
                      final image = _images[index];
                      final url = image['displayUrl'] ?? image['imageUrl'] ?? '';
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, image),
                        child: Container(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                          child: ClipRRect(borderRadius: BorderRadius.circular(8),
                            child: Stack(fit: StackFit.expand, children: [
                              Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image))),
                              Positioned(bottom: 0, left: 0, right: 0,
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), color: Colors.black.withOpacity(0.45),
                                  child: Text(image['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis))),
                            ])),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          Container(
            color: _green,
            child: Row(children: [
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Text('Select Image', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          if (_selectedCategoryId == null)
            TabBar(
              controller: _tabController,
              labelColor: _green, unselectedLabelColor: Colors.grey, indicatorColor: _green,
              tabs: [Tab(text: 'Admin (${_adminCategories.length})'), Tab(text: 'Mine (${_teacherCategories.length})')],
            ),
          Expanded(
            child: _isLoadingCategories
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _selectedCategoryId != null
                    ? _buildImageGrid()
                    : TabBarView(controller: _tabController, children: [
                        _buildCategoryList(_adminCategories),
                        _buildCategoryList(_teacherCategories),
                      ]),
          ),
        ]),
      ),
    );
  }
}