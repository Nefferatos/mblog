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
  String? rawAvatarPath;
  final profile = map['profiles'];
  Map<String, dynamic>? profileMap;
  if (profile is Map<String, dynamic>) {
    profileMap = profile;
  } else if (profile is List && profile.isNotEmpty && profile.first is Map<String, dynamic>) {
    profileMap = profile.first as Map<String, dynamic>;
  }

  if (profileMap != null && profileMap['avatar_url'] != null) {
    rawAvatarPath = profileMap['avatar_url'] as String?;
  } else if (map['avatar_url'] != null) {
    rawAvatarPath = map['avatar_url'] as String?;
  }

  final rawUserName = map['user_name'] ?? map['username'] ?? map['display_name'];

  return Comment(
    id: map['id'] as int,
    blogId: map['blog_id'] as int,
    userId: map['user_id'] as String,
    userName: rawUserName?.toString() ?? "Anonymous",
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
    String? avatarUrl,
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? this.id,
      blogId: blogId ?? this.blogId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
