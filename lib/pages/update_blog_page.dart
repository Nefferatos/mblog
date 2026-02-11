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
  
  // To support reordering, we combine existing and new images into a single list of objects
  List<Map<String, dynamic>> allImages = [];
  
  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();
  bool isLoading = false;
  static const int maxImageBytes = 15 * 1024 * 1024;
  static const int maxImagesCount = 10;

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF8F9FA);

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

    if (allImages.length >= maxImagesCount) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 images allowed'), backgroundColor: Colors.red),
      );
      return;
    }

    final remainingSlots = maxImagesCount - allImages.length;
    final imagesToAdd = selected.take(remainingSlots).toList();

    for (final image in imagesToAdd) {
      final imageSize = await image.length();
      if (imageSize > maxImageBytes) continue;
      
      final Uint8List bytes = await image.readAsBytes();
      setState(() {
        allImages.add({
          'type': 'local',
          'file': image,
          'bytes': bytes, // stored for web and preview
        });
      });
    }
  }

  void removeImageAt(int index) => setState(() => allImages.removeAt(index));

  Future<void> submit() async {
    if (titleController.text.isEmpty) return;
    setState(() => isLoading = true);
    
    try {
      final List<String> finalUrls = [];

      for (var item in allImages) {
        if (item['type'] == 'network') {
          finalUrls.add(item['value']);
        } else {
          // Upload new local image
          final fileName = 'blog-${DateTime.now().millisecondsSinceEpoch}-${allImages.indexOf(item)}.png';
          final uploadedUrl = kIsWeb
              ? await storage.uploadImage(item['bytes'], fileName)
              : await storage.uploadImage(File(item['file'].path), fileName);
          
          if (uploadedUrl != null) finalUrls.add(uploadedUrl);
        }
      }

      await service.updateBlog(
        widget.blog.id,
        title: titleController.text,
        content: contentController.text,
        imageUrls: finalUrls,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- UI COMPONENTS ---

  Widget _buildHeroPreview() {
    if (allImages.isEmpty) {
      return Container(
        color: colorDirtyWhite,
        child: const Icon(Icons.image_outlined, size: 48, color: Colors.grey),
      );
    }
    final first = allImages.first;
    if (first['type'] == 'network') {
      return Image.network(first['value'], fit: BoxFit.cover);
    }
    return Image.memory(first['bytes'], fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: colorBlack, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("Edit Story", style: TextStyle(color: colorBlack, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: isLoading ? null : submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorBlack,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Save"),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildHeroPreview(),
                  Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black45]))),
                  const Positioned(bottom: 16, left: 16, child: Text("COVER IMAGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("GALLERY (Hold to reorder)", style: TextStyle(fontWeight: FontWeight.bold, color: colorGrey, fontSize: 11)),
                  const SizedBox(height: 12),
                  
                  // REORDERABLE IMAGE LIST
                  SizedBox(
                    height: 100,
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: allImages.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = allImages.removeAt(oldIndex);
                          allImages.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final item = allImages[index];
                        return _buildDraggableThumbnail(index, item);
                      },
                    ),
                  ),

                  const SizedBox(height: 32),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(hintText: 'Story Title', border: InputBorder.none),
                  ),
                  const Divider(height: 32),
                  TextField(
                    controller: contentController,
                    maxLines: null,
                    style: const TextStyle(fontSize: 17, height: 1.6),
                    decoration: const InputDecoration(hintText: 'Tell your story...', border: InputBorder.none),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: allImages.length >= maxImagesCount ? null : pickImages,
        backgroundColor: colorBlack,
        icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
        label: const Text("Add Images", style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildDraggableThumbnail(int index, Map<String, dynamic> item) {
    return ReorderableDragStartListener(
      key: ValueKey(item),
      index: index,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: index == 0 ? Border.all(color: colorBlack, width: 2) : null,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item['type'] == 'network'
                  ? Image.network(item['value'], width: 80, height: 80, fit: BoxFit.cover)
                  : Image.memory(item['bytes'], width: 80, height: 80, fit: BoxFit.cover),
            ),
            if (index == 0)
              Positioned(
                top: 0, left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: const BoxDecoration(color: colorBlack, borderRadius: BorderRadius.only(bottomRight: Radius.circular(8))),
                  child: const Text("TOP", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
            Positioned(
              top: -2, right: -2,
              child: IconButton(
                icon: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white)),
                onPressed: () => removeImageAt(index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}