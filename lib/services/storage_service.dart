import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  final SupabaseClient client = Supabase.instance.client;

  Future<String?> uploadImage(
    dynamic file,
    String path,
  ) async {
    try {
      if (kIsWeb) {
        final bytes = file as Uint8List;

        await client.storage.from('blog-images').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/png',
              ),
            );
      }
      else {
        await client.storage.from('blog-images').upload(path, file);
      }

      return client.storage.from('blog-images').getPublicUrl(path);
    } catch (e) {
      print('Storage upload error: $e');
      return null;
    }
  }
  Future<String> uploadProfileImage(dynamic file, String userId) async {
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = 'avatars/$userId/$fileName';

    final storage = client.storage.from('blog-images');

    if (kIsWeb) {
      await storage.uploadBinary(
        path,
        file as Uint8List,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
    } else {
      await storage.upload(path, file);
    }

    return path; 
  }

}
