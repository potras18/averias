class SparePart {
  final String id;
  final String machineId;
  final String machineName;
  final String description;
  final int quantity;
  final String status;
  final String createdBy;
  final String createdByName;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SparePart({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.description,
    required this.quantity,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SparePart.fromJson(Map<String, dynamic> j) => SparePart(
        id:            j['id'] as String,
        machineId:     j['machine_id'] as String,
        machineName:   j['machine_name'] as String,
        description:   j['description'] as String,
        quantity:      j['quantity'] as int,
        status:        j['status'] as String,
        createdBy:     j['created_by'] as String,
        createdByName: j['created_by_name'] as String,
        updatedBy:     j['updated_by'] as String?,
        createdAt:     DateTime.parse(j['created_at'] as String),
        updatedAt:     DateTime.parse(j['updated_at'] as String),
      );
}
