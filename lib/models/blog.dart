import 'dart:convert';

class Blog {
  final int id;
  final String title;
  final String content;
  final String? imageUrl;
  final List<String> imageUrls;
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
    this.imageUrls = const [],
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
    final profile = map['profiles'];
    final profileMap = profile is Map<String, dynamic> ? profile : null;
    final rawUsername = profileMap?['username'] ?? map['username'];
    final rawAvatar = profileMap?['avatar_url'] ?? map['author_avatar_url'];
    final parsedImageUrls = _parseImageUrls(map['image_urls'] ?? map['image_url']);
    final primaryImageUrl = parsedImageUrls.isNotEmpty ? parsedImageUrls.first : null;
  
    return Blog(
      id: map['id'] ?? 0,
      title: map['title']?.toString() ?? 'No Title',
      content: content,
      imageUrl: primaryImageUrl,
      imageUrls: parsedImageUrls,
      excerpt: content.isNotEmpty
          ? (content.length > 50 ? '${content.substring(0, 50)}...' : content)
          : null,
      userId: map['user_id']?.toString() ?? 'unknown_user',
      username: (rawUsername ?? 'Anonymous').toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      isLiked: map['is_liked'] ?? false, 
      likesCount: map['likes_count'] ?? 0,
      authorAvatarUrl: rawAvatar?.toString(),
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
      if (raw.contains(',')) {
        return raw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return [raw];
    }
    return [];
  }

 Blog copyWith({
  int? id,
  String? title,
  String? content,
  String? imageUrl,
  List<String>? imageUrls,
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
  final nextImageUrls = imageUrls ?? this.imageUrls;
  final nextImageUrl =
      imageUrl ?? (nextImageUrls.isNotEmpty ? nextImageUrls.first : null);

  return Blog(
    id: id ?? this.id,
    title: title ?? this.title,
    content: content ?? this.content,
    imageUrl: nextImageUrl,
    imageUrls: nextImageUrls,
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

