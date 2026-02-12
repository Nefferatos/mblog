import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  final SupabaseClient client = Supabase.instance.client;

  Future<String?> uploadImage(
    dynamic file,
    String path,
    {String? contentType}
  ) async {
    try {
      if (kIsWeb) {
        final bytes = file as Uint8List;

        await client.storage.from('blog-images').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: contentType ?? _mimeTypeFromPath(path),
              ),
            );
      }
      else {
        await client.storage.from('blog-images').upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType ?? _mimeTypeFromPath(path)),
        );
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
  {String? originalFileName, String? contentType}
) async {
  final ext = _extensionFromName(originalFileName);
  final path = 'avatar/avatar-$userId-${DateTime.now().millisecondsSinceEpoch}.$ext';

  try {
    if (kIsWeb) {
      final bytes =
          file is Uint8List ? file : await file.readAsBytes();

      await client.storage.from('blog-images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType ?? _mimeTypeFromPath(path),
            ),
          );
    } else {
      await client.storage.from('blog-images').upload(
            path,
            file,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType ?? _mimeTypeFromPath(path),
            ),
          );
    }

    return path;
  } catch (e) {
    debugPrint('Profile upload error: $e');
    return null;
  }
}

String _extensionFromName(String? name) {
  if (name == null || !name.contains('.')) return 'jpg';
  final ext = name.split('.').last.toLowerCase().trim();
  if (ext.isEmpty || ext.length > 8) return 'jpg';
  return ext;
}

String _mimeTypeFromPath(String path) {
  final ext = _extensionFromName(path);
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
    case 'jfif':
      return 'image/jpeg';
    case 'pjpeg':
      return 'image/jpeg';
    case 'svg':
      return 'image/svg+xml';
    default:
      return 'image/jpeg';
  }
}

}
