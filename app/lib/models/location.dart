class Location {
  final String id;
  final String name;
  final String? address;

  const Location({required this.id, required this.name, this.address});

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String?,
  );
}
