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
  XFile? pickedImage;
  Uint8List? webImageBytes;
  bool loading = false;

  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  void pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        setState(() {
          pickedImage = image;
          webImageBytes = bytes;
        });
      } else {
        setState(() => pickedImage = image);
      }
    }
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
      String? imageUrl;

      if (pickedImage != null) {
        if (kIsWeb) {
          imageUrl = await storage.uploadImage(
            webImageBytes!,
            'blog-${DateTime.now().millisecondsSinceEpoch}.png',
          );
        } else {
          imageUrl = await storage.uploadImage(
            File(pickedImage!.path),
            'blog-${DateTime.now().millisecondsSinceEpoch}.png',
          );
        }
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'User not logged in';

      final displayName = user.userMetadata?['display_name'] as String? ?? 
                          user.userMetadata?['full_name'] as String? ?? 
                          'Anonymous';

      final newBlog = await service.createBlog(
        titleController.text,
        contentController.text,
        user.id,
        username: displayName,
        imageUrl: imageUrl,
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
                  ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Publish', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  border: pickedImage == null ? Border.all(color: Colors.grey.shade300, style: BorderStyle.solid) : null,
                ),
                child: pickedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            kIsWeb 
                              ? Image.memory(webImageBytes!, fit: BoxFit.cover) 
                              : Image.file(File(pickedImage!.path), fit: BoxFit.cover),
                            Container(color: Colors.black12),
                            const Center(child: Icon(Icons.sync, color: Colors.white, size: 30)),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_photo_alternate_outlined, size: 40, color: colorGrey),
                          SizedBox(height: 12),
                          Text('Add a cover photo', style: TextStyle(color: colorGrey, fontWeight: FontWeight.w500)),
                        ],
                      ),
              ),
            ),
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
    );
  }
}