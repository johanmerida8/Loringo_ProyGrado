import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

// ── AdminUploadImageScreen ────────────────────────────────────────────────────
// Redesigned: clear upload flow with progress indicator, image thumbnails,
// and a bottom sheet preview replacing the full-screen dialog.

class AdminUploadImageScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  const AdminUploadImageScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<AdminUploadImageScreen> createState() => _AdminUploadImageScreenState();
}

class _AdminUploadImageScreenState extends State<AdminUploadImageScreen> {
  final _imageService  = ImageService();
  final _db            = Database();
  static const int     _minRecommended = 15;
  static const Color   _green  = Color(0xFF4CAF50);
  static const Color   _green2 = Color(0xFF2E7D32);

  List<Map<String, dynamic>> _selectedFiles = [];
  bool    _isUploading  = false;
  int     _uploadedCount = 0;
  int     _totalCount   = 0;

  // ── File selection ────────────────────────────────────────────────────────

  Future<void> _selectImages() async {
    try {
      final picked = await _imageService.pickMultipleImages();
      if (picked == null || picked.isEmpty) return;
      setState(() {
        _selectedFiles = picked.map((f) => {
          'file': f,
          'name': f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
          'isSvg': f.name.toLowerCase().endsWith('.svg'),
        }).toList();
      });
      if (mounted) _showPreviewSheet();
    } catch (e) {
      if (mounted) _showError('Error selecting images: $e');
    }
  }

  // ── Preview bottom sheet ──────────────────────────────────────────────────

  void _showPreviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PreviewSheet(
        selectedFiles: _selectedFiles,
        onRemove: (index) {
          setState(() => _selectedFiles.removeAt(index));
          Navigator.pop(ctx);
          if (_selectedFiles.isNotEmpty) _showPreviewSheet();
        },
        onClearAll: () {
          setState(() => _selectedFiles = []);
          Navigator.pop(ctx);
        },
        onUpload: () {
          Navigator.pop(ctx);
          _confirmAndUpload();
        },
      ),
    );
  }

  // ── Confirm dialog ────────────────────────────────────────────────────────

  void _confirmAndUpload() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.cloud_upload_rounded, color: _green, size: 24),
          SizedBox(width: 10),
          Text('Confirm Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
              children: [
                TextSpan(text: '${_selectedFiles.length} image${_selectedFiles.length != 1 ? 's' : ''}'),
                const TextSpan(text: ' will be scanned for\ninappropriate content before uploading.'),
              ])),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _green.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withOpacity(0.2))),
            child: Row(children: [
              const Icon(Icons.folder_rounded, color: _green, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('To: ${widget.categoryName}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _green))),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _uploadImages(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Upload Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadImages() async {
    if (_selectedFiles.isEmpty) return;
    setState(() {
      _isUploading   = true;
      _uploadedCount = 0;
      _totalCount    = _selectedFiles.length;
    });

    int success = 0, rejected = 0, failed = 0;
    for (final entry in _selectedFiles) {
      final file      = entry['file'];
      final imageName = entry['name'] as String;
      final ext       = file.name.split('.').last;
      try {
        final result = await _imageService.uploadToCloudinary(
            file, categoryName: widget.categoryName);
        if (result['success'] != true) { rejected++; }
        else {
          await _db.saveImageMetadata(
            categoryId: widget.categoryId, name: imageName,
            imageUrl: result['secure_url'] as String,
            cloudinaryPublicId: result['public_id'] as String,
            fileExtension: ext,
          );
          success++;
        }
      } catch (_) { failed++; }
      if (mounted) setState(() => _uploadedCount++);
    }

    setState(() { _isUploading = false; _selectedFiles = []; });
    if (!mounted) return;

    _showUploadResult(success, rejected, failed);
    if (success > 0) Navigator.pop(context);
  }

  void _showUploadResult(int success, int rejected, int failed) {
    final allGood = rejected == 0 && failed == 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(allGood ? Icons.check_circle : Icons.warning_rounded,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text([
          if (success > 0) '$success uploaded',
          if (rejected > 0) '$rejected rejected',
          if (failed > 0)   '$failed failed',
        ].join(' · '))),
      ]),
      backgroundColor: allGood ? _green : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasFiles      = _selectedFiles.isNotEmpty;
    final isRecommended = _selectedFiles.length >= _minRecommended;
    final progress      = _totalCount > 0 ? _uploadedCount / _totalCount : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.categoryName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('Upload Images',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
        backgroundColor: _green, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isUploading
          ? _UploadingView(progress: progress,
              uploaded: _uploadedCount, total: _totalCount)
          : _IdleView(
              selectedCount: _selectedFiles.length,
              minRecommended: _minRecommended,
              isRecommended: isRecommended,
              hasFiles: hasFiles,
              onPreview: _showPreviewSheet,
              onClear: () => setState(() => _selectedFiles = []),
            ),
      floatingActionButton: _isUploading
          ? null
          : Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              FloatingActionButton.extended(
                heroTag: 'select',
                onPressed: _selectImages,
                backgroundColor: _green,
                elevation: 3,
                icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
                label: const Text('Select Images',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              if (hasFiles) ...[
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'upload',
                  onPressed: _confirmAndUpload,
                  backgroundColor: isRecommended ? Colors.blue : Colors.orange,
                  elevation: 3,
                  icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                  label: Text('Upload ${_selectedFiles.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
    );
  }
}

// ── Idle view (no upload in progress) ────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final int     selectedCount, minRecommended;
  final bool    isRecommended, hasFiles;
  final VoidCallback onPreview, onClear;

  const _IdleView({
    required this.selectedCount, required this.minRecommended,
    required this.isRecommended, required this.hasFiles,
    required this.onPreview, required this.onClear,
  });

  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // ── Hero icon ─────────────────────────────────────────────────
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: hasFiles
                    ? [Colors.orange.shade400, Colors.orange.shade700]
                    : [_green, const Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(
                color: (hasFiles ? Colors.orange : _green).withOpacity(0.4),
                blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Icon(
            hasFiles ? Icons.photo_library_rounded : Icons.add_photo_alternate_outlined,
            size: 46, color: Colors.white),
        ),
        const SizedBox(height: 24),

        // ── Title ─────────────────────────────────────────────────────
        Text(
          hasFiles ? 'Ready to Upload' : 'Select PNG or SVG images',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
              color: Colors.black87),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // ── Count indicator ───────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: (isRecommended ? _green : Colors.orange).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: (isRecommended ? _green : Colors.orange).withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isRecommended ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: isRecommended ? _green : Colors.orange),
            const SizedBox(width: 6),
            Text(
              selectedCount == 0
                  ? 'No images selected'
                  : '$selectedCount selected · ${isRecommended
                      ? 'Ready!' : '${minRecommended - selectedCount} more recommended'}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: isRecommended ? _green : Colors.orange),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Recommended: $minRecommended+ images per category',
            style: TextStyle(fontSize: 11, color: Colors.grey[500],
                fontStyle: FontStyle.italic)),

        // ── Preview / Clear buttons ───────────────────────────────────
        if (hasFiles) ...[
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: onPreview,
              icon: const Icon(Icons.preview_rounded, size: 18),
              label: const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
          ]),
        ] else ...[
          const SizedBox(height: 16),
          Text('Only PNG and SVG files are accepted\nImages are scanned before uploading',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400], height: 1.5)),
        ],

        // Bottom spacing for FABs
        const SizedBox(height: 100),
      ]),
    ),
  );
}

// ── Uploading progress view ───────────────────────────────────────────────────

class _UploadingView extends StatelessWidget {
  final double progress;
  final int uploaded, total;
  const _UploadingView({required this.progress, required this.uploaded, required this.total});
  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Animated upload icon
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_green, Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: _green.withOpacity(0.4),
                blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.cloud_upload_rounded, size: 44, color: Colors.white),
        ),
        const SizedBox(height: 28),
        const Text('Uploading Images…',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('$uploaded of $total processed',
            style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const SizedBox(height: 24),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation(_green),
          ),
        ),
        const SizedBox(height: 12),
        Text('${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                color: _green)),
        const SizedBox(height: 20),
        Text('Scanning each image for content safety…',
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ]),
    ),
  );
}

// ── Preview bottom sheet ──────────────────────────────────────────────────────

class _PreviewSheet extends StatelessWidget {
  final List<Map<String, dynamic>> selectedFiles;
  final void Function(int index) onRemove;
  final VoidCallback onClearAll, onUpload;

  const _PreviewSheet({
    required this.selectedFiles,
    required this.onRemove,
    required this.onClearAll,
    required this.onUpload,
  });

  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // ── Handle + header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.photo_library_rounded,
                      color: _green, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Preview — ${selectedFiles.length} image${selectedFiles.length != 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Text('Tap × to remove an image',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                const Spacer(),
                TextButton.icon(
                  onPressed: onClearAll,
                  icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.red),
                  label: const Text('Clear all',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
            ]),
          ),

          // ── Image grid ──────────────────────────────────────────────
          Expanded(
            child: GridView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: selectedFiles.length,
              itemBuilder: (_, index) {
                final file  = selectedFiles[index]['file'];
                final isSvg = selectedFiles[index]['isSvg'] as bool;
                final name  = (selectedFiles[index]['name'] as String);
                return Stack(fit: StackFit.expand, children: [
                  // Image tile
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!)),
                      child: isSvg
                          ? Column(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_aspect_ratio_rounded,
                                    color: Colors.blue[300], size: 32),
                                const SizedBox(height: 4),
                                const Text('SVG', style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                              ])
                          : Image.memory(file.bytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image, color: Colors.grey)),
                    ),
                  ),
                  // Name overlay
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12))),
                      child: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  // Remove button
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(index),
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 4)]),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),

          // ── Upload button ────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.cloud_upload_rounded,
                    color: Colors.white, size: 20),
                label: Text(
                    'Upload ${selectedFiles.length} Image${selectedFiles.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 3),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}