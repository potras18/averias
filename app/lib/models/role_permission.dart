class RolePermission {
  final String role;
  final String key;
  final bool allowed;

  const RolePermission({
    required this.role,
    required this.key,
    required this.allowed,
  });

  factory RolePermission.fromJson(Map<String, dynamic> json) => RolePermission(
        role: json['role'] as String,
        key: json['permission_key'] as String,
        allowed: json['allowed'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'permission_key': key,
        'allowed': allowed,
      };

  RolePermission copyWith({bool? allowed}) => RolePermission(
        role: role,
        key: key,
        allowed: allowed ?? this.allowed,
      );
}
