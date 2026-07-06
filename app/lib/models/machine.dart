import 'inspection.dart';

class Machine {
  final String id;
  final String name;
  final String qrCode;
  final String? locationId;
  final String? locationName;
  final bool hasRedemptionTickets;
  final bool active;
  final String? lastStatus;
  final DateTime? lastInspectedAt;
  final List<Inspection> inspections;
  final bool? inspected;
  final bool hasImage;

  const Machine({
    required this.id,
    required this.name,
    required this.qrCode,
    this.locationId,
    this.locationName,
    required this.hasRedemptionTickets,
    required this.active,
    this.lastStatus,
    this.lastInspectedAt,
    this.inspections = const [],
    this.inspected,
    this.hasImage = false,
  });

  factory Machine.fromJson(Map<String, dynamic> json) => Machine(
        id: json['id'] as String,
        name: json['name'] as String,
        qrCode: json['qr_code'] as String,
        locationId: json['location_id'] as String?,
        locationName: json['location_name'] as String?,
        hasRedemptionTickets: json['has_redemption_tickets'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
        lastStatus: json['last_status'] as String?,
        lastInspectedAt: json['last_inspected_at'] != null
            ? DateTime.parse(json['last_inspected_at'] as String)
            : null,
        inspections: (json['inspections'] as List<dynamic>?)
                ?.map((e) => Inspection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        inspected: json['inspected'] as bool?,
        hasImage: json['has_image'] as bool? ?? false,
      );
}
