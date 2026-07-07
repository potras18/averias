class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool active;
  final String? locationId;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.active = true,
    this.locationId,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String? ?? 'technician',
    active: json['active'] as bool? ?? true,
    locationId: json['location_id'] as String?,
  );
}
