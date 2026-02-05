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

String? get imagePublicUrl {
  if (widget.comment.imageUrl == null || widget.comment.imageUrl!.isEmpty) return null;
  if (widget.comment.imageUrl!.startsWith('http')) return widget.comment.imageUrl;
  return Supabase.instance.client.storage
      .from('comment-images')
      .getPublicUrl(widget.comment.imageUrl!);
}

String? get avatarPublicUrl {
  if (widget.comment.avatarUrl == null || widget.comment.avatarUrl!.isEmpty) return null;
  if (widget.comment.avatarUrl!.startsWith('http')) return widget.comment.avatarUrl;
  return Supabase.instance.client.storage
      .from('avatars') 
      .getPublicUrl(widget.comment.avatarUrl!);
}


  Future<void> _confirmDelete(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Delete Comment?"),
          content: const Text("Are you sure you want to remove this?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (widget.onDelete != null) widget.onDelete!();
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.comment.content);
    XFile? tempImage;
    Uint8List? tempWebBytes;

    return showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Comment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: controller, maxLines: null, decoration: const InputDecoration(border: OutlineInputBorder())),
                if (tempImage != null) ...[
                  const SizedBox(height: 10),
                  kIsWeb ? Image.memory(tempWebBytes!, height: 100) : Image.file(File(tempImage!.path), height: 100),
                ],
                TextButton.icon(
                  onPressed: () async {
                    final img = await _picker.pickImage(source: ImageSource.gallery);
                    if (img != null) {
                      final bytes = await img.readAsBytes();
                      setDialogState(() { tempImage = img; tempWebBytes = bytes; });
                    }
                  },
                  icon: const Icon(Icons.image),
                  label: const Text("Change Image"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                widget.onUpdate(controller.text, tempImage);
                Navigator.pop(dialogContext);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuthor = widget.comment.userId.trim() == widget.currentUserId.trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: widget.comment.avatarUrl != null && widget.comment.avatarUrl!.isNotEmpty
                            ? NetworkImage(widget.comment.avatarUrl!)
                            : null,
                        child: (widget.comment.avatarUrl == null || widget.comment.avatarUrl!.isEmpty)
                            ? const Icon(Icons.person, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.comment.userName.isNotEmpty ? widget.comment.userName : "Anonymous",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                if (isAuthor)
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showEditDialog(context)),
                      IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _confirmDelete(context)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.comment.content),
            if (imagePublicUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(imagePublicUrl!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}