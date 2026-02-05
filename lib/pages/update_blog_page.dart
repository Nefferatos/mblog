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

  dynamic pickedImage;
  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();
  bool isLoading = false;

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    titleController.text = widget.blog.title;
    contentController.text = widget.blog.content;
  }

  Future<void> pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;

    if (kIsWeb) {
      final bytes = await image.readAsBytes();
      setState(() => pickedImage = bytes);
    } else {
      setState(() => pickedImage = File(image.path));
    }
  }

  Future<String?> uploadPickedImage() async {
    if (pickedImage == null) return widget.blog.imageUrl;

    String fileName;
    if (kIsWeb) {
      fileName = 'web_${DateTime.now().millisecondsSinceEpoch}.png';
    } else {
      fileName = (pickedImage as File).path.split('/').last;
    }

    return await storage.uploadImage(pickedImage, fileName);
  }

  Future<void> submit() async {
    setState(() => isLoading = true);
    try {
      final imageUrl = await uploadPickedImage();

      await service.updateBlog(
        widget.blog.id,
        title: titleController.text,
        content: contentController.text,
        imageUrl: imageUrl,
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

  Future<void> deleteBlog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Post?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("This action cannot be undone. Are you sure?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: colorGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await service.deleteBlog(widget.blog.id);
    if (!mounted) return;
    Navigator.pop(context, true);
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
          "EDIT POST",
          style: TextStyle(color: colorBlack, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14),
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
                  ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              onTap: pickImage,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: colorDirtyWhite,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImagePreview(),
                      Container(color: Colors.black26),
                      const Center(
                        child: CircleAvatar(
                          backgroundColor: Colors.white70,
                          child: Icon(Icons.camera_alt_outlined, color: colorBlack),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            TextField(
              controller: titleController,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: colorBlack),
              decoration: const InputDecoration(
                hintText: 'Title',
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
                hintText: 'Edit your story...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 40),

            Center(
              child: OutlinedButton.icon(
                onPressed: deleteBlog,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text("Delete Post"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (pickedImage != null) {
      return kIsWeb
          ? Image.memory(pickedImage as Uint8List, fit: BoxFit.cover)
          : Image.file(pickedImage as File, fit: BoxFit.cover);
    } else if (widget.blog.imageUrl != null) {
      return Image.network(widget.blog.imageUrl!, fit: BoxFit.cover);
    }
    return Container(color: colorDirtyWhite);
  }
}