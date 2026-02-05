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
  XFile? commentImage;
  bool commentLoading = false;
  String? viewImage;

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    loadUser();
    fetchComments();
  }

  void loadUser() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        userId = user.id;
        final metadata = user.userMetadata;
        

        usernameDisplay = metadata?['display_name'] ?? 
                          metadata?['full_name'] ?? 
                          metadata?['username'] ?? 
                          user.email?.split('@')[0] ?? 
                          "Anonymous";

        currentUserProfilePic = metadata?['avatar_url'] ?? 
                                metadata?['picture'];
      });
    }
  }

  Future<void> fetchComments() async {
    setState(() => loading = true);
    try {
      final data = await service.getComments(widget.blog.id);
      final resolvedComments = await Future.wait(
        data.map((c) async {
          if (c.imageUrl != null && !c.imageUrl!.startsWith("http")) {
            final signedUrl = await Supabase.instance.client.storage
                .from('comment-images')
                .createSignedUrl(c.imageUrl!, 3600);
            return c.copyWith(imageUrl: signedUrl);
          }
          return c;
        }),
      );
      if (!mounted) return;
      setState(() {
        comments = resolvedComments;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> handleSaveOrUpdate({
    Comment? existingComment,
    String? updatedText,
    XFile? newImage,
  }) async {
    if (userId == null) return;
    final textToSave = (updatedText ?? commentController.text).trim();
    if (existingComment == null && textToSave.isEmpty && commentImage == null) return;

    setState(() => commentLoading = true);
    try {
      String? imageUrl = existingComment?.imageUrl;
      final imageToUpload = newImage ?? (existingComment == null ? commentImage : null);

      if (imageToUpload != null) {
        final fileName = 'comment-${DateTime.now().millisecondsSinceEpoch}.png';
        final bytes = await imageToUpload.readAsBytes();
        await Supabase.instance.client.storage.from('comment-images').uploadBinary(fileName, bytes);
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
    } finally {
      setState(() => commentLoading = false);
    }
  }

  Future<void> deleteComment(Comment c) async {
    try {
      if (c.imageUrl != null) {
        final fileName = c.imageUrl!.split('/').last.split('?')[0];
        await Supabase.instance.client.storage.from('comment-images').remove([fileName]);
      }
      await service.deleteComment(c.id);
      setState(() => comments.removeWhere((element) => element.id == c.id));
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }

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
                    SliverAppBar(
                      expandedHeight: 380.0,
                      floating: false,
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

                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: colorDirtyWhite,
                                backgroundImage: currentUserProfilePic != null
                                    ? NetworkImage(currentUserProfilePic!)
                                    : null,
                                child: currentUserProfilePic == null
                                    ? Text(usernameDisplay[0].toUpperCase(), 
                                        style: const TextStyle(color: colorBlack, fontWeight: FontWeight.bold, fontSize: 14))
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: widget.blog.imageUrl != null
                            ? GestureDetector(
                                onTap: () => setState(() => viewImage = widget.blog.imageUrl),
                                child: Hero(
                                  tag: 'blog_image_${widget.blog.id}',
                                  child: Image.network(
                                    widget.blog.imageUrl!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            : Container(color: colorDirtyWhite),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAuthorRow(),
                            const SizedBox(height: 20),
                            Text(
                              widget.blog.title,
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: colorBlack, height: 1.1),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              widget.blog.content,
                              style: const TextStyle(fontSize: 18, height: 1.7, color: Color(0xFF2D2D2D)),
                            ),
                            const SizedBox(height: 48),
                            const Row(
                              children: [
                                Text("COMMENTS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
                                Expanded(child: Divider(indent: 16, thickness: 1, color: colorDirtyWhite)),
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
                if (viewImage != null) _buildFullscreenViewer(),
              ],
            ),
    );
  }

  Widget _buildAuthorRow() {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: colorBlack,
          backgroundImage: widget.blog.authorAvatarUrl != null ? NetworkImage(widget.blog.authorAvatarUrl!) : null,
          child: widget.blog.authorAvatarUrl == null 
            ? Text(widget.blog.username?[0].toUpperCase() ?? "A", style: const TextStyle(color: Colors.white, fontSize: 10)) 
            : null,
        ),
        const SizedBox(width: 10),
        Text(
          "By ${widget.blog.username ?? 'Anonymous'}",
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colorGrey, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildCommentsList() {
    if (comments.isEmpty) return const Center(child: Text("No comments yet.", style: TextStyle(color: colorGrey)));
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: CommentTile(
            comment: comment,
            currentUserId: userId ?? "",
            onDelete: () => deleteComment(comment),
            onUpdate: (newText, newImg) => handleSaveOrUpdate(
              existingComment: comment,
              updatedText: newText,
              newImage: newImg,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommentInputArea() {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (commentImage != null) _buildImagePreview(),
            Row(
              children: [
                IconButton(icon: const Icon(Icons.add_photo_alternate_outlined, color: colorBlack, size: 24), onPressed: pickCommentImage),
                Expanded(
                  child: TextField(
                    controller: commentController,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(hintText: "Share your thoughts...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                  ),
                ),
                GestureDetector(
                  onTap: commentLoading ? null : () => handleSaveOrUpdate(),
                  child: CircleAvatar(
                    backgroundColor: colorBlack,
                    radius: 22,
                    child: commentLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: kIsWeb
                ? FutureBuilder<Uint8List>(
                    future: commentImage!.readAsBytes(),
                    builder: (context, snapshot) => snapshot.hasData 
                      ? Image.memory(snapshot.data!, height: 80, width: 80, fit: BoxFit.cover) 
                      : const SizedBox(width: 80))
                : Image.file(File(commentImage!.path), height: 80, width: 80, fit: BoxFit.cover),
          ),
          Positioned(right: 0, child: GestureDetector(onTap: () => setState(() => commentImage = null), child: const CircleAvatar(radius: 12, backgroundColor: colorBlack, child: Icon(Icons.close, size: 14, color: Colors.white)))),
        ],
      ),
    );
  }

  Widget _buildFullscreenViewer() {
    return GestureDetector(
      onTap: () => setState(() => viewImage = null),
      child: Container(
        color: Colors.black.withOpacity(0.95),
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(viewImage!))),
            Positioned(top: 60, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => setState(() => viewImage = null))),
          ],
        ),
      ),
    );
  }

  Future<void> pickCommentImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) setState(() => commentImage = image);
  }
}