import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class LikeButton extends StatefulWidget {
  final int blogId;

  const LikeButton({super.key, required this.blogId});

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  final SupabaseService service = SupabaseService();

  bool liked = false;
  int likeCount = 0;
  bool loading = true;

  String get userId =>
      Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    loadLikes();
  }

  Future<void> loadLikes() async {
    final likes = await service.getLikes(widget.blogId);
    final isLiked =
        likes.any((like) => like.userId == userId);

    if (!mounted) return;
    setState(() {
      likeCount = likes.length;
      liked = isLiked;
      loading = false;
    });
  }

  Future<void> toggleLike() async {
    if (loading) return;

    setState(() {
      liked = !liked;
      likeCount += liked ? 1 : -1;
    });

    final success = liked
        ? await service.likeBlog(widget.blogId, userId)
        : await service.unlikeBlog(widget.blogId, userId);

    if (!success && mounted) {
      setState(() {
        liked = !liked;
        likeCount += liked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Row(
      children: [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(liked),
              color: liked ? Colors.red : null,
            ),
          ),
          onPressed: toggleLike,
        ),
        Text(
          likeCount.toString(),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}
