class Comment {
  final int id;
  final int blogId;
  final String userId;
  final String userName;
  final String content;
  final String? imageUrl;
  final String? avatarUrl;
  final DateTime? createdAt;

  Comment({
    required this.id,
    required this.blogId,
    required this.userId,
    required this.userName,
    required this.content,
    this.imageUrl,
    this.avatarUrl,
    this.createdAt,
  });

factory Comment.fromMap(Map<String, dynamic> map) {
  // Get the raw avatar path from the joined profile, if present
  String? rawAvatarPath;
  if (map['profiles'] != null && map['profiles']['avatar_url'] != null) {
    rawAvatarPath = map['profiles']['avatar_url'] as String;
  } else if (map['avatar_url'] != null) {
    // fallback if your DB stores avatarUrl directly
    rawAvatarPath = map['avatar_url'] as String?;
  }

  return Comment(
    id: map['id'] as int,
    blogId: map['blog_id'] as int,
    userId: map['user_id'] as String,
    userName: map['user_name'] ?? "Anonymous",
    content: map['content'] ?? "",
    imageUrl: map['image_url'] as String?,
    avatarUrl: rawAvatarPath,
    createdAt: map['created_at'] != null
        ? DateTime.parse(map['created_at'] as String)
        : null,
  );
}


  Comment copyWith({
    int? id,
    int? blogId,
    String? userId,
    String? userName,
    String? content,
    String? imageUrl,
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? this.id,
      blogId: blogId ?? this.blogId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}