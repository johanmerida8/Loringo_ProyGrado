import 'package:flutter/material.dart';
import 'package:loringo_app/utils/image_service.dart';

class SelectImageDialog extends StatefulWidget {
  final bool singleSelect;

  const SelectImageDialog({
    super.key,
    this.singleSelect = true,
  });

  @override
  State<SelectImageDialog> createState() => _SelectImageDialogState();
}

class _SelectImageDialogState extends State<SelectImageDialog> {
  final imageService = ImageService();
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> images = [];
  String? selectedCategoryId;
  String? selectedCategoryName;
  bool isLoadingCategories = true;
  bool isLoadingImages = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await imageService.getCategories();
      setState(() {
        categories = cats;
        isLoadingCategories = false;
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() => isLoadingCategories = false);
    }
  }

  Future<void> _loadImages(String categoryId) async {
    setState(() => isLoadingImages = true);
    try {
      final imgs = await imageService.getImagesByCategory(categoryId);
      setState(() {
        images = imgs;
        isLoadingImages = false;
      });
    } catch (e) {
      print('Error loading images: $e');
      setState(() => isLoadingImages = false);
    }
  }

  void _selectImage(Map<String, dynamic> image) {
    Navigator.pop(context, image);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          AppBar(
            title: const Text('Select Image'),
            backgroundColor: const Color(0xFF4CAF50),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          Expanded(
            child: isLoadingCategories
                ? const Center(child: CircularProgressIndicator())
                : selectedCategoryId == null
                    ? _buildCategoryList()
                    : _buildImageGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return ListTile(
          title: Text(category['name'] as String),
          trailing: const Icon(Icons.arrow_forward),
          onTap: () {
            setState(() {
              selectedCategoryId = category['id'];
              selectedCategoryName = category['name'];
            });
            _loadImages(category['id']);
          },
        );
      },
    );
  }

  Widget _buildImageGrid() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    selectedCategoryId = null;
                    selectedCategoryName = null;
                    images.clear();
                  });
                },
              ),
              Expanded(
                child: Text(
                  selectedCategoryName ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoadingImages
              ? const Center(child: CircularProgressIndicator())
              : images.isEmpty
                  ? const Center(child: Text('No images in this category'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        final image = images[index];
                        return GestureDetector(
                          onTap: () => _selectImage(image),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                image['displayUrl'] ?? image['imageUrl'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}