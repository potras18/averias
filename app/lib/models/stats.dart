class TopMachine {
  final String name;
  final int faultCount;

  const TopMachine({required this.name, required this.faultCount});

  factory TopMachine.fromJson(Map<String, dynamic> json) => TopMachine(
    name: json['name'] as String,
    faultCount: json['fault_count'] as int,
  );
}

class MttrTopMachine {
  final String name;
  final double avgHours;

  const MttrTopMachine({required this.name, required this.avgHours});

  factory MttrTopMachine.fromJson(Map<String, dynamic> json) => MttrTopMachine(
    name: json['name'] as String,
    avgHours: (json['avg_hours'] as num).toDouble(),
  );
}

class DailyBreakdown {
  final DateTime date;
  final int operative;
  final int outOfService;
  final int inRepair;

  const DailyBreakdown({
    required this.date,
    required this.operative,
    required this.outOfService,
    required this.inRepair,
  });

  factory DailyBreakdown.fromJson(Map<String, dynamic> json) => DailyBreakdown(
    date: DateTime.parse(json['date'] as String),
    operative: json['operative'] as int,
    outOfService: json['out_of_service'] as int,
    inRepair: json['in_repair'] as int,
  );
}

class CardReaderStats {
  final double pctOk;
  final double pctFail;
  final String? topFailureType;

  const CardReaderStats({
    required this.pctOk,
    required this.pctFail,
    this.topFailureType,
  });

  factory CardReaderStats.fromJson(Map<String, dynamic> json) => CardReaderStats(
    pctOk: (json['pct_ok'] as num).toDouble(),
    pctFail: (json['pct_fail'] as num).toDouble(),
    topFailureType: json['top_failure_type'] as String?,
  );
}

class DispenserStats {
  final double pctOk;
  final double pctNoCheck;
  final double pctFull;
  final double pctLow;
  final double pctEmpty;

  const DispenserStats({
    required this.pctOk,
    required this.pctNoCheck,
    required this.pctFull,
    required this.pctLow,
    required this.pctEmpty,
  });

  factory DispenserStats.fromJson(Map<String, dynamic> json) => DispenserStats(
    pctOk:     (json['pct_ok']       as num).toDouble(),
    pctNoCheck: (json['pct_no_check'] as num).toDouble(),
    pctFull:   (json['pct_full']     as num).toDouble(),
    pctLow:    (json['pct_low']      as num).toDouble(),
    pctEmpty:  (json['pct_empty']    as num).toDouble(),
  );
}

class StatsResult {
  final double? mttrHours;
  final double? mttrMedianHours;
  final double pctOperative;
  final double pctOutOfService;
  final double pctInRepair;
  final int totalMachines;
  final List<TopMachine> topProblematic;
  final List<MttrTopMachine> mttrTopMachines;
  final List<DailyBreakdown> dailyBreakdown;
  final CardReaderStats cardReaderStats;
  final DispenserStats dispenserStats;
  final double? avgResolutionHours;
  final double? medianResolutionHours;
  final int openIncidencias;
  final int resolvedIncidencias;

  const StatsResult({
    required this.mttrHours,
    required this.mttrMedianHours,
    required this.pctOperative,
    required this.pctOutOfService,
    required this.pctInRepair,
    required this.totalMachines,
    required this.topProblematic,
    required this.mttrTopMachines,
    required this.dailyBreakdown,
    required this.cardReaderStats,
    required this.dispenserStats,
    this.avgResolutionHours,
    this.medianResolutionHours,
    this.openIncidencias = 0,
    this.resolvedIncidencias = 0,
  });

  factory StatsResult.fromJson(Map<String, dynamic> json) => StatsResult(
    mttrHours:       (json['mttr_hours'] as num?)?.toDouble(),
    mttrMedianHours: (json['mttr_median_hours'] as num?)?.toDouble(),
    pctOperative:    (json['pct_operative'] as num).toDouble(),
    pctOutOfService: (json['pct_out_of_service'] as num).toDouble(),
    pctInRepair:     (json['pct_in_repair'] as num).toDouble(),
    totalMachines:   json['total_machines'] as int,
    topProblematic:  (json['top_problematic'] as List)
        .map((e) => TopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
    mttrTopMachines: (json['mttr_top_machines'] as List)
        .map((e) => MttrTopMachine.fromJson(e as Map<String, dynamic>))
        .toList(),
    dailyBreakdown:  (json['daily_breakdown'] as List)
        .map((e) => DailyBreakdown.fromJson(e as Map<String, dynamic>))
        .toList(),
    cardReaderStats: CardReaderStats.fromJson(
        json['card_reader_stats'] as Map<String, dynamic>),
    dispenserStats:  DispenserStats.fromJson(
        json['dispenser_stats'] as Map<String, dynamic>),
    avgResolutionHours:    (json['avg_resolution_hours'] as num?)?.toDouble(),
    medianResolutionHours: (json['median_resolution_hours'] as num?)?.toDouble(),
    openIncidencias:       json['open_incidencias'] as int? ?? 0,
    resolvedIncidencias:   json['resolved_incidencias'] as int? ?? 0,
  );
}
