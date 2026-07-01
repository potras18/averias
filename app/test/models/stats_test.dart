import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/stats.dart';

Map<String, dynamic> _fullStatsJson() => {
  'mttr_hours': 4.5,
  'mttr_median_hours': 3.2,
  'pct_operative': 75.0,
  'pct_out_of_service': 15.0,
  'pct_in_repair': 10.0,
  'total_machines': 12,
  'top_problematic': [
    {'name': 'Máquina A', 'fault_count': 5},
  ],
  'mttr_top_machines': [
    {'name': 'Máquina C', 'avg_hours': 12.4},
  ],
  'daily_breakdown': [
    {'date': '2026-06-01', 'operative': 3, 'out_of_service': 1, 'in_repair': 0},
    {'date': '2026-06-02', 'operative': 2, 'out_of_service': 0, 'in_repair': 1},
  ],
  'card_reader_stats': {
    'pct_ok': 82.5,
    'pct_fail': 17.5,
    'top_failure_type': 'no_lee',
  },
  'dispenser_stats': {
    'pct_ok': 90.0,
    'pct_no_check': 10.0,
    'pct_full': 50.0,
    'pct_low': 30.0,
    'pct_empty': 10.0,
  },
};

void main() {
  group('DailyBreakdown.fromJson', () {
    test('parses all fields', () {
      final d = DailyBreakdown.fromJson({'date': '2026-06-01', 'operative': 3, 'out_of_service': 1, 'in_repair': 0});
      expect(d.date, DateTime(2026, 6, 1));
      expect(d.operative, 3);
      expect(d.outOfService, 1);
      expect(d.inRepair, 0);
    });
  });

  group('CardReaderStats.fromJson', () {
    test('parses pct fields and top_failure_type', () {
      final cr = CardReaderStats.fromJson({'pct_ok': 82.5, 'pct_fail': 17.5, 'top_failure_type': 'no_lee'});
      expect(cr.pctOk, 82.5);
      expect(cr.pctFail, 17.5);
      expect(cr.topFailureType, 'no_lee');
    });

    test('top_failure_type is null when absent', () {
      final cr = CardReaderStats.fromJson({'pct_ok': 100.0, 'pct_fail': 0.0, 'top_failure_type': null});
      expect(cr.topFailureType, isNull);
    });
  });

  group('DispenserStats.fromJson', () {
    test('parses all pct fields', () {
      final d = DispenserStats.fromJson({
        'pct_ok': 90.0, 'pct_no_check': 10.0,
        'pct_full': 50.0, 'pct_low': 30.0, 'pct_empty': 10.0,
      });
      expect(d.pctOk, 90.0);
      expect(d.pctNoCheck, 10.0);
      expect(d.pctFull, 50.0);
      expect(d.pctLow, 30.0);
      expect(d.pctEmpty, 10.0);
    });
  });

  group('StatsResult.fromJson', () {
    test('parses complete JSON including new fields', () {
      final s = StatsResult.fromJson(_fullStatsJson());
      expect(s.dailyBreakdown.length, 2);
      expect(s.dailyBreakdown[0].operative, 3);
      expect(s.cardReaderStats.pctOk, 82.5);
      expect(s.cardReaderStats.topFailureType, 'no_lee');
      expect(s.dispenserStats.pctNoCheck, 10.0);
      expect(s.dispenserStats.pctFull, 50.0);
    });

    test('parses all base fields', () {
      final result = StatsResult.fromJson(_fullStatsJson());
      expect(result.mttrHours, 4.5);
      expect(result.pctOperative, 75.0);
      expect(result.pctOutOfService, 15.0);
      expect(result.pctInRepair, 10.0);
      expect(result.totalMachines, 12);
      expect(result.topProblematic.length, 1);
      expect(result.topProblematic[0].name, 'Máquina A');
      expect(result.topProblematic[0].faultCount, 5);
    });

    test('handles null mttr_hours', () {
      final json = _fullStatsJson();
      json['mttr_hours'] = null;
      json['mttr_median_hours'] = null;
      json['top_problematic'] = [];
      json['mttr_top_machines'] = [];
      final result = StatsResult.fromJson(json);
      expect(result.mttrHours, isNull);
      expect(result.mttrMedianHours, isNull);
      expect(result.topProblematic, isEmpty);
      expect(result.mttrTopMachines, isEmpty);
    });
  });
}
