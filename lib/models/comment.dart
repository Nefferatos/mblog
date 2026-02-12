import 'dart:convert';

class Comment {
  final int id;
  final int blogId;
  final String userId;
  final String userName;
  final String content;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Comment({
    required this.id,
    required this.blogId,
    required this.userId,
    required this.userName,
    required this.content,
    this.imageUrl,
    this.imageUrls = const [],
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
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

  final parsedImageUrls = _parseImageUrls(map['image_url']);
  final primaryImageUrl = parsedImageUrls.isNotEmpty ? parsedImageUrls.first : null;

  return Comment(
    id: map['id'] as int,
    blogId: map['blog_id'] as int,
    userId: map['user_id'] as String,
    userName: rawUserName?.toString() ?? "Anonymous",
    content: map['content'] ?? "",
    imageUrl: primaryImageUrl,
    imageUrls: parsedImageUrls,
    avatarUrl: rawAvatarPath,
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'].toString())
        : null,
    updatedAt: map['updated_at'] != null
        ? DateTime.tryParse(map['updated_at'].toString())
        : null,
  );
}

  static List<String> _parseImageUrls(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return [];
      if (raw.startsWith('[')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
        } catch (_) {}
      }
      return [raw];
    }
    return [];
  }


  Comment copyWith({
    int? id,
    int? blogId,
    String? userId,
    String? userName,
    String? content,
    String? imageUrl,
    List<String>? imageUrls,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextImageUrls = imageUrls ?? this.imageUrls;
    final nextImageUrl =
        imageUrl ?? (nextImageUrls.isNotEmpty ? nextImageUrls.first : null);

    return Comment(
      id: id ?? this.id,
      blogId: blogId ?? this.blogId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      content: content ?? this.content,
      imageUrl: nextImageUrl,
      imageUrls: nextImageUrls,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
