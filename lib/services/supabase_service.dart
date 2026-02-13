import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/blog.dart';
import '../models/comment.dart';
import '../models/like.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class SupabaseService {
  final SupabaseClient client = Supabase.instance.client;

  Future<List<Blog>> getBlogs() async {
    final data = await client
        .from('blogs')
        .select('''
          *,
          profiles:user_id (
            username,
            avatar_url
          )
        ''')
        .order('created_at', ascending: false);
    return (data as List).map((e) => Blog.fromMap(e)).toList();
  }

Future<Blog> createBlog(
  String title,
  String content,
  String userId, {
  String? username,
  String? imageUrl,
  List<String>? imageUrls,
}) async {
  final resolvedImageUrls = imageUrls ?? const [];
  final createdAtIso = DateTime.now().toIso8601String();
  final payload = {
    'title': title,
    'content': content,
    'user_id': userId,
    'username': username, 
    'image_url': resolvedImageUrls.isNotEmpty
        ? jsonEncode(resolvedImageUrls)
        : imageUrl,
    'created_at': createdAtIso,
  };
  final payloadWithUpdatedAt = {
    ...payload,
    'updated_at': createdAtIso,
  };

  dynamic response;
  try {
    response = await Supabase.instance.client
        .from('blogs')
        .insert(payloadWithUpdatedAt)
        .select()
        .single();
  } catch (e) {
    if (_isMissingColumnError(e, 'updated_at', 'blogs')) {
      response = await Supabase.instance.client
          .from('blogs')
          .insert(payload)
          .select()
          .single();
    } else {
      rethrow;
    }
  }

  return Blog.fromMap(response);
}


  Future<bool> updateBlog(
    int id, {
    String? title,
    String? content,
    String? imageUrl,
    List<String>? imageUrls,
  }) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (content != null) updates['content'] = content;
      if (imageUrls != null) {
        updates['image_url'] = imageUrls.isNotEmpty ? jsonEncode(imageUrls) : null;
      } else if (imageUrl != null) {
        updates['image_url'] = imageUrl;
      }
      if (updates.isEmpty) return true;
      final updatesWithTimestamp = {
        ...updates,
        'updated_at': nowIso,
      };

      try {
        await client
            .from('blogs')
            .update(updatesWithTimestamp)
            .eq('id', id);
      } catch (e) {
        // Fallback for schemas that don't have blogs.updated_at yet.
        if (_isMissingColumnError(e, 'updated_at', 'blogs')) {
          await client
              .from('blogs')
              .update(updates)
              .eq('id', id);
        } else {
          rethrow;
        }
      }
      return true;
    } catch (e) {
      print('Error updating blog: $e');
      return false;
    }
  }

  Future<bool> deleteBlog(int id) async {
    try {
      await client.from('blogs').delete().eq('id', id);
      return true;
    } catch (e) {
      print('Error deleting blog: $e');
      return false;
    }
  }

  Future<List<Comment>> getComments(int blogId) async {
    try {
      final data = await client
          .from('comments')
          .select('*, profiles:user_id(avatar_url)')
          .eq('blog_id', blogId)
          .order('created_at', ascending: true);
      return (data as List).map((e) => Comment.fromMap(e)).toList();
    } catch (e) {
      debugPrint('Comments join query failed, using fallback: $e');
      final data = await client
          .from('comments')
          .select('*')
          .eq('blog_id', blogId)
          .order('created_at', ascending: true);
      return (data as List).map((e) => Comment.fromMap(e)).toList();
    }
  }

Future<Comment?> addComment(
  int blogId,
  String content,
  String? imageUrl,
  String username, 
) async {
  try {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final createdAtIso = DateTime.now().toIso8601String();
    final payload = {
      'blog_id': blogId,
      'user_id': user.id,
      'content': content,
      'image_url': imageUrl,
      'user_name': username,
      'created_at': createdAtIso,
    };
    final payloadWithUpdatedAt = {
      ...payload,
      'updated_at': createdAtIso,
    };

    dynamic res;
    try {
      res = await client
          .from('comments')
          .insert(payloadWithUpdatedAt)
          .select();
    } catch (e) {
      if (_isMissingColumnError(e, 'updated_at', 'comments')) {
        res = await client
            .from('comments')
            .insert(payload)
            .select();
      } else {
        rethrow;
      }
    }

    return Comment.fromMap((res as List).first);
  } catch (e) {
    debugPrint('Error creating comment: $e');
    return null;
  }
}
  Future<bool> updateComment(int id, String content, String? imageUrl) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'content': content,
        'image_url': imageUrl,
      };
      final updatesWithTimestamp = {
        ...updates,
        'updated_at': nowIso,
      };

      try {
        await client
            .from('comments')
            .update(updatesWithTimestamp)
            .eq('id', id);
      } catch (e) {
        // Fallback for schemas that don't have comments.updated_at yet.
        if (_isMissingColumnError(e, 'updated_at', 'comments')) {
          await client
              .from('comments')
              .update(updates)
              .eq('id', id);
        } else {
          rethrow;
        }
      }
      return true;
    } catch (e) {
      print('Error updating comment: $e');
      return false;
    }
  }

  Future<bool> deleteComment(int id) async {
    try {
      await client.from('comments').delete().eq('id', id);
      return true;
    } catch (e) {
      print('Error deleting comment: $e');
      return false;
    }
  }

  Future<String?> uploadCommentImage(dynamic file, String filename) async {
    try {
      final contentType = _mimeTypeFromPath(filename);
      if (kIsWeb) {
        final bytes = file as Uint8List;
        await client.storage
            .from('comment-images')
            .uploadBinary(
              filename,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
      } else {
        await client.storage.from('comment-images').upload(
          filename,
          file,
          fileOptions: FileOptions(contentType: contentType),
        );
      }
      return filename; 
    } catch (e) {
      print('Error uploading comment image: $e');
      return null;
    }
  }


  Future<List<Like>> getLikes(int blogId) async {
    final data = await client.from('likes').select().eq('blog_id', blogId);
    return (data as List).map((e) => Like.fromMap(e)).toList();
  }

  Future<bool> likeBlog(int blogId, String userId) async {
    try {
      await client.from('likes').insert({'blog_id': blogId, 'user_id': userId});
      return true;
    } catch (e) {
      print('Error liking blog: $e');
      return false;
    }
  }

Future<List<Blog>> getBlogsByUser(String userId) async {
  try {
    final currentUserId = client.auth.currentUser?.id;

    final response = await client
        .from('blogs')
        .select('*, likes(*)') 
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final data = response as List;

    return data.map((e) {
      final blog = Blog.fromMap(e);

      final likesList = (e['likes'] as List?) ?? [];
      final likesCount = likesList.length;
      final isLiked = currentUserId != null &&
          likesList.any((like) => like['user_id'] == currentUserId);

      return blog.copyWith(
        likesCount: likesCount,
        isLiked: isLiked,
      );
    }).toList();
  } catch (e) {
    debugPrint('Error fetching user blogs: $e');
    return [];
  }
}

  Future<bool> unlikeBlog(int blogId, String userId) async {
    try {
      await client
          .from('likes')
          .delete()
          .eq('blog_id', blogId)
          .eq('user_id', userId);
      return true;
    } catch (e) {
      print('Error unliking blog: $e');
      return false;
    }
  }

  Future<dynamic> addLike(int id, String s) async {}

  Future<void> removeLike(int id) async {}
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await client
        .from('profiles')
        .select('id, username, email')
        .or('username.ilike.%$query%,email.ilike.%$query%')
        .limit(20);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<Blog?> toggleLike(Blog blog, String userId) async {
    try {
      final existing = await client
          .from('likes')
          .select('id')
          .eq('blog_id', blog.id)
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('likes')
            .delete()
            .eq('blog_id', blog.id)
            .eq('user_id', userId);
      } else {
        await client.from('likes').insert({
          'blog_id': blog.id,
          'user_id': userId,
        });
      }

      final likesData = await client
          .from('likes')
          .select('user_id')
          .eq('blog_id', blog.id);

      final likesList = likesData as List;
      final likesCount = likesList.length;
      final isLiked = likesList.any((like) => like['user_id'] == userId);


      return blog.copyWith(likesCount: likesCount, isLiked: isLiked);
    } catch (e) {
      debugPrint('Error toggling like: $e');
      return null;
    }
  }

  String _mimeTypeFromPath(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase().trim() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'avif':
        return 'image/avif';
      default:
        return 'application/octet-stream';
    }
  }

  bool _isMissingColumnError(Object error, String column, String table) {
    final raw = error.toString().toLowerCase();
    return raw.contains("'$column'") &&
        raw.contains("'$table'") &&
        raw.contains('schema cache');
  }
  
}
