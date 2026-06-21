import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class LoginScreen extends StatelessWidget {
  final ApiClient api;
  final StorageService storage;
  const LoginScreen({super.key, required this.api, required this.storage});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Login')));
}
