import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;
  User? get currentUser => _client.auth.currentUser;
  String? get userId => currentUser?.id;
  String? get userEmail => currentUser?.email;
  
  String get displayName {
    final user = currentUser;
    if (user == null) return 'Guest';

    return user.userMetadata?['display_name'] ??
        user.email ??
        'Guest';
  }

  /// Sign up user
  Future<User?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        if (displayName != null) 'display_name': displayName,
      },
    );

    return response.user;
  }

  Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> updateDisplayName(String displayName) async {
    if (currentUser == null) return;

    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'display_name': displayName,
        },
      ),
    );
  }
}