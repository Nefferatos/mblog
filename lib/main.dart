import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/blog_list_page.dart';
import 'pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ifcarekzqlvxbumqttns.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmY2FyZWt6cWx2eGJ1bXF0dG5zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyMDYwNzAsImV4cCI6MjA4Mzc4MjA3MH0.Rx5QzZDDUI2-4XxOROHxRyVzWmLD5ngRJy740PPDFFw',
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Simple Blog App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Supabase.instance.client.auth.currentUser != null
          ? const BlogListPage()
          : const LoginPage(),
    );
  }
}