import 'package:flutter_test/flutter_test.dart';
import 'package:medication_app/main.dart';

void main() {
  test('health entries survive JSON serialization', () {
    final entry = HealthEntry(
      id: 1,
      at: DateTime(2026, 9, 24, 8, 30),
      systolic: 128,
      diastolic: 78,
      heartRate: 72,
      weight: 60.5,
      mood: '不錯',
    );
    final restored = HealthEntry.fromJson(entry.toJson());
    expect(restored.systolic, 128);
    expect(restored.diastolic, 78);
    expect(restored.weight, 60.5);
    expect(restored.mood, '不錯');
  });

  test('symptom guidance uses general department rules', () {
    expect(guideDepartment('我今天喉嚨痛').$1, '耳鼻喉科');
    expect(guideDepartment('皮膚發痒起紅疹').$1, '皮膚科');
    expect(guideDepartment('有胸痛和呼吸困難').$1, '立即尋求緊急醫療協助');
  });

  test('health alerts flag values that need attention', () {
    final entry = HealthEntry(
      id: 1,
      at: DateTime(2026),
      systolic: 150,
      diastolic: 95,
      heartRate: 130,
    );
    expect(healthAlerts(entry), hasLength(2));
  });
}
