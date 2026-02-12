import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/blog.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

class UpdateBlogPage extends StatefulWidget {
  final Blog blog;
  const UpdateBlogPage({super.key, required this.blog});

  @override
  State<UpdateBlogPage> createState() => _UpdateBlogPageState();
}

class _UpdateBlogPageState extends State<UpdateBlogPage> {
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  
  // Keep existing and newly selected images in one list for unified preview/upload.
  List<Map<String, dynamic>> allImages = [];
  
  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();
  bool isLoading = false;
  static const int maxImageBytes = 15 * 1024 * 1024;
  static const int maxImagesCount = 10;

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    titleController.text = widget.blog.title;
    contentController.text = widget.blog.content;
    
    // Initialize existing images into our unified list
    for (var url in widget.blog.imageUrls) {
      allImages.add({'type': 'network', 'value': url});
    }
    // Fallback for old single image model
    if (allImages.isEmpty && widget.blog.imageUrl != null && widget.blog.imageUrl!.isNotEmpty) {
      allImages.add({'type': 'network', 'value': widget.blog.imageUrl});
    }
  }

  Future<void> pickImages() async {
    final selected = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (selected.isEmpty) return;

    final remainingSlots = maxImagesCount - allImages.length;
    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 images allowed'), backgroundColor: Colors.red),
      );
      return;
    }

    final imagesToAdd = selected.take(remainingSlots).toList();
    final localItems = <Map<String, dynamic>>[];

    for (final image in imagesToAdd) {
      final imageSize = await image.length();
      if (imageSize > maxImageBytes) continue;
      final Uint8List bytes = await image.readAsBytes();
      localItems.add({
        'type': 'local',
        'file': image,
        'bytes': bytes,
      });
    }

    if (!mounted) return;
    setState(() => allImages.addAll(localItems));

    if (selected.length > remainingSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only 10 images can be selected'), backgroundColor: Colors.orange),
      );
    }
    if (localItems.length < imagesToAdd.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some images were skipped (over 15 MB)'), backgroundColor: Colors.orange),
      );
    }
  }

  void removeImageAt(int index) => setState(() => allImages.removeAt(index));

  void reorderImage(int oldIndex, int newIndex) {
    final imagesCount = allImages.length;
    if (oldIndex >= imagesCount) return;
    setState(() {
      if (newIndex > imagesCount) newIndex = imagesCount;
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = allImages.removeAt(oldIndex);
      allImages.insert(newIndex, moved);
    });
  }

  Future<void> submit() async {
    if (titleController.text.trim().isEmpty || contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in both title and content'),
          backgroundColor: colorBlack,
        ),
      );
      return;
    }
    setState(() => isLoading = true);
    
    try {
      final List<String> finalUrls = [];

      for (var item in allImages) {
        if (item['type'] == 'network') {
          finalUrls.add(item['value']);
        } else {
          final xfile = item['file'] as XFile;
          final ext = _extensionFromName(xfile.name);
          final mimeType = _resolveMimeType(xfile, ext);
          final fileName = 'blog-${DateTime.now().millisecondsSinceEpoch}-${allImages.indexOf(item)}.$ext';
          final uploadedUrl = kIsWeb
              ? await storage.uploadImage(
                  item['bytes'],
                  fileName,
                  contentType: mimeType,
                )
              : await storage.uploadImage(
                  File(xfile.path),
                  fileName,
                  contentType: mimeType,
                );
          
          if (uploadedUrl != null) finalUrls.add(uploadedUrl);
        }
      }

      final success = await service.updateBlog(
        widget.blog.id,
        title: titleController.text,
        content: contentController.text,
        imageUrls: finalUrls,
      );
      if (!success) {
        throw Exception('Update failed');
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        widget.blog.copyWith(
          title: titleController.text,
          content: contentController.text,
          imageUrls: finalUrls,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildHeaderPreview() {
    if (allImages.isEmpty) {
      return Container(
        color: colorDirtyWhite,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 40, color: colorGrey),
              SizedBox(height: 12),
              Text(
                'Add cover images',
                style: TextStyle(color: colorGrey, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 6),
              Text(
                'Up to 10 images, each max 15 MB',
                style: TextStyle(color: colorGrey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    final first = allImages.first;
    if (first['type'] == 'network') {
      return Image.network(first['value'], fit: BoxFit.cover);
    }
    if (kIsWeb) {
      return Image.memory(first['bytes'], fit: BoxFit.cover);
    }
    return Image.file(File(first['file'].path), fit: BoxFit.cover);
  }

  Widget _buildThumbnail(Map<String, dynamic> item) {
    if (item['type'] == 'network') {
      return Image.network(item['value'], fit: BoxFit.cover);
    }
    if (kIsWeb) {
      return Image.memory(item['bytes'], fit: BoxFit.cover);
    }
    return Image.file(File(item['file'].path), fit: BoxFit.cover);
  }

  String _resolveMimeType(XFile file, String ext) {
    final fromPicker = file.mimeType?.trim();
    if (fromPicker != null && fromPicker.isNotEmpty) {
      return fromPicker;
    }
    return _mimeTypeFromExtension(ext);
  }

  String _extensionFromName(String? name) {
    if (name == null || !name.contains('.')) return 'jpg';
    final ext = name.split('.').last.toLowerCase().trim();
    if (ext.isEmpty || ext.length > 8) return 'jpg';
    return ext;
  }

  String _mimeTypeFromExtension(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'avif':
        return 'image/avif';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: colorBlack),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'EDIT STORY',
          style: TextStyle(
            color: colorBlack,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 14,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: TextButton(
              onPressed: isLoading ? null : submit,
              style: TextButton.styleFrom(
                backgroundColor: colorBlack,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 15,
                      width: 15,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Update',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            GestureDetector(
              onTap: pickImages,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: colorDirtyWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: allImages.isEmpty
                      ? Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildHeaderPreview(),
                      if (allImages.isNotEmpty) ...[
                        Container(color: Colors.black26),
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Text(
                            '${allImages.length} image(s) selected',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Image preview (up to 10 images, max 15 MB each)',
              style: TextStyle(color: colorGrey, fontSize: 12),
            ),
            if (allImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  onReorder: reorderImage,
                  itemCount: allImages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == allImages.length) {
                      return Padding(
                        key: const ValueKey('add_tile_update_blog'),
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: allImages.length >= maxImagesCount ? null : pickImages,
                          child: Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: colorDirtyWhite,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colorGrey.withOpacity(0.35)),
                            ),
                            child: const Icon(Icons.add, color: colorGrey),
                          ),
                        ),
                      );
                    }

                    final item = allImages[index];
                    final itemKey = item['type'] == 'network'
                        ? '${item['type']}-${item['value']}'
                        : '${item['type']}-${(item['file'] as XFile).path}';
                    return Padding(
                      key: ValueKey(itemKey),
                      padding: const EdgeInsets.only(right: 10),
                      child: ReorderableDragStartListener(
                        index: index,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 92,
                                height: 92,
                                child: _buildThumbnail(item),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => removeImageAt(index),
                                child: const CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close, size: 13, color: Colors.white),
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 4,
                              bottom: 4,
                              child: CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.black45,
                                child: Icon(Icons.drag_indicator, size: 13, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 32),
            TextField(
              controller: titleController,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: colorBlack),
              decoration: const InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: Color(0xFFE0E0E0)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const Divider(height: 40, thickness: 1),
            TextField(
              controller: contentController,
              maxLines: null,
              style: const TextStyle(fontSize: 18, height: 1.6, color: colorBlack),
              decoration: const InputDecoration(
                hintText: 'Tell your story...',
                hintStyle: TextStyle(color: colorGrey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: allImages.length >= maxImagesCount ? null : pickImages,
        backgroundColor: colorBlack,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add Images'),
      ),
    );
  }
}
