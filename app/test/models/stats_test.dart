import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/models/stats.dart';

void main() {
  group('StatsResult.fromJson', () {
    test('parses all fields', () {
      final result = StatsResult.fromJson({
        'mttr_hours': 4.5,
        'pct_operative': 75.0,
        'pct_out_of_service': 15.0,
        'pct_in_repair': 10.0,
        'total_machines': 12,
        'top_problematic': [
          {'name': 'Máquina A', 'fault_count': 5},
        ],
      });
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
      final result = StatsResult.fromJson({
        'mttr_hours': null,
        'pct_operative': 100.0,
        'pct_out_of_service': 0.0,
        'pct_in_repair': 0.0,
        'total_machines': 5,
        'top_problematic': [],
      });
      expect(result.mttrHours, isNull);
      expect(result.topProblematic, isEmpty);
    });
  });
}
