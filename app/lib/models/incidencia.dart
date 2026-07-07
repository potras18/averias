class Incidencia {
  final String id;
  final String machineId;
  final String? machineName;
  final String? locationName;
  final String? reportedByName;
  final String? resolvedByName;
  final String? machineProblemType;
  final String? cardReaderProblemType;
  final String? comment;
  final String status; // 'open' | 'resolved'
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolution; // 'operative' | 'in_repair'

  const Incidencia({
    required this.id,
    required this.machineId,
    this.machineName,
    this.locationName,
    this.reportedByName,
    this.resolvedByName,
    this.machineProblemType,
    this.cardReaderProblemType,
    this.comment,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.resolution,
  });

  factory Incidencia.fromJson(Map<String, dynamic> json) => Incidencia(
        id: json['id'] as String,
        machineId: json['machine_id'] as String,
        machineName: json['machine_name'] as String?,
        locationName: json['location_name'] as String?,
        reportedByName: json['reported_by_name'] as String?,
        resolvedByName: json['resolved_by_name'] as String?,
        machineProblemType: json['machine_problem_type'] as String?,
        cardReaderProblemType: json['card_reader_problem_type'] as String?,
        comment: json['comment'] as String?,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        resolvedAt: json['resolved_at'] != null
            ? DateTime.parse(json['resolved_at'] as String)
            : null,
        resolution: json['resolution'] as String?,
      );
}
