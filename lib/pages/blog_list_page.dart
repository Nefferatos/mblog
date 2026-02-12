import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../models/blog.dart';
import '../widgets/blog_card.dart';
import 'blog_detail_page.dart';
import 'create_blog_page.dart';
import 'login_page.dart';
import 'update_blog_page.dart';
import 'profile_page.dart';

class BlogListPage extends StatefulWidget {
  const BlogListPage({super.key});

  @override
  State<BlogListPage> createState() => _BlogListPageState();
}

class _BlogListPageState extends State<BlogListPage> {
  final StorageService storage = StorageService();
  final AuthService auth = AuthService();
  final service = SupabaseService();

  List<Blog> allBlogs = [];
  List<Map<String, String>> searchUsers = [];
  bool loading = true;
  bool postsLoading = false;
  String? userId;
  String userDisplayName = 'U';
  String? userAvatarUrl;

  // --- Pagination & Sorting State ---
  int currentPage = 0;
  final int pageSize = 4;
  bool isAscending = false;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final TextEditingController searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _postsScrollController = ScrollController();

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    loadUser();
    fetchBlogs(showPageLoader: true);
    setupRealtime();
  }

  Future<void> loadUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          userId = null;
          userAvatarUrl = null;
          userDisplayName = 'U';
        });
      }
      return;
    }

    String nextName =
        user.userMetadata?['display_name'] ??
        user.userMetadata?['full_name'] ??
        user.userMetadata?['username'] ??
        user.email?.split('@')[0] ??
        'User';
    String? nextAvatar =
        user.userMetadata?['avatar_url'] ??
        user.userMetadata?['avatar'] ??
        user.userMetadata?['picture'];

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null) {
        final profileName = profile['username']?.toString();
        if (profileName != null && profileName.isNotEmpty) {
          nextName = profileName;
        }

        final profileAvatar = profile['avatar_url']?.toString();
        if (profileAvatar != null && profileAvatar.isNotEmpty) {
          nextAvatar = profileAvatar;
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile for menu: $e');
    }

    if (!mounted) return;
    setState(() {
      userId = user.id;
      userDisplayName = nextName;
      userAvatarUrl = _toPublicBlogImageUrl(nextAvatar);
    });
  }

  Future<void> fetchBlogs({bool showPageLoader = false}) async {
    if (!mounted) return;
    setState(() {
      if (showPageLoader) {
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
            .order('created_at', ascending: isAscending)
            .range(from, to);
      } catch (e) {
        debugPrint('Feed join query failed, using fallback: $e');
        data = await Supabase.instance.client
            .from('blogs')
            .select('*')
            .order('created_at', ascending: isAscending)
            .range(from, to);
      }

      final updatedBlogs = await _hydrateBlogsWithProfiles(data);

      if (!mounted) return;
      setState(() {
        allBlogs = updatedBlogs;
        loading = false;
        postsLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading blogs: $e');
      if (!mounted) return;
      setState(() {
        loading = false;
        postsLoading = false;
      });
    }
  }

  void setupRealtime() {
    Supabase.instance.client
        .channel('public:blogs')
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'blogs'),
          (payload, [ref]) => fetchBlogs(),
        )
        .subscribe();
  }

  Future<void> _changePage(int delta) async {
    setState(() => currentPage += delta);
    await fetchBlogs();
    _scrollPostsToTop();
  }

  Future<void> _goToFirstPage() async {
    if (currentPage == 0) return;
    setState(() => currentPage = 0);
    await fetchBlogs();
    _scrollPostsToTop();
  }

  Future<void> _goToLastPage() async {
    if (loading || postsLoading) return;
    var probePage = currentPage;
    try {
      while (true) {
        final from = (probePage + 1) * pageSize;
        final to = from + pageSize - 1;

        final rows = await Supabase.instance.client
            .from('blogs')
            .select('id')
            .order('created_at', ascending: isAscending)
            .range(from, to) as List<dynamic>;

        if (rows.isEmpty) break;
        probePage += 1;
        if (rows.length < pageSize) break;
      }

      if (!mounted || probePage == currentPage) return;
      setState(() => currentPage = probePage);
      await fetchBlogs();
      _scrollPostsToTop();
    } catch (e) {
      debugPrint('Error jumping to last page: $e');
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
    fetchBlogs();
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => searchUsers = []);
      _removeOverlay();
      return;
    }

    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url')
          .ilike('username', '%$q%')
          .limit(10);

      final users = (rows as List).map((row) {
        final avatar = row['avatar_url']?.toString();
        return <String, String>{
          'id': row['id']?.toString() ?? '',
          'username': row['username']?.toString() ?? 'Anonymous',
          'avatar_url': _toPublicBlogImageUrl(avatar) ?? '',
        };
      }).where((u) => (u['id'] ?? '').isNotEmpty).toList();

      if (!mounted) return;

      setState(() {
        searchUsers = users;
      });

      if (searchUsers.isNotEmpty) {
        if (_overlayEntry == null) {
          _showOverlay();
        } else {
          _overlayEntry!.markNeedsBuild();
        }
      } else {
        _removeOverlay();
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  Future<List<Blog>> _hydrateBlogsWithProfiles(List<dynamic> data) async {
    final userIds = data
        .map((e) => e['user_id']?.toString())
        .whereType<String>()
        .toSet();
    final profilesByUserId = await _fetchProfilesByUserIds(userIds);
    final hydrated = await Future.wait(data.map((e) async {
      final blog = Blog.fromMap(e);
      final likes = (e['likes'] as List?) ?? await _fetchLikesByBlogId(blog.id);
      final profile = profilesByUserId[blog.userId];
      final usernameFromProfile = profile?['username'];
      final avatarFromProfile = profile?['avatar_url'];

      return blog.copyWith(
        likesCount: likes.length,
        isLiked: userId != null && likes.any((l) => l['user_id'] == userId),
        username: (usernameFromProfile != null && usernameFromProfile.isNotEmpty)
            ? usernameFromProfile
            : (blog.username ?? 'Anonymous'),
        authorAvatarUrl: _toPublicBlogImageUrl(
          (avatarFromProfile != null && avatarFromProfile.isNotEmpty)
              ? avatarFromProfile
              : blog.authorAvatarUrl,
        ),
      );
    }));
    return hydrated;
  }

  Future<Map<String, Map<String, String?>>> _fetchProfilesByUserIds(
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
      debugPrint('Error hydrating profiles for blogs: $e');
      return {};
    }
  }

  Future<void> _handlePullToRefresh() async {
    _removeOverlay();
    _focusNode.unfocus();
    searchController.clear();
    if (mounted) {
      setState(() => searchUsers = []);
    }
    await loadUser();
    await fetchBlogs();
  }

  Future<List<dynamic>> _fetchLikesByBlogId(int blogId) async {
    try {
      final rows = await Supabase.instance.client
          .from('likes')
          .select('user_id')
          .eq('blog_id', blogId);
      return rows as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching likes for blog $blogId: $e');
      return [];
    }
  }

  Future<void> toggleLike(Blog blog) async {
    if (userId == null) return;
    try {
      final updated = await service.toggleLike(blog, userId!);
      if (updated == null || !mounted) return;
      setState(() {
        final index = allBlogs.indexWhere((b) => b.id == blog.id);
        if (index != -1) {
          allBlogs[index] = allBlogs[index].copyWith(
            likesCount: updated.likesCount,
            isLiked: updated.isLiked,
          );
        }
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width * 0.8,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 45),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: searchUsers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No results found'),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: searchUsers.length,
                      itemBuilder: (context, i) {
                        final user = searchUsers[i];
                        final username = user['username'] ?? 'Anonymous';
                        final avatarUrl = user['avatar_url'];
                        final profileUserId = user['id'] ?? '';
                        return GestureDetector(
                          onTap: () {
                            searchController.clear();
                            setState(() => searchUsers = []);
                            _focusNode.unfocus();
                            _removeOverlay();

                            if (profileUserId.isEmpty) return;
                            Future.delayed(const Duration(milliseconds: 80), () {
                              if (!mounted) return;
                              Navigator.of(this.context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProfilePage(userId: profileUserId),
                                ),
                              );
                            });
                          },
                          child: Container(
                            color: Colors.transparent,
                            child: ListTile(
                              title: Text(
                                username,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: colorDirtyWhite,
                                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? Text(
                                        username.isNotEmpty ? username[0].toUpperCase() : 'A',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: colorBlack,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
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
            child: const Text(
              "Cancel",
              style: TextStyle(color: Color(0xFF757575)),
            ),
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
      if (success) {
        fetchBlogs(showPageLoader: true);
      } else {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _focusNode.unfocus();
        _removeOverlay();
      },
      child: Scaffold(
        backgroundColor: colorDirtyWhite,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: 120,
          title: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'FEED',
                    style: TextStyle(
                      color: colorBlack,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _layerLink,
                      child: _buildSearchField(),
                    ),
                  ),
                  _buildUserMenu(),
                ],
              ),
              const SizedBox(height: 12),
              _buildSortRow(),
            ],
          ),
        ),
        body: RefreshIndicator(
          color: colorBlack,
          onRefresh: _handlePullToRefresh,
          child: loading
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 220),
                    Center(
                      child: CircularProgressIndicator(color: colorBlack),
                    ),
                  ],
                )
              : _buildScrollableContent(),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: colorBlack,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
          onPressed: () async {
            final res = await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CreateBlogPage()));
            if (!mounted || res == null) return;
            if (res is Blog && currentPage == 0) {
              final created = res.copyWith(
                username: (res.username != null && res.username!.isNotEmpty)
                    ? res.username
                    : userDisplayName,
                authorAvatarUrl: _toPublicBlogImageUrl(
                  res.authorAvatarUrl ?? userAvatarUrl,
                ),
              );
              setState(() {
                allBlogs = [created, ...allBlogs];
                if (allBlogs.length > pageSize) {
                  allBlogs = allBlogs.sublist(0, pageSize);
                }
              });
            } else {
              fetchBlogs();
            }
          },
        ),
      ),
    );
  }

  Widget _buildScrollableContent() {
    if (allBlogs.isEmpty) {
      return ListView(
        controller: _postsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 220),
          Center(child: Text("No posts found")),
        ],
      );
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _postsScrollController,
          padding: const EdgeInsets.symmetric(vertical: 12),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: allBlogs.length + 1,
          itemBuilder: (context, index) {
            if (index == allBlogs.length) {
              return _buildPaginationRow();
            }

            final blog = allBlogs[index];
            return BlogCard(
              blog: blog,
              currentUserId: userId,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => BlogDetailPage(blog: blog))),
              onLike: () => toggleLike(blog),
              onComment: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => BlogDetailPage(blog: blog))),
              onProfileTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(userId: blog.userId),
                  ),
                );
                fetchBlogs();
              },
              onEdit: () async {
                final updated = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => UpdateBlogPage(blog: blog)),
                );
                if (!mounted || updated == null) return;
                if (updated is Blog) {
                  setState(() {
                    final i = allBlogs.indexWhere((b) => b.id == updated.id);
                    if (i != -1) {
                      allBlogs[i] = allBlogs[i].copyWith(
                        title: updated.title,
                        content: updated.content,
                        imageUrls: updated.imageUrls,
                        updatedAt: updated.updatedAt,
                      );
                    }
                  });
                } else {
                  fetchBlogs();
                }
              },
              onDelete: () => _handleDelete(blog),
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
    );
  }

  Widget _buildPaginationRow() {
    bool hasNext = allBlogs.length == pageSize;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "Page ${currentPage + 1}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: colorBlack,
                fontSize: 16,
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
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: colorBlack,
        disabledBackgroundColor: colorGrey.withOpacity(0.1),
        foregroundColor: Colors.white,
        disabledForegroundColor: colorGrey,
      ),
    );
  }

  Widget _buildSortRow() {
    return Row(
      children: [
        _sortButton("Newest", !isAscending, () => _toggleSort(false)),
        const SizedBox(width: 8),
        _sortButton("Oldest", isAscending, () => _toggleSort(true)),
      ],
    );
  }

  Widget _sortButton(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorBlack : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colorBlack : colorGrey.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : colorBlack,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorDirtyWhite,
        borderRadius: BorderRadius.circular(25),
      ),
      child: TextField(
        controller: searchController,
        focusNode: _focusNode,
        onChanged: _performSearch,
        decoration: const InputDecoration(
          hintText: 'Search posts...',
          prefixIcon: Icon(Icons.search, size: 18),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildUserMenu() {
    return PopupMenuButton<String>(
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: colorDirtyWhite,
        backgroundImage: (userAvatarUrl != null && userAvatarUrl!.isNotEmpty)
            ? NetworkImage(userAvatarUrl!)
            : null,
        child: (userAvatarUrl == null || userAvatarUrl!.isEmpty)
            ? Text(
                userDisplayName.isNotEmpty ? userDisplayName[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: colorBlack,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              )
            : null,
      ),
      onSelected: (v) async {
        if (v == 'logout') {
          logout();
        } else if (v == 'profile') {
          if (userId != null) {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfilePage(userId: userId!)),
            );
            await loadUser();
            fetchBlogs();
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'profile', child: Text('My Profile')),
        const PopupMenuItem(
          value: 'logout',
          child: Text('Logout', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  String? _toPublicBlogImageUrl(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) return null;
    if (rawValue.startsWith('http')) return rawValue;
    return Supabase.instance.client.storage.from('blog-images').getPublicUrl(rawValue);
  }

  @override
  void dispose() {
    _removeOverlay();
    _postsScrollController.dispose();
    searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
