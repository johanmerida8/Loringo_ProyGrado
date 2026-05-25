// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_upload_image_screen.dart';
import 'package:loringo_app/screens/admin/admin_view_images_screen.dart';
import 'package:loringo_app/utils/image_service.dart';


class AdminImagesScreen extends StatefulWidget {
  final Function(String url)? onImageSelected;
  
  const AdminImagesScreen({
    super.key,
    this.onImageSelected,
  });

  @override
  State<AdminImagesScreen> createState() => _AdminImagesScreenState();
}

class _AdminImagesScreenState extends State<AdminImagesScreen> {

  final imageService = ImageService();
  List<Map<String, dynamic>> categories = [];
  bool isLoadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final fetchedCategories = await imageService.getCategories();
      setState(() {
        categories = fetchedCategories;
        isLoadingCategories = false;
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() => isLoadingCategories = false);
    }
  }

  Future<void> _showCreateCategoryDialog() async {
    final nameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Category'),
        content: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: 'Category Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: Spaces will be converted to underscores'
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final rawName = nameController.text.trim();

              if (rawName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category name cannot be empty')),
                );
                return;
              }

              final sanitizedName = rawName
                  .replaceAll(' ', '_')
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
                  .toLowerCase();
              
              if (sanitizedName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category name must contain alphanumeric characters')),
                );
                return;
              }

              try {
                await imageService.createCategory(sanitizedName);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Category "$sanitizedName" created successfully')),
                );
                _loadCategories();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            }, 
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : categories.isEmpty
              ? const Center(
                  child: Text('No categories yet. Tap + to create one.'),
                )
              : ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.folder, color: Color(0xFF4CAF50)),
                        title: Text(
                          category['name'],
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminViewImagesScreen(
                                categoryId: category['id'], 
                                categoryName: category['name'],
                              )
                            ),
                          ).then((_) => _loadCategories()); // Refresh on return
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateCategoryDialog,
        backgroundColor: const Color(0xFF4CAF50),
        child: const Icon(Icons.add),
        tooltip: 'Create New Category',
      ),
    );
  }
}