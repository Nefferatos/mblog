import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import '../models/blog.dart';
import '../models/comment.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../widgets/comment_tile.dart';

class BlogDetailPage extends StatefulWidget {
  final Blog blog;

  const BlogDetailPage({super.key, required this.blog});

  @override
  State<BlogDetailPage> createState() => _BlogDetailPageState();
}

class _BlogDetailPageState extends State<BlogDetailPage> {
  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();

  List<Comment> comments = [];
  bool loading = true;
  bool commentsLoading = false;
  String? userId;
  String usernameDisplay = "Anonymous";
  String? currentUserProfilePic; 
  final TextEditingController commentController = TextEditingController();
  final PageController _carouselController = PageController();
  
  List<XFile> commentImages = [];
  List<Uint8List> commentWebImageBytes = [];
  bool commentLoading = false;
  int _currentCarouselIndex = 0;

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  List<String> get _blogImages {
    final rawImages = widget.blog.imageUrls.isNotEmpty
        ? widget.blog.imageUrls
        : (widget.blog.imageUrl != null && widget.blog.imageUrl!.isNotEmpty
              ? [widget.blog.imageUrl!]
              : <String>[]);

    return rawImages
        .map((img) => _toPublicBlogImageUrl(img) ?? img)
        .where((img) => img.isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    loadUser();
    fetchComments(showPageLoader: true);
  }

  @override
  void dispose() {
    _carouselController.dispose();
    commentController.dispose();
    super.dispose();
  }


  Future<void> loadUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final metadata = user.userMetadata;
      var nextUsername = metadata?['display_name'] ?? metadata?['full_name'] ?? "Anonymous";
      String? nextAvatar = metadata?['avatar_url'];

      try {
        final profile = await Supabase.instance.client.from('profiles').select('username, avatar_url').eq('id', user.id).maybeSingle();
        if (profile != null) {
          if (profile['username'] != null) nextUsername = profile['username'];
          if (profile['avatar_url'] != null) nextAvatar = profile['avatar_url'];
        }
      } catch (e) { debugPrint('Profile error: $e'); }

      if (!mounted) return;
      setState(() {
        userId = user.id;
        usernameDisplay = nextUsername;
        currentUserProfilePic = _toPublicBlogImageUrl(nextAvatar);
      });
    }
  }

  Future<void> fetchComments({bool showPageLoader = false}) async {
    if (!mounted) return;
    setState(() {
      if (showPageLoader) {
        loading = true;
      } else {
        commentsLoading = true;
      }
    });
    try {
      final data = await service.getComments(widget.blog.id);
      final profilesByUserId = await _fetchCommentProfiles(
        data.map((c) => c.userId).toSet(),
      );

      final resolvedComments = await Future.wait(data.map((c) async {
        final profile = profilesByUserId[c.userId];
        final avatarFromProfile = profile?['avatar_url'];
        final usernameFromProfile = profile?['username'];

        var nextComment = c.copyWith(
          userName: c.userName.isNotEmpty
              ? c.userName
              : (usernameFromProfile ?? 'Anonymous'),
          avatarUrl: (avatarFromProfile != null && avatarFromProfile.isNotEmpty)
              ? avatarFromProfile
              : c.avatarUrl,
        );

        final signedImageUrls = await Future.wait(
          nextComment.imageUrls.map((img) async {
            if (img.startsWith("http")) return img;
            return Supabase.instance.client.storage
                .from('comment-images')
                .createSignedUrl(img, 3600);
          }),
        );
        nextComment = nextComment.copyWith(imageUrls: signedImageUrls);
        return nextComment;
      }));
      if (!mounted) return;
      setState(() {
        comments = resolvedComments;
        loading = false;
        commentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        commentsLoading = false;
      });
    }
  }

  Future<Map<String, Map<String, String?>>> _fetchCommentProfiles(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url');

      final profileMap = <String, Map<String, String?>>{};
      for (final row in (rows as List)) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (!userIds.contains(id)) continue;
        profileMap[id] = {
          'username': row['username']?.toString(),
          'avatar_url': row['avatar_url']?.toString(),
        };
      }
      return profileMap;
    } catch (e) {
      debugPrint('Comment profile fallback error: $e');
      return {};
    }
  }

  Future<void> handleSaveOrUpdate({
    Comment? existingComment,
    String? updatedText,
    List<XFile>? newImages,
    List<String>? retainedExistingImageUrls,
  }) async {
    if (userId == null) return;
    final textToSave = (updatedText ?? commentController.text).trim();
    setState(() => commentLoading = true);
    try {
      var finalImagePaths = _normalizeCommentImagePaths(
        existingComment?.imageUrls ?? const [],
      );
      if (existingComment != null && retainedExistingImageUrls != null) {
        finalImagePaths = _normalizeCommentImagePaths(retainedExistingImageUrls);
      }
      final imagesToUpload =
          newImages ?? (existingComment == null ? commentImages : const <XFile>[]);

      if (imagesToUpload.isNotEmpty) {
        final uploadedPaths = <String>[];
        for (var i = 0; i < imagesToUpload.length; i++) {
          final image = imagesToUpload[i];
          final ext = _extensionFromName(image.name);
          final mimeType = _resolveMimeType(image, ext);
          final fileName = 'comment-${DateTime.now().millisecondsSinceEpoch}-$i.$ext';
          await Supabase.instance.client.storage
              .from('comment-images')
              .uploadBinary(
                fileName,
                await image.readAsBytes(),
                fileOptions: FileOptions(contentType: mimeType),
              );
          uploadedPaths.add(fileName);
        }
        finalImagePaths = [...finalImagePaths, ...uploadedPaths];
      } else if (existingComment != null && newImages != null && newImages.isEmpty) {

        finalImagePaths = [];
      }

      final encodedImageField = _encodeCommentImages(finalImagePaths);

      if (existingComment != null) {
        final ok = await service.updateComment(
          existingComment.id,
          textToSave,
          encodedImageField,
        );
        if (!ok) throw Exception('Failed to update comment');
        if (!mounted) return;
        setState(() {
          comments = comments
              .map(
                (c) => c.id == existingComment.id
                    ? c.copyWith(
                        content: textToSave,
                        imageUrls: finalImagePaths,
                        updatedAt: DateTime.now(),
                      )
                    : c,
              )
              .toList();
        });
      } else {
        final created = await service.addComment(
          widget.blog.id,
          textToSave,
          encodedImageField,
          usernameDisplay,
        );
        if (created != null && mounted) {
          setState(() {
            comments = [
              ...comments,
              created.copyWith(
                userName: created.userName.isNotEmpty
                    ? created.userName
                    : usernameDisplay,
                avatarUrl: currentUserProfilePic,
                imageUrls: finalImagePaths,
              ),
            ];
          });
        } else {
          await fetchComments();
        }
      }
      commentController.clear();
      setState(() {
        commentImages = [];
        commentWebImageBytes = [];
      });
    } finally { setState(() => commentLoading = false); }
  }

  Future<void> deleteComment(Comment c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Comment"),
        content: const Text("Are you sure you want to delete this comment?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (c.imageUrls.isNotEmpty) {
        final fileNames = c.imageUrls
            .map((url) => url.split('/').last.split('?').first)
            .where((name) => name.isNotEmpty)
            .toList();
        if (fileNames.isNotEmpty) {
          await Supabase.instance.client.storage
              .from('comment-images')
              .remove(fileNames);
        }
      }
      await service.deleteComment(c.id);
      setState(() => comments.removeWhere((element) => element.id == c.id));
    } catch (e) { debugPrint("Delete error: $e"); }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _buildCommentInputArea(),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: colorBlack))
          : CustomScrollView(
              slivers: [
                _buildSliverCarousel(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_blogImages.length > 1) _buildThumbnailRow(),
                        const SizedBox(height: 24),
                        _buildAuthorHeader(),
                        const SizedBox(height: 24),
                        Text(
                          widget.blog.title,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: colorBlack, height: 1.1),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.blog.content,
                          style: const TextStyle(fontSize: 17, height: 1.7, color: Color(0xFF2D2D2D)),
                        ),
                        const SizedBox(height: 48),
                        const Row(
                          children: [
                            Text("COMMENTS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
                            Expanded(child: Divider(indent: 16, color: colorDirtyWhite)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildCommentsList(),
                        const SizedBox(height: 120), 
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliverCarousel() {
    return SliverAppBar(
      expandedHeight: 400.0,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.white.withOpacity(0.9),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: colorBlack, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          alignment: Alignment.center,
          children: [
            PageView.builder(
              controller: _carouselController,
              onPageChanged: (i) => setState(() => _currentCarouselIndex = i),
              itemCount: _blogImages.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _openImageViewer(index),
                child: Image.network(
                  _blogImages[index],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorBlack),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: colorDirtyWhite,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: colorGrey),
                    ),
                  ),
                ),
              ),
            ),
            if (_blogImages.isNotEmpty)
              Positioned(
                top: 48,
                right: 16,
                child: GestureDetector(
                  onTap: () => _openImageViewer(_currentCarouselIndex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${_currentCarouselIndex + 1}/${_blogImages.length}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (_blogImages.length > 1) ...[
              Positioned(
                right: 12,
                child: _navButton(Icons.arrow_forward_ios, () {
                  _carouselController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                }),
              ),
              Positioned(
                left: 12,
                child: _navButton(Icons.arrow_back_ios_new, () {
                  _carouselController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                }),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.black26,
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _buildThumbnailRow() {
    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _blogImages.length,
        itemBuilder: (context, index) {
          bool isSelected = _currentCarouselIndex == index;
          return GestureDetector(
            onTap: () => _carouselController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              width: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? colorBlack : Colors.transparent, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _blogImages[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: colorDirtyWhite,
                    child: const Icon(Icons.broken_image, color: colorGrey, size: 18),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAuthorHeader() {
    final bool isEdited = widget.blog.updatedAt != null &&
        (widget.blog.createdAt == null ||
            !widget.blog.updatedAt!.isAtSameMomentAs(widget.blog.createdAt!));

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: colorBlack,
          backgroundImage: widget.blog.authorAvatarUrl != null ? NetworkImage(widget.blog.authorAvatarUrl!) : null,
          child: widget.blog.authorAvatarUrl == null 
            ? Text(widget.blog.username?[0].toUpperCase() ?? "A", style: const TextStyle(color: Colors.white)) 
            : null,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.blog.username ?? "Anonymous", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDateTime(widget.blog.updatedAt!),
                    style: const TextStyle(color: colorGrey, fontSize: 12),
                  ),
                ],
              )
            else
              Text(
                widget.blog.createdAt != null
                    ? _formatDateTime(widget.blog.createdAt!)
                    : "Unknown date",
                style: const TextStyle(color: colorGrey, fontSize: 12),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openImageViewer(int initialIndex) async {
    if (_blogImages.isEmpty) return;
    final safeInitialIndex = initialIndex.clamp(0, _blogImages.length - 1);
    final selectedIndex = await showDialog<int>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => _FullscreenBlogImageViewer(
        imageUrls: _blogImages,
        initialIndex: safeInitialIndex,
      ),
    );
    if (!mounted) return;
    final syncedIndex =
        (selectedIndex ?? _currentCarouselIndex).clamp(0, _blogImages.length - 1);
    if (_carouselController.hasClients) {
      _carouselController.jumpToPage(syncedIndex);
    }
    setState(() => _currentCarouselIndex = syncedIndex);
  }

  Widget _buildCommentsList() {
    if (commentsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: colorBlack),
          ),
        ),
      );
    }
    if (comments.isEmpty) return const Center(child: Text("No comments yet.", style: TextStyle(color: colorGrey)));
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: CommentTile(
          comment: comments[index],
          currentUserId: userId ?? "",
          onDelete: () => deleteComment(comments[index]),
          onUpdate: (txt, imgs, retainedUrls) => handleSaveOrUpdate(
            existingComment: comments[index],
            updatedText: txt,
            newImages: imgs,
            retainedExistingImageUrls: retainedUrls,
          ),
        ),
      ),
    );
  }

  Widget _buildCommentInputArea() {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: colorDirtyWhite))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (commentImages.isNotEmpty) _buildImagePreview(),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: pickCommentImages,
              ),
              Expanded(
                child: TextField(
                  controller: commentController,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: "Write a comment...",
                    filled: true,
                    fillColor: colorDirtyWhite,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: commentLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.send_rounded, color: colorBlack),
                onPressed: commentLoading ? null : () => handleSaveOrUpdate(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: commentImages.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == commentImages.length) {
            return _buildAddImageTile(
              onTap: pickCommentImages,
            );
          }
          final imageIndex = index;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: _buildPickedImage(
                  commentImages[imageIndex],
                  webBytes: (imageIndex < commentWebImageBytes.length)
                      ? commentWebImageBytes[imageIndex]
                      : null,
                  height: 80,
                  width: 80,
                ),
              ),
              Positioned(
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      commentImages.removeAt(imageIndex);
                      if (kIsWeb && imageIndex < commentWebImageBytes.length) {
                        commentWebImageBytes.removeAt(imageIndex);
                      }
                    });
                  },
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: colorBlack,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> pickCommentImages() async {
    final images = await ImagePicker().pickMultiImage(imageQuality: 70);
    if (images.isEmpty) return;
    if (kIsWeb) {
      final bytes = await Future.wait(images.map((e) => e.readAsBytes()));
      if (!mounted) return;
      setState(() {
        commentImages.addAll(images);
        commentWebImageBytes.addAll(bytes);
      });
      return;
    }
    if (!mounted) return;
    setState(() => commentImages.addAll(images));
  }

  Widget _buildPickedImage(
    XFile image, {
    Uint8List? webBytes,
    double? height,
    double? width,
  }) {
    if (kIsWeb) {
      if (webBytes != null) {
        return Image.memory(webBytes, height: height, width: width, fit: BoxFit.contain);
      }
      return FutureBuilder<Uint8List>(
        future: image.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              height: height,
              width: width,
              fit: BoxFit.contain,
            );
          }
          return Container(
            height: height,
            width: width,
            color: colorDirtyWhite,
            child: const Center(
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }
    return Image.file(
      File(image.path),
      height: height,
      width: width,
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

  String? _encodeCommentImages(List<String> imagePaths) {
    if (imagePaths.isEmpty) return null;
    if (imagePaths.length == 1) return imagePaths.first;
    return jsonEncode(imagePaths);
  }

  List<String> _normalizeCommentImagePaths(List<String> values) {
    return values
        .map((value) {
          if (!value.startsWith('http')) return value;
          return value.split('/').last.split('?').first;
        })
        .where((value) => value.isNotEmpty)
        .toList();
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

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day}/${dt.month}/${dt.year} $hour:$minute $suffix';
  }

String? _toPublicBlogImageUrl(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) return null;
    if (rawValue.startsWith('http')) return rawValue;
    return Supabase.instance.client.storage.from('blog-images').getPublicUrl(rawValue);
  }

}

class _FullscreenBlogImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullscreenBlogImageViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullscreenBlogImageViewer> createState() =>
      _FullscreenBlogImageViewerState();
}

class _FullscreenBlogImageViewerState extends State<_FullscreenBlogImageViewer> {
  late final ScrollController _scrollController;
  late final ValueNotifier<int> _currentIndex;
  double _itemExtent = 1;
  bool _didJumpInitial = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentIndex = ValueNotifier<int>(widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheAround(widget.initialIndex);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  void _precacheAround(int index) {
    final start = (index - 1).clamp(0, widget.imageUrls.length - 1);
    final end = (index + 1).clamp(0, widget.imageUrls.length - 1);
    for (var i = start; i <= end; i++) {
      precacheImage(NetworkImage(widget.imageUrls[i]), context);
    }
  }

  void _updateCurrentIndexFromOffset() {
    if (!_scrollController.hasClients) return;
    final raw = (_scrollController.offset / _itemExtent).round();
    final next = raw.clamp(0, widget.imageUrls.length - 1);
    if (_currentIndex.value != next) {
      _currentIndex.value = next;
      _precacheAround(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context, _currentIndex.value),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withValues(alpha: 0.30)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final modalWidth = constraints.maxWidth * 0.92;
                  final modalHeight = constraints.maxHeight * 0.82;
                  final imageHeight = (modalWidth - 24) * 0.82;
                  final itemSpacing = 10.0;
                  _itemExtent = imageHeight + itemSpacing;

                  if (!_didJumpInitial) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_scrollController.hasClients) return;
                      final target = (widget.initialIndex * _itemExtent)
                          .clamp(0, _scrollController.position.maxScrollExtent)
                          .toDouble();
                      _scrollController.jumpTo(target);
                      _didJumpInitial = true;
                      _updateCurrentIndexFromOffset();
                    });
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: modalWidth,
                      height: modalHeight,
                      color: Colors.black.withValues(alpha: 0.92),
                      child: Stack(
                        children: [
                          NotificationListener<ScrollUpdateNotification>(
                            onNotification: (notification) {
                              _updateCurrentIndexFromOffset();
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 54, 12, 12),
                              itemCount: widget.imageUrls.length,
                              itemBuilder: (context, index) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == widget.imageUrls.length - 1
                                      ? 0
                                      : itemSpacing,
                                ),
                                child: SizedBox(
                                  height: imageHeight,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      color: Colors.black,
                                      child: Image.network(
                                        widget.imageUrls[index],
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.low,
                                        gaplessPlayback: true,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Center(
                                          child: Icon(
                                            Icons.broken_image,
                                            color: Colors.white70,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              onPressed: () =>
                                  Navigator.pop(context, _currentIndex.value),
                              icon: const Icon(Icons.close, color: Colors.white),
                            ),
                          ),
                          Positioned(
                            top: 14,
                            left: 14,
                            child: ValueListenableBuilder<int>(
                              valueListenable: _currentIndex,
                              builder: (context, currentIndex, _) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  "${currentIndex + 1}/${widget.imageUrls.length}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
