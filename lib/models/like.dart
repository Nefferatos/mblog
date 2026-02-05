class Like {
  final int id;
  final int blogId;
  final String userId;

  Like({
    required this.id,
    required this.blogId,
    required this.userId,
  });

  factory Like.fromMap(Map<String, dynamic> map) {
    return Like(
      id: map['id'],
      blogId: map['blog_id'],
      userId: map['user_id']?.toString() ?? '',
    );
  }
}
