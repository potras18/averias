class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool active;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String? ?? 'technician',
    active: json['active'] as bool? ?? true,
  );
}
