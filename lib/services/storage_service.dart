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
  Future<String?> uploadProfileImage(
  dynamic file,
  String userId,
) async {
  final path = 'avatar/avatar-$userId-${DateTime.now().millisecondsSinceEpoch}.png';

  try {
    if (kIsWeb) {
      final bytes =
          file is Uint8List ? file : await file.readAsBytes();

      await client.storage.from('blog-images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/png',
            ),
          );
    } else {
      await client.storage.from('blog-images').upload(
            path,
            file,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/png',
            ),
          );
    }

    return path;
  } catch (e) {
    debugPrint('Profile upload error: $e');
    return null;
  }
}

}
