class Blog {
  final int id;
  final String title;
  final String content;
  final String? imageUrl;
  final String? excerpt;
  final String userId;
  final DateTime? createdAt;
  final String? username;
  final bool isLiked;      
  final int likesCount;
  final String? authorAvatarUrl;
  final String? displayName;
  final String? userEmail;
  
  

  Blog({
    required this.id,
    required this.title,
    required this.content,
    this.imageUrl,
    this.excerpt,
    required this.userId,
    this.createdAt,
    this.username = 'Anonymous',
    this.isLiked = false,
    this.likesCount = 0,
    this.authorAvatarUrl,
    this.displayName,
    this.userEmail,
  });

  factory Blog.fromMap(Map<String, dynamic> map) {
    final content = map['content']?.toString() ?? '';
  
    return Blog(
      id: map['id'] ?? 0,
      title: map['title']?.toString() ?? 'No Title',
      content: content,
      imageUrl: map['image_url']?.toString(),
      excerpt: content.isNotEmpty
          ? (content.length > 50 ? '${content.substring(0, 50)}...' : content)
          : null,
      userId: map['user_id']?.toString() ?? 'unknown_user',
      username: map['username'] ?? 'Anonymous',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      isLiked: map['is_liked'] ?? false, 
      likesCount: map['likes_count'] ?? 0,
      authorAvatarUrl: map['author_avatar_url']?.toString()
    );
  }

 Blog copyWith({
  int? id,
  String? title,
  String? content,
  String? imageUrl,
  String? excerpt,
  String? userId,
  DateTime? createdAt,
  String? username,
  bool? isLiked,
  int? likesCount,
  String? authorAvatarUrl,
  String? displayName,
  String? userEmail,
}) {
  return Blog(
    id: id ?? this.id,
    title: title ?? this.title,
    content: content ?? this.content,
    imageUrl: imageUrl ?? this.imageUrl,
    excerpt: excerpt ?? this.excerpt,
    userId: userId ?? this.userId,
    createdAt: createdAt ?? this.createdAt,
    username: username ?? this.username,
    isLiked: isLiked ?? this.isLiked,
    likesCount: likesCount ?? this.likesCount,
    authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
    displayName: displayName ?? this.displayName,
    userEmail: userEmail ?? this.userEmail,
  );
}
}
extension BlogDisplayName on Blog {
  String displayNameComputed({String Function(String userId)? getLatestUsername}) {
    if (getLatestUsername != null) {
      final latestName = getLatestUsername(userId);
      if (latestName.isNotEmpty) return latestName;
    }
    if (username != null && username!.isNotEmpty) return username!;
    if (userEmail != null && userEmail!.isNotEmpty) return userEmail!;
    return 'Anonymous';
  }
}

