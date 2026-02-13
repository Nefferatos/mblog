import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/comment.dart';

class CommentTile extends StatefulWidget {
  final Comment comment;
  final String currentUserId;
  final VoidCallback? onDelete;
  final Function(
    String updatedContent,
    List<XFile>? newImages,
    List<String>? retainedExistingImageUrls,
  ) onUpdate;

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
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  List<String> get imagePublicUrls {
    if (widget.comment.imageUrls.isEmpty) return [];
    return widget.comment.imageUrls.map((url) {
      if (url.startsWith('http')) return url;
      return Supabase.instance.client.storage.from('comment-images').getPublicUrl(url);
    }).toList();
  }

  String? get avatarPublicUrl {
    if (widget.comment.avatarUrl == null || widget.comment.avatarUrl!.isEmpty) return null;
    if (widget.comment.avatarUrl!.startsWith('http')) return widget.comment.avatarUrl;
    return Supabase.instance.client.storage.from('blog-images').getPublicUrl(widget.comment.avatarUrl!);
  }

  void _showEditDialog() {
    final controller = TextEditingController(text: widget.comment.content);
    final List<XFile> tempImages = [];
    final List<Uint8List> tempWebBytes = [];
    final List<String> editableExistingImages = List<String>.from(imagePublicUrls);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasSelectedImages = tempImages.isNotEmpty;
          final hasExistingImages = editableExistingImages.isNotEmpty;
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 24,
              right: 24,
              top: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EDIT COMMENT',
                  style: TextStyle(
                    color: colorBlack,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                if (hasSelectedImages || hasExistingImages) ...[
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: editableExistingImages.length + tempImages.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final existingCount = editableExistingImages.length;
                        final selectedCount = tempImages.length;
                        final addTileIndex = existingCount + selectedCount;

                        if (index == addTileIndex) {
                          return _buildAddImageTile(
                            onTap: () async {
                              final imgs = await _picker.pickMultiImage(
                                imageQuality: 70,
                              );
                              if (imgs.isEmpty) return;
                              final bytes = await Future.wait(
                                imgs.map((e) => e.readAsBytes()),
                              );
                              setDialogState(() {
                                tempImages.addAll(imgs);
                                tempWebBytes.addAll(bytes);
                              });
                            },
                          );
                        }

                        if (index < existingCount) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  editableExistingImages[index],
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    width: 80,
                                    height: 80,
                                    color: colorBubble,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: colorGrey,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      editableExistingImages.removeAt(index);
                                    });
                                  },
                                  child: const CircleAvatar(
                                    radius: 12,
                                    backgroundColor: colorBlack,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        final selectedIndex = index - existingCount;
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildPickedImage(
                                tempImages[selectedIndex],
                                webBytes: selectedIndex < tempWebBytes.length
                                    ? tempWebBytes[selectedIndex]
                                    : null,
                                width: 80,
                                height: 80,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    tempImages.removeAt(selectedIndex);
                                    tempWebBytes.removeAt(selectedIndex);
                                  });
                                },
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: colorBlack,
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: () async {
                        final imgs = await _picker.pickMultiImage(
                          imageQuality: 70,
                        );
                        if (imgs.isEmpty) return;
                        final bytes = await Future.wait(
                          imgs.map((e) => e.readAsBytes()),
                        );
                        setDialogState(() {
                          tempImages.addAll(imgs);
                          tempWebBytes.addAll(bytes);
                        });
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'Write a comment...',
                          filled: true,
                          fillColor: colorDirtyWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: colorBlack),
                      onPressed: () {
                        widget.onUpdate(
                          controller.text,
                          tempImages.isNotEmpty ? tempImages : null,
                          editableExistingImages,
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuthor = widget.comment.userId.trim() == widget.currentUserId.trim();
    final bool isEdited = widget.comment.updatedAt != null &&
        (widget.comment.createdAt == null ||
            !widget.comment.updatedAt!.isAtSameMomentAs(widget.comment.createdAt!));

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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.comment.userName.isNotEmpty ? widget.comment.userName : "Anonymous",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorBlack),
                                      ),
                                    ),
                                    if (isAuthor) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          "YOU",
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: colorGrey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                if (isEdited)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: colorDirtyWhite,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          "Edited",
                                          style: TextStyle(
                                            color: colorGrey,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatDateTime(widget.comment.updatedAt!),
                                        style: const TextStyle(color: colorGrey, fontSize: 10),
                                      ),
                                    ],
                                  )
                                else if (widget.comment.createdAt != null)
                                  Text(
                                    _formatDateTime(widget.comment.createdAt!),
                                    style: const TextStyle(color: colorGrey, fontSize: 10),
                                  ),
                              ],
                            ),
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
                      if (imagePublicUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildCommentImageGrid(imagePublicUrls),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickedImage(
    XFile image, {
    Uint8List? webBytes,
    double? width,
    double? height,
  }) {
    if (kIsWeb) {
      if (webBytes != null) {
        return Image.memory(webBytes, width: width, height: height, fit: BoxFit.contain);
      }
      return FutureBuilder<Uint8List>(
        future: image.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              width: width,
              height: height,
              fit: BoxFit.contain,
            );
          }
          return Container(
            width: width,
            height: height,
            color: colorDirtyWhite,
            child: const Center(
              child: SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }
    return Image.file(
      File(image.path),
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }

  Widget _buildAddImageTile({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: colorDirtyWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorGrey.withOpacity(0.35)),
        ),
        child: const Icon(Icons.add, color: colorGrey),
      ),
    );
  }

  Widget _buildCommentImageGrid(List<String> urls) {
    final count = urls.length;
    final shownCount = count > 4 ? 4 : count;
    const spacing = 6.0;

    if (shownCount == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: GestureDetector(
            onTap: () => _openImageViewer(urls, 0),
            child: _commentImage(urls.first, fit: BoxFit.contain),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (shownCount / 2).ceil();
        final tileSize = (constraints.maxWidth - spacing) / 2;
        final totalHeight = rows * tileSize + (rows - 1) * spacing;

        return SizedBox(
          height: totalHeight,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: shownCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final image = ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _commentImage(urls[index], fit: BoxFit.cover),
              );
              Widget tile = image;
              if (index == shownCount - 1 && count > shownCount) {
                tile = Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '+${count - shownCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return GestureDetector(
                onTap: () => _openImageViewer(urls, index),
                behavior: HitTestBehavior.opaque,
                child: tile,
              );
            },
          ),
        );
      },
    );
  }

  Widget _commentImage(String url, {BoxFit fit = BoxFit.contain}) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: colorBubble,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: colorBubble,
        child: const Center(
          child: Icon(Icons.broken_image, color: colorGrey),
        ),
      ),
    );
  }

  void _openImageViewer(List<String> urls, int initialIndex) {
    var currentIndex = initialIndex;
    final pageController = PageController(initialPage: initialIndex);

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => StatefulBuilder(
        builder: (context, setViewerState) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.black,
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: urls.length,
                          onPageChanged: (index) {
                            setViewerState(() => currentIndex = index);
                          },
                          itemBuilder: (context, index) {
                            return InteractiveViewer(
                              child: Image.network(
                                urls[index],
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  color: Colors.black,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.white70,
                                    size: 40,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (urls.length > 1)
                        Container(
                          height: 78,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          color: Colors.black87,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: urls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final isSelected = index == currentIndex;
                              return GestureDetector(
                                onTap: () {
                                  pageController.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeInOut,
                                  );
                                  setViewerState(() => currentIndex = index);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white24,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: SizedBox(
                                      width: 62,
                                      height: 62,
                                      child: Image.network(
                                        urls[index],
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  if (urls.length > 1) ...[
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 78,
                      child: Center(
                        child: _viewerNavButton(
                          icon: Icons.arrow_back_ios_new,
                          onTap: () {
                            if (currentIndex <= 0) return;
                            pageController.previousPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 78,
                      child: Center(
                        child: _viewerNavButton(
                          icon: Icons.arrow_forward_ios,
                          onTap: () {
                            if (currentIndex >= urls.length - 1) return;
                            pageController.nextPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      pageController.dispose();
    });
  }

  Widget _viewerNavButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day}/${dt.month}/${dt.year} $hour:$minute $suffix';
  }
}
