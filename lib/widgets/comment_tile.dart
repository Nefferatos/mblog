import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/comment.dart';

class CommentTile extends StatefulWidget {
  final Comment comment;
  final String currentUserId;
  final VoidCallback? onDelete;
  final Function(String updatedContent, XFile? newImage) onUpdate;

  const CommentTile({
    super.key,
    required this.comment,
    required this.currentUserId,
    this.onDelete,
    required this.onUpdate,
  });

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  final ImagePicker _picker = ImagePicker();
  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorBubble = Color(0xFFF2F3F5);

  String? get imagePublicUrl {
    if (widget.comment.imageUrl == null || widget.comment.imageUrl!.isEmpty) return null;
    if (widget.comment.imageUrl!.startsWith('http')) return widget.comment.imageUrl;
    return Supabase.instance.client.storage.from('comment-images').getPublicUrl(widget.comment.imageUrl!);
  }

  String? get avatarPublicUrl {
    if (widget.comment.avatarUrl == null || widget.comment.avatarUrl!.isEmpty) return null;
    if (widget.comment.avatarUrl!.startsWith('http')) return widget.comment.avatarUrl;
    return Supabase.instance.client.storage.from('blog-images').getPublicUrl(widget.comment.avatarUrl!);
  }

  void _showEditDialog() {
    final controller = TextEditingController(text: widget.comment.content);
    XFile? tempImage;
    Uint8List? tempWebBytes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Edit Comment", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: "Update your reply...",
                  fillColor: colorBubble,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              if (tempImage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb ? Image.memory(tempWebBytes!, height: 120) : Image.file(File(tempImage!.path), height: 120),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final img = await _picker.pickImage(source: ImageSource.gallery);
                      if (img != null) {
                        final bytes = await img.readAsBytes();
                        setDialogState(() { tempImage = img; tempWebBytes = bytes; });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text("Update Image"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      widget.onUpdate(controller.text, tempImage);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: colorBlack, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("Save Changes"),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuthor = widget.comment.userId.trim() == widget.currentUserId.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorBubble,
            backgroundImage: avatarPublicUrl != null ? NetworkImage(avatarPublicUrl!) : null,
            child: avatarPublicUrl == null ? const Icon(Icons.person, color: colorGrey, size: 20) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorBubble,
                    borderRadius: BorderRadius.only(
                      topRight: const Radius.circular(16),
                      bottomLeft: const Radius.circular(16),
                      bottomRight: const Radius.circular(16),
                      topLeft: isAuthor ? const Radius.circular(16) : Radius.zero,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.comment.userName.isNotEmpty ? widget.comment.userName : "Anonymous",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorBlack),
                          ),
                          if (isAuthor)
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.more_horiz, size: 18, color: colorGrey),
                              onSelected: (value) {
                                if (value == 'edit') _showEditDialog();
                                if (value == 'delete') widget.onDelete?.call();
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text("Edit", style: TextStyle(fontSize: 14))),
                                const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(fontSize: 14, color: Colors.red))),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.comment.content,
                        style: const TextStyle(fontSize: 14, height: 1.3, color: colorBlack),
                      ),
                    ],
                  ),
                ),
                if (imagePublicUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imagePublicUrl!,
                        width: MediaQuery.of(context).size.width * 0.6,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(width: 100, height: 100, color: colorBubble);
                        },
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 8),
                  child: Text("Just now", style: TextStyle(color: colorGrey, fontSize: 10)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}