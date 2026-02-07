import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'update_blog_page.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../models/blog.dart';
import '../widgets/blog_card.dart';
import 'blog_detail_page.dart';

class ProfilePage extends StatefulWidget {
  final String userId;
  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();
  final AuthService auth = AuthService();

  String? currentUserId;
  String? userEmail;
  
  String? profileAvatarUrl;
  String profileUsername = "Loading...";

  List<Blog> blogs = [];
  bool loading = true;
  bool isCurrentUser = false;

  int currentPage = 0;
  final int pageSize = 4;
  bool isAscending = false;

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorLightGrey = Color(0xFFEEEEEE);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    checkOwnership();
    loadProfileHeader();
    fetchUserBlogs();
  }

  void checkOwnership() {
    currentUserId = auth.userId;
    isCurrentUser = widget.userId == currentUserId;
    setState(() {});
  }

Future<void> loadProfileHeader() async {
    setState(() => loading = true);
    
    try {
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .maybeSingle();

      if (profileData != null) {
        profileUsername = profileData['username'] ?? "Anonymous";
        profileAvatarUrl = profileData['avatar_url'];
      } else if (isCurrentUser) {
        profileUsername = auth.displayName;
        final avatarPath = auth.currentUser?.userMetadata?['avatar'] as String?;
        if (avatarPath != null) {
          profileAvatarUrl = Supabase.instance.client.storage
              .from('blog-images').getPublicUrl(avatarPath);
        }
      } else {
        profileUsername = "New User";
      }
    } catch (e) {
      profileUsername = "Anonymous";
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> fetchUserBlogs() async {
    setState(() => loading = true);
    try {
      final from = currentPage * pageSize;
      final to = from + pageSize - 1;

      final data = await Supabase.instance.client
          .from('blogs')
          .select('*, likes(*)')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: isAscending)
          .range(from, to);

      final fetchedBlogs = (data as List).map((e) {
        var blog = Blog.fromMap(e);
        final likes = (e['likes'] as List?) ?? [];
        return blog.copyWith(
          likesCount: likes.length,
          isLiked: currentUserId != null && likes.any((l) => l['user_id'] == currentUserId),
          username: blog.username ?? "Anonymous",
          authorAvatarUrl: blog.authorAvatarUrl,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        blogs = fetchedBlogs;
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _changePage(int delta) {
    setState(() => currentPage += delta);
    fetchUserBlogs();
  }

  void _toggleSort(bool ascending) {
    if (isAscending == ascending) return;
    setState(() {
      isAscending = ascending;
      currentPage = 0;
    });
    fetchUserBlogs();
  }

  Future<void> _toggleLike(Blog blog) async {
    if (currentUserId == null) return;
    await service.toggleLike(blog, currentUserId!);
    fetchUserBlogs();
  }

  Future<void> _handleDelete(Blog blog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Delete Post"),
        content: const Text("Are you sure you want to delete this forever?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: colorGrey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => loading = true);
      final success = await service.deleteBlog(blog.id);
      if (success) fetchUserBlogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorDirtyWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: colorBlack,
        elevation: 0,
        centerTitle: true,
        title: const Text("PROFILE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16)),
        actions: [
          if (isCurrentUser)
            IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: _showSettingsMenu),
        ],
      ),
      body: RefreshIndicator(
        color: colorBlack,
        onRefresh: () async {
          currentPage = 0;
          await loadProfileHeader();
          await fetchUserBlogs();
        },
        child: loading
            ? const Center(child: CircularProgressIndicator(color: colorBlack))
            : ListView.builder(
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: blogs.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildHeader();
                  if (index == blogs.length + 1) return _buildPaginationControls();

                  final blog = blogs[index - 1];
                  return BlogCard(
                    blog: blog,
                    currentUserId: currentUserId,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BlogDetailPage(blog: blog))),
                    onEdit: isCurrentUser
    ? () async {
        final updated = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UpdateBlogPage(blog: blog),
          ),
        );

        if (updated == true) {
          fetchUserBlogs();
        }
      }
    : null,

                    onDelete: isCurrentUser ? () => _handleDelete(blog) : null,
                    onLike: () => _toggleLike(blog),
                    onComment: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BlogDetailPage(blog: blog))),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.only(bottom: 32, top: 16),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: colorDirtyWhite,
                backgroundImage: profileAvatarUrl != null ? NetworkImage(profileAvatarUrl!) : null,
                child: profileAvatarUrl == null ? const Icon(Icons.person, size: 50, color: colorGrey) : null,
              ),
              const SizedBox(height: 16),
              Text(profileUsername, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorBlack)),
              if (isCurrentUser) ...[
                const SizedBox(height: 4),
                Text(userEmail ?? "", style: const TextStyle(color: colorGrey)),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _showEditProfileDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: colorLightGrey),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Edit Profile", style: TextStyle(color: colorBlack, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
        _buildSortRow(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Text(isCurrentUser ? "MY POSTS" : "POSTS", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: colorGrey)),
              const SizedBox(width: 12),
              Expanded(child: Divider(color: colorBlack.withOpacity(0.05))),
            ],
          ),
        ),
        if (blogs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text("No posts found", style: TextStyle(color: colorGrey)),
          ),
      ],
    );
  }


  Widget _buildSortRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _sortButton("Newest", !isAscending, () => _toggleSort(false)),
          const SizedBox(width: 8),
          _sortButton("Oldest", isAscending, () => _toggleSort(true)),
          const Spacer(),
          Text("Page ${currentPage + 1}", style: const TextStyle(color: colorGrey, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _sortButton(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorBlack : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? colorBlack : colorLightGrey),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : colorBlack, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildPaginationControls() {
    bool hasNext = blogs.length == pageSize;
    if (blogs.isEmpty && currentPage == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _navButton(Icons.chevron_left, currentPage > 0 ? () => _changePage(-1) : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Text("Page ${currentPage + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: colorBlack)),
          ),
          _navButton(Icons.chevron_right, hasNext ? () => _changePage(1) : null),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onTap) {
    return IconButton.filled(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: colorBlack,
        disabledBackgroundColor: colorGrey.withOpacity(0.1),
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline, color: colorBlack),
              title: const Text("Edit Name & Photo"),
              onTap: () { Navigator.pop(context); _showEditProfileDialog(); },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                await auth.signOut();
                if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: profileUsername);
    XFile? tempImage;
    Uint8List? tempWebBytes;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("Edit Profile"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (img != null) {
                    final bytes = await img.readAsBytes();
                    setDialogState(() { tempImage = img; tempWebBytes = bytes; });
                  }
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: tempImage != null 
                    ? (kIsWeb ? MemoryImage(tempWebBytes!) : FileImage(File(tempImage!.path)) as ImageProvider)
                    : (profileAvatarUrl != null ? NetworkImage(profileAvatarUrl!) : null),
                  child: (tempImage == null && profileAvatarUrl == null) ? const Icon(Icons.camera_alt) : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: "Display Name")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateProfile(nameController.text, tempImage, tempWebBytes);
              },
              style: ElevatedButton.styleFrom(backgroundColor: colorBlack, foregroundColor: Colors.white),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateProfile(String name, XFile? image, Uint8List? bytes) async {
    setState(() => loading = true);
    try {
      String? newPath;
      if (image != null) {
        newPath = await storage.uploadProfileImage(kIsWeb ? bytes! : File(image.path), currentUserId!);
      }
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'display_name': name, if (newPath != null) 'avatar': newPath}));
      
      // Refresh local state
      await loadProfileHeader();
    } catch (e) {
      debugPrint("Update error: $e");
    } finally {
      setState(() => loading = false);
    }
  }
}