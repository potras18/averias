class TopMachine {
  final String name;
  final int faultCount;

  const TopMachine({required this.name, required this.faultCount});

  factory TopMachine.fromJson(Map<String, dynamic> json) => TopMachine(
    name: json['name'] as String,
    faultCount: json['fault_count'] as int,
  );
}

class StatsResult {
  final double? mttrHours;
  final double pctOperative;
  final double pctOutOfService;
  final double pctInRepair;
  final int totalMachines;
  final List<TopMachine> topProblematic;

  const StatsResult({
    required this.mttrHours,
    required this.pctOperative,
    required this.pctOutOfService,
    required this.pctInRepair,
    required this.totalMachines,
    required this.topProblematic,
  });

  factory StatsResult.fromJson(Map<String, dynamic> json) => StatsResult(
    mttrHours:       (json['mttr_hours'] as num?)?.toDouble(),
    pctOperative:    (json['pct_operative'] as num).toDouble(),
    pctOutOfService: (json['pct_out_of_service'] as num).toDouble(),
    pctInRepair:     (json['pct_in_repair'] as num).toDouble(),
    totalMachines:   json['total_machines'] as int,
    topProblematic:  (json['top_problematic'] as List)
        .map((e) => TopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
