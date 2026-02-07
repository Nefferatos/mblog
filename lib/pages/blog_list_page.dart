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
  List<Blog> searchResults = [];
  bool loading = true;
  String? userId;

  // --- Pagination & Sorting State ---
  int currentPage = 0;
  final int pageSize = 4;
  bool isAscending = false;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final TextEditingController searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const Color colorBlack = Color(0xFF1A1A1A);
  static const Color colorGrey = Color(0xFF757575);
  static const Color colorDirtyWhite = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    loadUser();
    fetchBlogs();
    setupRealtime();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _removeOverlay();
    });
  }

  void loadUser() {
    final user = Supabase.instance.client.auth.currentUser;
    setState(() => userId = user?.id);
  }

  Future<void> fetchBlogs() async {
    setState(() => loading = true);
    try {
      final from = currentPage * pageSize;
      final to = from + pageSize - 1;

      final data = await Supabase.instance.client
          .from('blogs')
          .select('*, likes(*)')
          .order('created_at', ascending: isAscending)
          .range(from, to);

      final updatedBlogs = (data as List).map((e) {
        var blog = Blog.fromMap(e);
        final likes = (e['likes'] as List?) ?? [];
        return blog.copyWith(
          likesCount: likes.length,
          isLiked: userId != null && likes.any((l) => l['user_id'] == userId),
          username: blog.username ?? 'Anonymous',
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        allBlogs = updatedBlogs;
        loading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  void setupRealtime() {
    Supabase.instance.client
        .channel('public:blogs')
        .on(
            RealtimeListenTypes.postgresChanges,
            ChannelFilter(event: '*', schema: 'public', table: 'blogs'),
            (payload, [ref]) => fetchBlogs())
        .subscribe();
  }

  void _changePage(int delta) {
    setState(() => currentPage += delta);
    fetchBlogs();
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
    if (query.isEmpty) {
      setState(() => searchResults = []);
      _removeOverlay();
      return;
    }

    try {
      // FIX: Query Supabase directly to search ALL blogs, not just local list
      final data = await Supabase.instance.client
          .from('blogs')
          .select()
          .ilike('title', '%$query%') // Case-insensitive search
          .limit(5);

      setState(() {
        searchResults = (data as List).map((e) => Blog.fromMap(e)).toList();
      });

      if (searchResults.isNotEmpty) {
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

  Future<void> toggleLike(Blog blog) async {
    if (userId == null) return;
    try {
      await service.toggleLike(blog, userId!);
      fetchBlogs();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
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
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: searchResults.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(searchResults[i].title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(searchResults[i].username ?? "Anonymous",
                      style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    _removeOverlay();
                    searchController.clear();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            BlogDetailPage(blog: searchResults[i])));
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                  const Text('FEED',
                      style: TextStyle(
                          color: colorBlack,
                          fontWeight: FontWeight.w900,
                          fontSize: 20)),
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
        body: loading
            ? const Center(child: CircularProgressIndicator(color: colorBlack))
            : _buildScrollableContent(),
        floatingActionButton: FloatingActionButton(
          backgroundColor: colorBlack,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
          onPressed: () async {
            final res = await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const CreateBlogPage()));
            if (res != null) fetchBlogs();
          },
        ),
      ),
    );
  }

  Widget _buildScrollableContent() {
    if (allBlogs.isEmpty) return const Center(child: Text("No posts found"));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: allBlogs.length + 1,
      itemBuilder: (context, index) {
        if (index == allBlogs.length) {
          return _buildPaginationRow();
        }

        final blog = allBlogs[index];
        return BlogCard(
          blog: blog,
          currentUserId: userId,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => BlogDetailPage(blog: blog))),
          onLike: () => toggleLike(blog),
          onComment: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => BlogDetailPage(blog: blog))),
          onProfileTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ProfilePage(userId: blog.userId))),
          onEdit: () async {
            final updated = await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => UpdateBlogPage(blog: blog)));
            if (updated != null) fetchBlogs();
          },
        );
      },
    );
  }

  Widget _buildPaginationRow() {
    bool hasNext = allBlogs.length == pageSize;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _navButton(Icons.chevron_left,
              currentPage > 0 ? () => _changePage(-1) : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "Page ${currentPage + 1}",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: colorBlack, fontSize: 16),
            ),
          ),
          _navButton(Icons.chevron_right, hasNext ? () => _changePage(1) : null),
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
              color: isSelected ? colorBlack : colorGrey.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : colorBlack,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
          color: colorDirtyWhite, borderRadius: BorderRadius.circular(25)),
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
      icon: const Icon(Icons.account_circle_outlined, size: 30),
      onSelected: (v) {
        if (v == 'logout') {
          logout();
        } else if (v == 'profile') {
          if (userId != null) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProfilePage(userId: userId!)));
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'profile', child: Text('My Profile')),
        const PopupMenuItem(
            value: 'logout',
            child: Text('Logout', style: TextStyle(color: Colors.red))),
      ],
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}