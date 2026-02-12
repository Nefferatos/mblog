import 'dart:io';
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

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final SupabaseService service = SupabaseService();
  final StorageService storage = StorageService();
  final AuthService auth = AuthService();

  String? currentUserId;
  String? userEmail;

  String? profileAvatarUrl;
  String profileUsername = "Loading...";

  List<Blog> blogs = [];
  bool loading = true;
  bool postsLoading = false;
  bool profileUpdating = false;
  bool isCurrentUser = false;

  int currentPage = 0;
  final int pageSize = 4;
  bool isAscending = false;
  final ScrollController _postsScrollController = ScrollController();

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorLightGrey = Color(0xFFEEEEEE);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this); 
  checkOwnership();
  loadProfileHeader();
  fetchUserBlogs(showPageLoader: true);
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _postsScrollController.dispose();
  super.dispose();
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // Refresh session when app comes to foreground
    _refreshSession();
    fetchUserBlogs();
    loadProfileHeader(forceRefresh: true);
  }
}

  void checkOwnership() {
    currentUserId = auth.userId;
    isCurrentUser = widget.userId == currentUserId;
    setState(() {});
  }

  /// Refresh the authentication session
  Future<void> _refreshSession() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
      debugPrint('Session refreshed successfully');
    } catch (e) {
      debugPrint('Session refresh error: $e');
      // If refresh fails, user needs to login again
      if (mounted && e.toString().contains('invalid_grant')) {
        _handleSessionExpired();
      }
    }
  }

  /// Handle expired session - redirect to login
  void _handleSessionExpired() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session expired. Please login again.')),
    );
  }

  Future<void> loadProfileHeader({bool forceRefresh = false}) async {
    setState(() => loading = true);

    try {
      userEmail = auth.currentUser?.email;

      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .maybeSingle();

      if (profileData != null) {
        profileUsername = profileData['username'] ?? "Anonymous";
        final avatarPath = profileData['avatar_url'] as String?;

        if (avatarPath != null && avatarPath.isNotEmpty) {
          final rawUrl = Supabase.instance.client.storage
              .from('blog-images')
              .getPublicUrl(avatarPath);

          profileAvatarUrl = forceRefresh
              ? '$rawUrl?ts=${DateTime.now().millisecondsSinceEpoch}'
              : rawUrl;
        } else {
          profileAvatarUrl = null;
        }
      } else if (isCurrentUser) {
        profileUsername = auth.displayName;
        final avatarPath = auth.currentUser?.userMetadata?['avatar'] as String?;

        if (avatarPath != null && avatarPath.isNotEmpty) {
          final rawUrl = Supabase.instance.client.storage
              .from('blog-images')
              .getPublicUrl(avatarPath);

          profileAvatarUrl = forceRefresh
              ? '$rawUrl?ts=${DateTime.now().millisecondsSinceEpoch}'
              : rawUrl;
        } else {
          profileAvatarUrl = null;
        }
      } else {
        profileUsername = "New User";
        profileAvatarUrl = null;
      }
    } catch (e) {
      debugPrint('Load profile header error: $e');
      profileUsername = "Anonymous";
      profileAvatarUrl = null;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> fetchUserBlogs({bool showPageLoader = false}) async {
    if (!mounted) return;
    setState(() {
      if (showPageLoader || blogs.isEmpty) {
        loading = true;
      } else {
        postsLoading = true;
      }
    });
    try {
      final from = currentPage * pageSize;
      final to = from + pageSize - 1;

      List<dynamic> data;
      try {
        data = await Supabase.instance.client
            .from('blogs')
            .select('*, likes(*), profiles:user_id(username, avatar_url)')
            .eq('user_id', widget.userId)
            .order('created_at', ascending: isAscending)
            .range(from, to);
      } catch (e) {
        debugPrint('Profile blogs join query failed, using fallback: $e');
        data = await Supabase.instance.client
            .from('blogs')
            .select('*')
            .eq('user_id', widget.userId)
            .order('created_at', ascending: isAscending)
            .range(from, to);
      }

      final profile = await _fetchProfileForCurrentPageUser();
      final profileUsername = profile['username'];
      final profileAvatarPath = profile['avatar_url'];

      final fetchedBlogs = await Future.wait(data.map((e) async {
        var blog = Blog.fromMap(e);
        final likes = (e['likes'] as List?) ?? await _fetchLikesByBlogId(blog.id);
        return blog.copyWith(
          likesCount: likes.length,
          isLiked:
              currentUserId != null &&
              likes.any((l) => l['user_id'] == currentUserId),
          username: (profileUsername != null && profileUsername.isNotEmpty)
              ? profileUsername
              : (blog.username ?? "Anonymous"),
          authorAvatarUrl: _toPublicBlogImageUrl(
            (profileAvatarPath != null && profileAvatarPath.isNotEmpty)
                ? profileAvatarPath
                : blog.authorAvatarUrl,
          ),
        );
      }));

      if (!mounted) return;
      setState(() {
        blogs = fetchedBlogs;
        loading = false;
        postsLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch blogs error: $e');
      if (!mounted) return;
      setState(() {
        loading = false;
        postsLoading = false;
      });
    }
  }

  Future<Map<String, String?>> _fetchProfileForCurrentPageUser() async {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', widget.userId)
          .maybeSingle();
      if (row == null) return {};
      return {
        'username': row['username']?.toString(),
        'avatar_url': row['avatar_url']?.toString(),
      };
    } catch (e) {
      debugPrint('Profile lookup error for blogs: $e');
      return {};
    }
  }

  Future<List<dynamic>> _fetchLikesByBlogId(int blogId) async {
    try {
      final rows = await Supabase.instance.client
          .from('likes')
          .select('user_id')
          .eq('blog_id', blogId);
      return rows as List<dynamic>;
    } catch (e) {
      debugPrint('Profile likes lookup error for blog $blogId: $e');
      return [];
    }
  }

  Future<void> _changePage(int delta) async {
    setState(() => currentPage += delta);
    await fetchUserBlogs();
    _scrollPostsToTop();
  }

  Future<void> _goToFirstPage() async {
    if (currentPage == 0) return;
    setState(() => currentPage = 0);
    await fetchUserBlogs();
    _scrollPostsToTop();
  }

  Future<void> _goToLastPage() async {
    if (loading) return;
    var probePage = currentPage;
    try {
      while (true) {
        final from = (probePage + 1) * pageSize;
        final to = from + pageSize - 1;

        final rows = await Supabase.instance.client
            .from('blogs')
            .select('id')
            .eq('user_id', widget.userId)
            .order('created_at', ascending: isAscending)
            .range(from, to) as List<dynamic>;

        if (rows.isEmpty) break;
        probePage += 1;
        if (rows.length < pageSize) break;
      }

      if (!mounted || probePage == currentPage) return;
      setState(() => currentPage = probePage);
      await fetchUserBlogs();
      _scrollPostsToTop();
    } catch (e) {
      debugPrint('Error jumping to last profile page: $e');
    }
  }

  void _scrollPostsToTop() {
    if (!_postsScrollController.hasClients) return;
    _postsScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
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
    final updated = await service.toggleLike(blog, currentUserId!);
    if (!mounted || updated == null) return;
    setState(() {
      final index = blogs.indexWhere((b) => b.id == blog.id);
      if (index != -1) {
        blogs[index] = blogs[index].copyWith(
          likesCount: updated.likesCount,
          isLiked: updated.isLiked,
        );
      }
    });
  }

  Future<void> _handleDelete(Blog blog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Delete Post"),
        content: const Text("Are you sure you want to delete this forever?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: colorGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Delete",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
        title: const Text(
          "PROFILE",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        actions: [
          if (isCurrentUser)
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: _showSettingsMenu,
            ),
        ],
      ),
      body: RefreshIndicator(
        color: colorBlack,
        onRefresh: () async {
          currentPage = 0;
          await loadProfileHeader(forceRefresh: true);
          await fetchUserBlogs();
        },
        child: loading
            ? const Center(child: CircularProgressIndicator(color: colorBlack))
            : Stack(
                children: [
                  ListView.builder(
                    controller: _postsScrollController,
                    padding: EdgeInsets.zero,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: blogs.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildHeader();
                      if (index == blogs.length + 1) {
                        return _buildPaginationControls();
                      }

                      final blog = blogs[index - 1];
                      return BlogCard(
                        blog: blog,
                        currentUserId: currentUserId,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BlogDetailPage(blog: blog),
                            ),
                          );
                          fetchUserBlogs();
                          loadProfileHeader(forceRefresh: true);
                        },
                        onEdit: isCurrentUser
                            ? () async {
                                final updated = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UpdateBlogPage(blog: blog),
                                  ),
                                );

                                if (!mounted || updated == null) return;
                                if (updated is Blog) {
                                  setState(() {
                                    final index = blogs.indexWhere(
                                      (b) => b.id == updated.id,
                                    );
                                    if (index != -1) {
                                      blogs[index] = blogs[index].copyWith(
                                        title: updated.title,
                                        content: updated.content,
                                        imageUrls: updated.imageUrls,
                                        updatedAt: updated.updatedAt,
                                      );
                                    }
                                  });
                                } else {
                                  fetchUserBlogs();
                                }
                              }
                            : null,
                        onDelete: isCurrentUser ? () => _handleDelete(blog) : null,
                        onLike: () => _toggleLike(blog),
                        onComment: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BlogDetailPage(blog: blog),
                            ),
                          );
                          fetchUserBlogs();
                        },
                      );
                    },
                  ),
                  if (postsLoading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(color: colorBlack),
                    ),
                ],
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
              ClipOval(
                child: Stack(
                  children: [
                    profileAvatarUrl != null
                        ? Image.network(
                            profileAvatarUrl!,
                            key: ValueKey(profileAvatarUrl),
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            },
                          )
                        : Container(
                            width: 100,
                            height: 100,
                            color: colorDirtyWhite,
                            child: const Icon(
                              Icons.person,
                              size: 50,
                              color: colorGrey,
                            ),
                          ),
                    if (profileUpdating)
                      Container(
                        width: 100,
                        height: 100,
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                profileUsername,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorBlack,
                ),
              ),
              if (isCurrentUser) ...[
                const SizedBox(height: 4),
                Text(userEmail ?? "", style: const TextStyle(color: colorGrey)),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _showEditProfileDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: colorLightGrey),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Edit Profile",
                    style: TextStyle(
                      color: colorBlack,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              Text(
                isCurrentUser ? "MY POSTS" : "POSTS",
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: colorGrey,
                ),
              ),
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
          Text(
            "Page ${currentPage + 1}",
            style: const TextStyle(
              color: colorGrey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
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
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : colorBlack,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
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
          _navButton(
            Icons.first_page,
            currentPage > 0 ? _goToFirstPage : null,
          ),
          const SizedBox(width: 6),
          _navButton(
            Icons.chevron_left,
            currentPage > 0 ? () => _changePage(-1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Text(
              "Page ${currentPage + 1}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: colorBlack,
              ),
            ),
          ),
          _navButton(
            Icons.chevron_right,
            hasNext ? () => _changePage(1) : null,
          ),
          const SizedBox(width: 6),
          _navButton(
            Icons.last_page,
            hasNext ? _goToLastPage : null,
          ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline, color: colorBlack),
              title: const Text("Edit Name & Photo"),
              onTap: () {
                Navigator.pop(context);
                _showEditProfileDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                "Logout",
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                await auth.signOut();
                if (mounted)
                  Navigator.of(context).popUntil((route) => route.isFirst);
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
                  final img = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                  );
                  if (img != null) {
                    final bytes = await img.readAsBytes();
                    setDialogState(() {
                      tempImage = img;
                      tempWebBytes = bytes;
                    });
                  }
                },
                child: CircleAvatar(
                  key: ValueKey(tempImage?.path ?? profileAvatarUrl),
                  radius: 40,
                  backgroundImage: tempImage != null
                      ? (kIsWeb
                            ? MemoryImage(tempWebBytes!)
                            : FileImage(File(tempImage!.path)))
                      : (profileAvatarUrl != null
                            ? NetworkImage(profileAvatarUrl!)
                            : null),
                  child: (tempImage == null && profileAvatarUrl == null)
                      ? const Icon(Icons.camera_alt)
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Display Name"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateProfile(
                  nameController.text,
                  tempImage,
                  tempWebBytes,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorBlack,
                foregroundColor: Colors.white,
              ),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateProfile(
    String name,
    XFile? image,
    Uint8List? bytes,
  ) async {
    if (currentUserId == null) return;
    setState(() => profileUpdating = true);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    try {
      // Refresh session before updating profile
      await _refreshSession();

      String? newAvatarPath;
      if (image != null) {
        final ext = _extensionFromName(image.name);
        final mimeType = _resolveMimeType(image, ext);
        newAvatarPath = await storage.uploadProfileImage(
          kIsWeb ? bytes! : File(image.path),
          currentUserId!,
          originalFileName: image.name,
          contentType: mimeType,
        );
      }
      
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'display_name': name,
            if (newAvatarPath != null) 'avatar': newAvatarPath,
            if (newAvatarPath != null) 'avatar_url': newAvatarPath,
            if (newAvatarPath != null) 'picture': newAvatarPath,
          },
        ),
      );

      final profileUpdates = {
        'username': name,
        if (newAvatarPath != null) 'avatar_url': newAvatarPath,
      };

      await Supabase.instance.client
          .from('profiles')
          .update(profileUpdates)
          .eq('id', currentUserId!);

      await Supabase.instance.client
          .from('blogs')
          .update({'username': name})
          .eq('user_id', currentUserId!);

      String? displayAvatarUrl;
      if (newAvatarPath != null) {
        final rawUrl = Supabase.instance.client.storage
            .from('blog-images')
            .getPublicUrl(newAvatarPath);
        displayAvatarUrl =
            '$rawUrl?ts=${DateTime.now().millisecondsSinceEpoch}';
      }

      setState(() {
        profileUsername = name;
        if (displayAvatarUrl != null) {
          profileAvatarUrl = displayAvatarUrl;
        }

        blogs = blogs.map((blog) {
          if (blog.userId == currentUserId) {
            return blog.copyWith(
              username: name,
              authorAvatarUrl: displayAvatarUrl ?? blog.authorAvatarUrl,
            );
          }
          return blog;
        }).toList();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } on AuthException catch (e) {
      debugPrint('Profile update auth error: $e');
      if (mounted) {
        // Check if it's a session error
        if (e.message.contains('Session') || e.statusCode == '403') {
          _handleSessionExpired();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Auth error: ${e.message}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Profile update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => profileUpdating = false);
    }
  }

  String? _toPublicBlogImageUrl(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) return null;
    if (rawValue.startsWith('http')) return rawValue;
    return Supabase.instance.client.storage.from('blog-images').getPublicUrl(rawValue);
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
}
