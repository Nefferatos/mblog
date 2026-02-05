import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/blog.dart';
import '../models/comment.dart';
import '../models/like.dart';
import 'dart:typed_data';
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

Future<Blog> createBlog(String title, String content, String userId,
    {String? username, String? imageUrl}) async {
  final response = await Supabase.instance.client.from('blogs').insert({
    'title': title,
    'content': content,
    'user_id': userId,
    'username': username, 
    'image_url': imageUrl,
    'created_at': DateTime.now().toIso8601String(),
  }).select().single();

  return Blog.fromMap(response);
}


  Future<bool> updateBlog(
    int id, {
    String? title,
    String? content,
    String? imageUrl,
  }) async {
    try {
      await client
          .from('blogs')
          .update({
            'title': ?title,
            'content': ?content,
            'image_url': ?imageUrl,
          })
          .eq('id', id);
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
    final data = await client
        .from('comments')
        .select()
        .eq('blog_id', blogId)
        .order('created_at', ascending: true);
    return (data as List).map((e) => Comment.fromMap(e)).toList();
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

    final res = await client.from('comments').insert({
      'blog_id': blogId,
      'user_id': user.id,
      'content': content,
      'image_url': imageUrl,
      'user_name': username,
    }).select();

    return Comment.fromMap((res as List).first);
  } catch (e) {
    debugPrint('Error creating comment: $e');
    return null;
  }
}
  Future<bool> updateComment(int id, String content, String? imageUrl) async {
    try {
      await client
          .from('comments')
          .update({'content': content, 'image_url': imageUrl})
          .eq('id', id);
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
      if (kIsWeb) {
        final bytes = file as Uint8List;
        await client.storage
            .from('comment-images')
            .uploadBinary(
              filename,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );
      } else {
        await client.storage.from('comment-images').upload(filename, file);
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
          .select()
          .eq('blog_id', blog.id)
          .eq('user_id', userId)
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
          .select()
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
  
}
