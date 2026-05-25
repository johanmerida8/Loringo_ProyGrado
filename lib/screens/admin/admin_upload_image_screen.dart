import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class AdminUploadImageScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const AdminUploadImageScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<AdminUploadImageScreen> createState() => _AdminUploadImageScreenState();
}

class _AdminUploadImageScreenState extends State<AdminUploadImageScreen> {
  final imageService = ImageService();
  static const int minRecommendedImages = 15; // Flexible minimum
  List<Map<String, dynamic>> selectedFiles = [];
  bool isUploading = false;

  Future<void> _selectImages() async {
    try {
      final pickedFiles = await imageService.pickMultipleImages();
      if (pickedFiles == null || pickedFiles.isEmpty) return;

      setState(() {
        selectedFiles = pickedFiles
            .map((file) => {
                  'file': file,
                  'name': file.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
                  'isSvg': file.name.toLowerCase().endsWith('.svg'),
                })
            .toList();
      });

      _showPreviewDialog();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showPreviewDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Preview (${selectedFiles.length} images)'),
        content: SizedBox(
          width: 600,
          height: 500,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: selectedFiles.length,
            itemBuilder: (context, index) {
              final file = selectedFiles[index]['file'];
              final isSvg = selectedFiles[index]['isSvg'] as bool;
              
              return Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: isSvg
                                ? Container(
                                    color: Colors.blue[50],
                                    child: const Center(
                                      child: Icon(
                                        Icons.image_aspect_ratio,
                                        color: Colors.blue,
                                        size: 40,
                                      ),
                                    ),
                                  )
                                : Image.memory(
                                    file.bytes!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child: Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Tooltip(
                        message: file.name,
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => selectedFiles.removeAt(index));
                        Navigator.pop(context);
                        if (selectedFiles.isNotEmpty) {
                          _showPreviewDialog();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => selectedFiles = []);
              Navigator.pop(context);
            },
            child: const Text('Clear All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showUploadConfirmDialog();
            },
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  void _showUploadConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Upload'),
        content: Text('Upload ${selectedFiles.length} images to "${widget.categoryName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadImages();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadImages() async {
    if (selectedFiles.isEmpty) return;

    setState(() => isUploading = true);

    int successCount = 0;
    int failedCount = 0;
    int rejectedCount = 0;

    for (int i = 0; i < selectedFiles.length; i++) {
      final file = selectedFiles[i]['file'];
      final imageName = selectedFiles[i]['name'];

      try {
        // Get upload result (moderation handled by Cloudinary)
        final uploadResult = await imageService.uploadToCloudinary(
          file,
          categoryName: widget.categoryName,
        );

        // Check if upload was successful
        if (uploadResult is! Map || uploadResult['success'] != true) {
          final reason = uploadResult['reason'] ?? uploadResult['error'] ?? 'Upload failed';
          rejectedCount++;
          print('Rejected ${i + 1}/${selectedFiles.length}: $imageName - $reason');
          continue;
        }

        // Extract the secure URL from the result
        final imageUrl = uploadResult['secure_url'] as String;

        final cloudinaryPublicId = 'imagesPredefined/${widget.categoryName}/$imageName';

        await imageService.saveImageMetadata(
          name: imageName,
          categoryId: widget.categoryId,
          imageUrl: imageUrl,
          cloudinaryPublicId: cloudinaryPublicId,
          fileExtension: file.name.split('.').last,
        );

        successCount++;
        print('Uploaded ${i + 1}/${selectedFiles.length}: $imageName');
      } catch (e) {
        failedCount++;
        print('Failed ${i + 1}/${selectedFiles.length}: $imageName - $e');
      }
    }

    setState(() {
      isUploading = false;
      selectedFiles = [];
    });

    final parts = <String>[];
    if (successCount > 0) parts.add('Uploaded: $successCount');
    if (rejectedCount > 0) parts.add('Rejected: $rejectedCount (inappropriate)');
    if (failedCount > 0) parts.add('Failed: $failedCount');
    
    final message = parts.isEmpty ? 'No images processed' : parts.join(', ');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failedCount == 0 && rejectedCount == 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRecommendedAmount = selectedFiles.length >= minRecommendedImages;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        backgroundColor: AppColors.primary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            const Text(
              'Select images to upload',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Selected: ${selectedFiles.length} images',
              style: TextStyle(
                fontSize: 16,
                color: isRecommendedAmount ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Recommended: $minRecommendedImages+ images',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 30),
            if (selectedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showPreviewDialog,
                        icon: const Icon(Icons.preview),
                        label: const Text('Preview'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() => selectedFiles = []);
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: isUploading ? null : _selectImages,
            label: Text(isUploading ? 'Uploading...' : 'Select Images'),
            icon: isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.add_photo_alternate),
            backgroundColor: AppColors.primary,
            tooltip: 'Select images',
          ),
          if (selectedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FloatingActionButton.extended(
                onPressed: isUploading ? null : _showUploadConfirmDialog,
                label: Text(isUploading ? 'Uploading...' : 'Upload All'),
                icon: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.cloud_upload),
                backgroundColor: isRecommendedAmount ? Colors.blue : Colors.orange,
                tooltip: 'Upload selected images',
              ),
            ),
        ],
      ),
    );
  }
}