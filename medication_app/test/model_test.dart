import 'package:flutter_test/flutter_test.dart';
import 'package:medication_app/main.dart';

void main() {
  test('medicine and records survive JSON serialization', () {
    final medicine = Medicine(12, '測試藥', '1 顆', [480, 1320]);
    final restored = Medicine.fromJson(medicine.toJson());
    expect(restored.times, [480, 1320]);
    expect(clockTime(restored.times.last), '22:00');
    final record = DoseRecord(
      12,
      '測試藥',
      '1 顆',
      '2026-09-22',
      480,
      '略過',
      DateTime(2026, 9, 22, 8),
    );
    expect(DoseRecord.fromJson(record.toJson()).key, '12:2026-09-22:480');
  });

  test('legacy medicine loads with inventory tracking disabled', () {
    final medicine = Medicine.fromJson({
      'id': 1,
      'name': '舊藥',
      'dose': '1 顆',
      'times': [480],
    });
    expect(medicine.active, isTrue);
    expect(medicine.stock, isNull);
    expect(medicine.applyDoseChange(null, '已服用'), 0);
  });

  test('taken, skipped, and corrected records adjust stock once', () {
    final medicine = Medicine(
      2,
      '測試藥',
      '2 顆',
      [480],
      stock: 5,
      unitsPerDose: 2,
    );
    final taken = medicine.applyDoseChange(null, '已服用');
    expect(taken, 2);
    expect(medicine.stock, 3);
    final previous = DoseRecord(
      2,
      '測試藥',
      '2 顆',
      '2026-09-22',
      480,
      '已服用',
      DateTime(2026, 9, 22, 8),
      deductedUnits: taken,
    );
    expect(medicine.applyDoseChange(previous, '略過'), 0);
    expect(medicine.stock, 5);
    expect(medicine.applyDoseChange(null, '已服用'), 2);
    expect(medicine.stock, 3);
  });

  test('stock never becomes negative when a dose is recorded', () {
    final medicine = Medicine(
      3,
      '測試藥',
      '2 顆',
      [480],
      stock: 1,
      unitsPerDose: 2,
    );
    expect(medicine.applyDoseChange(null, '已服用'), 1);
    expect(medicine.stock, 0);
  });
}
