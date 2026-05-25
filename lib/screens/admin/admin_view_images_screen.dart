// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';
// import 'package:flutter_svg/svg.dart';
import 'package:loringo_app/screens/admin/admin_upload_image_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class AdminViewImagesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const AdminViewImagesScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<AdminViewImagesScreen> createState() => _AdminViewImagesScreenState();
}

class _AdminViewImagesScreenState extends State<AdminViewImagesScreen> {
  final imageService = ImageService();
  List<Map<String, dynamic>> images = [];
  bool isLoading = false;
  int _imagesPerPage = 10;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      setState(() => _imagesPerPage += 10);
    }
  }

  Future<void> _loadImages() async {
    setState(() => isLoading = true);
    try {
      final fetchedImages = await imageService.getImagesByCategory(widget.categoryId);
      setState(() {
        images = fetchedImages;
        isLoading = false;
        _imagesPerPage = 10;
      });
    } catch (e) {
      print('Error loading images: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteImage(String imageId, String cloudinaryPublicId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );

    if (confirmed == true) {
      final success = await imageService.deleteImageComplete(widget.categoryId, imageId, cloudinaryPublicId);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image deleted')),
        );
        _loadImages();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedImages = images.take(_imagesPerPage).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.categoryName} (${images.length})'),
        backgroundColor: AppColors.primary,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : displayedImages.isEmpty
              ? const Center(
                  child: Text('No images yet. Tap + to add images.'),
                )
              : GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: displayedImages.length,
                  itemBuilder: (context, index) {
                    final image = displayedImages[index];
                    // final isSvg = image['format'] == 'svg';

                    return Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
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
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.6),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              image['name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _deleteImage(
                              image['id'],
                              image['cloudinaryPublicId'],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.7),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminUploadImageScreen(
                categoryId: widget.categoryId,
                categoryName: widget.categoryName,
              ),
            ),
          ).then((_) => _loadImages()); // Refresh after upload
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_photo_alternate),
        tooltip: 'Add Images',
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}