class TicketCheck {
  final bool dispenserOk;
  final String ticketLevel; // full | low | empty

  const TicketCheck({required this.dispenserOk, required this.ticketLevel});

  factory TicketCheck.fromJson(Map<String, dynamic> json) => TicketCheck(
        dispenserOk: json['dispenser_ok'] as bool,
        ticketLevel: json['ticket_level'] as String,
      );

  Map<String, dynamic> toJson() => {
        'dispenser_ok': dispenserOk,
        'ticket_level': ticketLevel,
      };
}

class Inspection {
  final String id;
  final String machineId;
  final String? technicianName;
  final String status; // operative | out_of_service | in_repair
  final bool cardReaderOk;
  final String? cardReaderFailureType;
  final String? comment;
  final DateTime inspectedAt;
  final TicketCheck? ticketCheck;

  const Inspection({
    required this.id,
    required this.machineId,
    this.technicianName,
    required this.status,
    required this.cardReaderOk,
    this.cardReaderFailureType,
    this.comment,
    required this.inspectedAt,
    this.ticketCheck,
  });

  factory Inspection.fromJson(Map<String, dynamic> json) => Inspection(
        id: json['id'] as String,
        machineId: json['machine_id'] as String,
        technicianName: json['technician_name'] as String?,
        status: json['status'] as String,
        cardReaderOk: json['card_reader_ok'] as bool,
        cardReaderFailureType: json['card_reader_failure_type'] as String?,
        comment: json['comment'] as String?,
        inspectedAt: DateTime.parse(json['inspected_at'] as String),
        ticketCheck: json['ticket_check'] != null
            ? TicketCheck.fromJson(json['ticket_check'] as Map<String, dynamic>)
            : null,
      );
}
