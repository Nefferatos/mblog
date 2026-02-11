import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateBlogPage extends StatefulWidget {
  const CreateBlogPage({super.key});

  @override
  State<CreateBlogPage> createState() => _CreateBlogPageState();
}

class _CreateBlogPageState extends State<CreateBlogPage> {
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final List<XFile> pickedImages = [];
  final List<Uint8List> webImageBytes = [];
  bool loading = false;
  static const int maxImageBytes = 15 * 1024 * 1024;
  static const int maxImagesCount = 10;

  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  Future<void> pickImages() async {
    final selected = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (selected.isEmpty) return;

    final remainingSlots = maxImagesCount - pickedImages.length;
    final imagesToAdd = selected.take(remainingSlots).toList();

    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 10 images allowed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final validImages = <XFile>[];
    final validBytes = <Uint8List>[];
    for (final image in imagesToAdd) {
      final imageSize = await image.length();
      if (imageSize > maxImageBytes) {
        continue;
      }
      validImages.add(image);
      if (kIsWeb) {
        validBytes.add(await image.readAsBytes());
      }
    }

    if (!mounted) return;
    setState(() {
      pickedImages.addAll(validImages);
      if (kIsWeb) {
        webImageBytes.addAll(validBytes);
      }
    });

    if (selected.length > remainingSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only 10 images can be selected'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    if (validImages.length < imagesToAdd.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some images were skipped (over 15 MB)'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void removeImageAt(int index) {
    setState(() {
      pickedImages.removeAt(index);
      if (kIsWeb && index < webImageBytes.length) {
        webImageBytes.removeAt(index);
      }
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

    setState(() => loading = true);

    try {
      final imageUrls = <String>[];
      for (int i = 0; i < pickedImages.length; i++) {
        final fileName = 'blog-${DateTime.now().millisecondsSinceEpoch}-$i.png';
        final uploadedUrl = kIsWeb
            ? await storage.uploadImage(webImageBytes[i], fileName)
            : await storage.uploadImage(File(pickedImages[i].path), fileName);
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          imageUrls.add(uploadedUrl);
        }
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'User not logged in';

      final displayName =
          user.userMetadata?['display_name'] as String? ??
          user.userMetadata?['full_name'] as String? ??
          'Anonymous';

      final newBlog = await service.createBlog(
        titleController.text,
        contentController.text,
        user.id,
        username: displayName,
        imageUrls: imageUrls,
      );

      if (!mounted) return;
      Navigator.pop(context, newBlog);
    } catch (e) {
      debugPrint('Error creating blog: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating blog: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _buildHeaderPreview() {
    if (pickedImages.isEmpty) {
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

    if (kIsWeb && webImageBytes.isNotEmpty) {
      return Image.memory(webImageBytes.first, fit: BoxFit.cover);
    }
    return Image.file(File(pickedImages.first.path), fit: BoxFit.cover);
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
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
          'NEW STORY',
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
              onPressed: loading ? null : submit,
              style: TextButton.styleFrom(
                backgroundColor: colorBlack,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: loading
                  ? const SizedBox(
                      height: 15,
                      width: 15,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Publish',
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
                  border: pickedImages.isEmpty
                      ? Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildHeaderPreview(),
                      if (pickedImages.isNotEmpty) ...[
                        Container(color: Colors.black26),
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Text(
                            '${pickedImages.length} image(s) selected',
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
            if (pickedImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: pickedImages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 92,
                              height: 92,
                              child: kIsWeb
                                  ? Image.memory(webImageBytes[index], fit: BoxFit.cover)
                                  : Image.file(File(pickedImages[index].path), fit: BoxFit.cover),
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
                        ],
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
        onPressed: pickedImages.length >= maxImagesCount ? null : pickImages,
        backgroundColor: colorBlack,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add Images'),
      ),
    );
  }
}
