import 'package:flutter/material.dart';
import '../models/blog.dart';

class BlogCard extends StatelessWidget {
  final Blog blog;
  final String? currentUserId;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onProfileTap;

  const BlogCard({
    super.key,
    required this.blog,
    this.currentUserId,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onLike,
    this.onComment,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOwner = currentUserId != null && blog.userId == currentUserId;
    

    const Color colorBlack = Color(0xFF1A1A1A);
    const Color colorGrey = Color(0xFF757575);
    const Color colorLightGrey = Color(0xFFEEEEEE);
    const Color colorWhite = Colors.white;

    final String usernameDisplay =
        (blog.username != null && blog.username!.isNotEmpty)
            ? blog.username!
            : 'Anonymous';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      elevation: 0,
      color: colorWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          ListTile(
            onTap: onProfileTap,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: GestureDetector(
              onTap: onProfileTap,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: colorLightGrey,
                backgroundImage: (blog.authorAvatarUrl != null && blog.authorAvatarUrl!.isNotEmpty)
                    ? NetworkImage(blog.authorAvatarUrl!)
                    : null,
                child: (blog.authorAvatarUrl == null || blog.authorAvatarUrl!.isEmpty)
                    ? Text(
                        usernameDisplay[0].toUpperCase(),
                        style: const TextStyle(color: colorBlack, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
            ),
            title: Row(
              children: [
                Text(
                  usernameDisplay,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorBlack,
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorLightGrey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "YOU",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: colorGrey),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: blog.createdAt != null
                ? Text(
                    "${blog.createdAt!.day}/${blog.createdAt!.month}/${blog.createdAt!.year}",
                    style: const TextStyle(color: colorGrey, fontSize: 11),
                  )
                : null,
            trailing: isOwner
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: colorGrey, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  )
                : null,
          ),


          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Text(
                blog.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: colorBlack,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),


          if (blog.imageUrl != null && blog.imageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onTap,
                  child: Image.network(
                    blog.imageUrl!,
                    key: ValueKey(blog.imageUrl),
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 100,
                      color: colorLightGrey,
                      child: const Icon(Icons.broken_image, color: colorGrey),
                    ),
                  ),
                ),
              ),
            ),

          const Divider(height: 1, indent: 16, endIndent: 16),


          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _ActionButton(
                  icon: blog.isLiked ? Icons.favorite : Icons.favorite_border,
                  label: '${blog.likesCount}',
                  color: blog.isLiked ? Colors.black : colorGrey,
                  onTap: onLike,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Comment',
                  color: colorGrey,
                  onTap: onComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}