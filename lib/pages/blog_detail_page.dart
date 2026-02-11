import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
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
  String? userId;
  String usernameDisplay = "Anonymous";
  String? currentUserProfilePic; 
  final TextEditingController commentController = TextEditingController();
  final PageController _carouselController = PageController();
  
  XFile? commentImage;
  bool commentLoading = false;
  int? viewImageIndex;
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
    fetchComments();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    commentController.dispose();
    super.dispose();
  }

  // --- LOGIC METHODS (Unchanged as per your request) ---

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

  Future<void> fetchComments() async {
    setState(() => loading = true);
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

        if (nextComment.imageUrl != null && !nextComment.imageUrl!.startsWith("http")) {
          final signedUrl = await Supabase.instance.client.storage
              .from('comment-images')
              .createSignedUrl(nextComment.imageUrl!, 3600);
          nextComment = nextComment.copyWith(imageUrl: signedUrl);
        }
        return nextComment;
      }));
      if (!mounted) return;
      setState(() { comments = resolvedComments; loading = false; });
    } catch (e) { setState(() => loading = false); }
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

  Future<void> handleSaveOrUpdate({Comment? existingComment, String? updatedText, XFile? newImage}) async {
    if (userId == null) return;
    final textToSave = (updatedText ?? commentController.text).trim();
    setState(() => commentLoading = true);
    try {
      String? imageUrl = existingComment?.imageUrl;
      final imageToUpload = newImage ?? (existingComment == null ? commentImage : null);
      if (imageToUpload != null) {
        final fileName = 'comment-${DateTime.now().millisecondsSinceEpoch}.png';
        await Supabase.instance.client.storage.from('comment-images').uploadBinary(fileName, await imageToUpload.readAsBytes());
        imageUrl = fileName;
      }
      if (existingComment != null) {
        await service.updateComment(existingComment.id, textToSave, imageUrl);
      } else {
        await service.addComment(widget.blog.id, textToSave, imageUrl, usernameDisplay);
      }
      commentController.clear();
      setState(() => commentImage = null);
      fetchComments();
    } finally { setState(() => commentLoading = false); }
  }

  Future<void> deleteComment(Comment c) async {
    try {
      if (c.imageUrl != null) {
        final fileName = c.imageUrl!.split('/').last.split('?')[0];
        await Supabase.instance.client.storage.from('comment-images').remove([fileName]);
      }
      await service.deleteComment(c.id);
      setState(() => comments.removeWhere((element) => element.id == c.id));
    } catch (e) { debugPrint("Delete error: $e"); }
  }

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _buildCommentInputArea(),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: colorBlack))
          : Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    _buildSliverCarousel(),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. IMAGE PREVIEWS (Thumbnails)
                            if (_blogImages.length > 1) _buildThumbnailRow(),
                            const SizedBox(height: 24),

                            // 2. AVATAR AND USERNAME
                            _buildAuthorHeader(),
                            const SizedBox(height: 24),

                            // 3. TITLE
                            Text(
                              widget.blog.title,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: colorBlack, height: 1.1),
                            ),
                            const SizedBox(height: 20),

                            // 4. DESCRIPTION
                            Text(
                              widget.blog.content,
                              style: const TextStyle(fontSize: 17, height: 1.7, color: Color(0xFF2D2D2D)),
                            ),
                            const SizedBox(height: 48),

                            // 5. COMMENT SECTION
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
                if (viewImageIndex != null) _buildFullscreenViewer(),
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
              itemBuilder: (context, index) => Image.network(_blogImages[index], fit: BoxFit.cover),
            ),
            // Carousel Buttons
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
                image: DecorationImage(image: NetworkImage(_blogImages[index]), fit: BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAuthorHeader() {
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
            const Text("Author", style: TextStyle(color: colorGrey, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentsList() {
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
          onUpdate: (txt, img) => handleSaveOrUpdate(existingComment: comments[index], updatedText: txt, newImage: img),
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
          if (commentImage != null) _buildImagePreview(),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: pickCommentImage),
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
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(File(commentImage!.path), height: 80, width: 80, fit: BoxFit.cover)),
          Positioned(right: 0, child: GestureDetector(onTap: () => setState(() => commentImage = null), child: const CircleAvatar(radius: 12, backgroundColor: colorBlack, child: Icon(Icons.close, size: 14, color: Colors.white)))),
        ],
      ),
    );
  }

  Widget _buildFullscreenViewer() {
    return GestureDetector(
      onTap: () => setState(() => viewImageIndex = null),
      child: Container(
        color: Colors.black.withOpacity(0.95),
        child: PageView.builder(
          controller: PageController(initialPage: viewImageIndex!),
          itemCount: _blogImages.length,
          itemBuilder: (context, index) => InteractiveViewer(child: Image.network(_blogImages[index])),
        ),
      ),
    );
  }

  Future<void> pickCommentImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) setState(() => commentImage = image);
  }

  String? _toPublicBlogImageUrl(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) return null;
    if (rawValue.startsWith('http')) return rawValue;
    return Supabase.instance.client.storage.from('blog-images').getPublicUrl(rawValue);
  }
}
