import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'web_preferences_stub.dart'
    if (dart.library.js_interop) 'web_preferences_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) registerWebPreferences();
  runApp(const MedicationApp());
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String clockTime(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

class Medicine {
  Medicine(
    this.id,
    this.name,
    this.dose,
    this.times, {
    this.active = true,
    this.stock,
    this.unitsPerDose = 1,
    this.lowStockThreshold = 3,
  });
  final int id;
  String name;
  String dose;
  List<int> times;
  bool active;
  int? stock;
  int unitsPerDose;
  int lowStockThreshold;
  int applyDoseChange(DoseRecord? previous, String status) {
    if (stock == null) return 0;
    if (previous?.status == '已服用') {
      stock = stock! + previous!.deductedUnits;
    }
    if (status != '已服用') return 0;
    final deducted = stock! < unitsPerDose ? stock! : unitsPerDose;
    stock = stock! - deducted;
    return deducted;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dose': dose,
    'times': times,
    'active': active,
    'stock': stock,
    'unitsPerDose': unitsPerDose,
    'lowStockThreshold': lowStockThreshold,
  };
  factory Medicine.fromJson(Map<String, dynamic> x) => Medicine(
    x['id'] as int,
    x['name'] as String,
    x['dose'] as String,
    (x['times'] as List).cast<int>(),
    active: x['active'] as bool? ?? true,
    stock: x['stock'] as int?,
    unitsPerDose: x['unitsPerDose'] as int? ?? 1,
    lowStockThreshold: x['lowStockThreshold'] as int? ?? 3,
  );
}

class DoseRecord {
  DoseRecord(
    this.medicineId,
    this.name,
    this.dose,
    this.day,
    this.time,
    this.status,
    this.at, {
    this.actualAt,
    this.deductedUnits = 0,
  });
  final int medicineId;
  final String name;
  final String dose;
  final String day;
  final int time;
  final String status;
  final DateTime at;
  final DateTime? actualAt;
  final int deductedUnits;
  String get key => '$medicineId:$day:$time';
  Map<String, dynamic> toJson() => {
    'medicineId': medicineId,
    'name': name,
    'dose': dose,
    'day': day,
    'time': time,
    'status': status,
    'at': at.toIso8601String(),
    'actualAt': actualAt?.toIso8601String(),
    'deductedUnits': deductedUnits,
  };
  factory DoseRecord.fromJson(Map<String, dynamic> x) => DoseRecord(
    x['medicineId'] as int,
    x['name'] as String,
    x['dose'] as String,
    x['day'] as String,
    x['time'] as int,
    x['status'] as String,
    DateTime.parse(x['at'] as String),
    actualAt: DateTime.tryParse(x['actualAt'] as String? ?? ''),
    deductedUnits: x['deductedUnits'] as int? ?? 0,
  );
}

class HealthRecord {
  HealthRecord(this.type, this.value, this.at);
  final String type;
  final String value;
  final DateTime at;
  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value,
    'at': at.toIso8601String(),
  };
  factory HealthRecord.fromJson(Map<String, dynamic> x) => HealthRecord(
    x['type'] as String,
    x['value'] as String,
    DateTime.parse(x['at'] as String),
  );
}

class AppStore extends ChangeNotifier {
  static const maxDailyReminders = 64;
  static const maxSnoozes = 4;
  final prefs = SharedPreferencesAsync();
  final notifications = FlutterLocalNotificationsPlugin();
  final medicines = <Medicine>[];
  final records = <DoseRecord>[];
  final health = <HealthRecord>[];
  final snoozes = <String, DateTime>{};
  String name = '';
  DateTime? birthday;
  bool reminders = true;
  bool ready = false;
  bool notificationPermission = false;
  String? notificationError;
  Future<void> load() async {
    try {
      medicines.addAll(
        (jsonDecode(await prefs.getString('medicines') ?? '[]') as List).map(
          (e) => Medicine.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
      records.addAll(
        (jsonDecode(await prefs.getString('records') ?? '[]') as List).map(
          (e) => DoseRecord.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
      health.addAll(
        (jsonDecode(await prefs.getString('health') ?? '[]') as List).map(
          (e) => HealthRecord.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
      name = await prefs.getString('name') ?? '';
      birthday = DateTime.tryParse(await prefs.getString('birthday') ?? '');
      reminders = await prefs.getBool('reminders') ?? true;
      final savedSnoozes = Map<String, dynamic>.from(
        jsonDecode(await prefs.getString('snoozes') ?? '{}') as Map,
      );
      for (final entry in savedSnoozes.entries) {
        final date = DateTime.tryParse(entry.value as String);
        if (date != null && date.isAfter(DateTime.now())) {
          snoozes[entry.key] = date;
        }
      }
    } catch (_) {
      /* Damaged local data must not prevent launch. */
    }
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await refreshNotificationPermission();
      await syncNotifications();
    } catch (error) {
      notificationPermission = false;
      notificationError = '提醒初始化失敗：$error';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> refreshNotificationPermission() async {
    if (!kIsWeb && Platform.isIOS) {
      notificationPermission =
          await notifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } else if (!kIsWeb && Platform.isAndroid) {
      notificationPermission =
          await notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    notifyListeners();
  }

  Future<void> save() async {
    await Future.wait([
      prefs.setString(
        'medicines',
        jsonEncode(medicines.map((e) => e.toJson()).toList()),
      ),
      prefs.setString(
        'records',
        jsonEncode(records.map((e) => e.toJson()).toList()),
      ),
      prefs.setString(
        'health',
        jsonEncode(health.map((e) => e.toJson()).toList()),
      ),
      prefs.setString('name', name),
      prefs.setString('birthday', birthday?.toIso8601String() ?? ''),
      prefs.setBool('reminders', reminders),
      prefs.setString(
        'snoozes',
        jsonEncode(
          snoozes.map((key, value) => MapEntry(key, value.toIso8601String())),
        ),
      ),
    ]);
    notifyListeners();
  }

  Future<void> syncNotifications() async {
    try {
      await notifications.cancelAll();
      notificationError = null;
      if (!reminders || !notificationPermission) return;
      if (medicines
              .where((m) => m.active)
              .fold<int>(
                0,
                (total, medicine) => total + medicine.times.length,
              ) >
          maxDailyReminders - maxSnoozes) {
        notificationError =
            '每日提醒超過 ${maxDailyReminders - maxSnoozes} 次，請減少服藥時間。';
        return;
      }
      for (final medicine in medicines.where((m) => m.active)) {
        for (var i = 0; i < medicine.times.length; i++) {
          final minutes = medicine.times[i];
          final now = tz.TZDateTime.now(tz.local);
          var next = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            minutes ~/ 60,
            minutes % 60,
          );
          if (!next.isAfter(now)) {
            next = tz.TZDateTime(
              tz.local,
              now.year,
              now.month,
              now.day + 1,
              minutes ~/ 60,
              minutes % 60,
            );
          }
          await notifications.zonedSchedule(
            id: medicine.id * 10 + i,
            title: '服藥提醒：${medicine.name}',
            body: '${medicine.dose}・${clockTime(minutes)}',
            scheduledDate: next,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'medication_daily',
                '每日服藥提醒',
                channelDescription: '按每日設定時間提醒服藥',
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      }
      snoozes.removeWhere(
        (key, time) =>
            !time.isAfter(DateTime.now()) ||
            !medicines.any((m) => m.active && key.startsWith('${m.id}:')),
      );
      var snoozeId = 1800000000;
      for (final entry in snoozes.entries.take(maxSnoozes)) {
        final medicineId = int.tryParse(entry.key.split(':').first);
        final match = medicines.where((m) => m.id == medicineId);
        if (match.isEmpty) continue;
        final medicine = match.first;
        await notifications.zonedSchedule(
          id: snoozeId++,
          title: '稍後提醒：${medicine.name}',
          body: medicine.dose,
          scheduledDate: tz.TZDateTime.from(entry.value, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('medication_daily', '每日服藥提醒'),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (error) {
      notificationError = '提醒排程失敗：$error';
    } finally {
      notifyListeners();
    }
  }

  Future<void> addMedicine(
    String n,
    String d,
    List<int> times, {
    bool active = true,
    int? stock,
    int unitsPerDose = 1,
    int lowStockThreshold = 3,
  }) async {
    final currentReminders = medicines
        .where((m) => m.active)
        .fold<int>(0, (total, medicine) => total + medicine.times.length);
    if (active &&
        currentReminders + times.length > maxDailyReminders - maxSnoozes) {
      throw StateError('每日最多可設定 ${maxDailyReminders - maxSnoozes} 次提醒');
    }
    medicines.add(
      Medicine(
        DateTime.now().microsecondsSinceEpoch.remainder(100000000),
        n,
        d,
        times..sort(),
        active: active,
        stock: stock,
        unitsPerDose: unitsPerDose,
        lowStockThreshold: lowStockThreshold,
      ),
    );
    await save();
    await syncNotifications();
  }

  Future<void> updateMedicine(
    Medicine medicine,
    String n,
    String d,
    List<int> times, {
    required bool active,
    int? stock,
    required int unitsPerDose,
    required int lowStockThreshold,
  }) async {
    final otherReminders = medicines
        .where((m) => m.active && m.id != medicine.id)
        .fold<int>(0, (total, m) => total + m.times.length);
    if (active &&
        otherReminders + times.length > maxDailyReminders - maxSnoozes) {
      throw StateError('每日最多可設定 ${maxDailyReminders - maxSnoozes} 次提醒');
    }
    if (!active || !listEquals(medicine.times, times)) {
      snoozes.removeWhere((key, _) => key.startsWith('${medicine.id}:'));
    }
    if (medicine.stock != stock) {
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        if (record.medicineId == medicine.id &&
            record.day == dayKey(DateTime.now()) &&
            record.deductedUnits != 0) {
          records[i] = DoseRecord(
            record.medicineId,
            record.name,
            record.dose,
            record.day,
            record.time,
            record.status,
            record.at,
            actualAt: record.actualAt,
          );
        }
      }
    }
    medicine.name = n;
    medicine.dose = d;
    medicine.times = [...times]..sort();
    medicine.active = active;
    medicine.stock = stock;
    medicine.unitsPerDose = unitsPerDose;
    medicine.lowStockThreshold = lowStockThreshold;
    await save();
    await syncNotifications();
  }

  Future<void> setMedicineActive(Medicine medicine, bool active) async {
    await updateMedicine(
      medicine,
      medicine.name,
      medicine.dose,
      medicine.times,
      active: active,
      stock: medicine.stock,
      unitsPerDose: medicine.unitsPerDose,
      lowStockThreshold: medicine.lowStockThreshold,
    );
  }

  Future<void> deleteMedicine(Medicine m) async {
    medicines.remove(m);
    snoozes.removeWhere((key, _) => key.startsWith('${m.id}:'));
    await save();
    await syncNotifications();
  }

  DoseRecord? recordFor(Medicine m, int time, DateTime day) {
    for (final r in records) {
      if (r.medicineId == m.id && r.time == time && r.day == dayKey(day)) {
        return r;
      }
    }
    return null;
  }

  String doseKey(Medicine m, int time) =>
      '${m.id}:${dayKey(DateTime.now())}:$time';

  Future<void> snooze(Medicine m, int time, Duration delay) async {
    if (!notificationPermission) throw StateError('請先在 iPhone 設定中允許通知');
    snoozes.removeWhere((_, until) => !until.isAfter(DateTime.now()));
    final key = doseKey(m, time);
    if (!snoozes.containsKey(key) && snoozes.length >= maxSnoozes) {
      throw StateError('同時最多可設定 $maxSnoozes 個稍後提醒');
    }
    snoozes[key] = DateTime.now().add(delay);
    await save();
    await syncNotifications();
  }

  Future<void> mark(
    Medicine m,
    int time,
    String status, {
    DateTime? actualAt,
  }) async {
    final old = recordFor(m, time, DateTime.now());
    final before = m.stock;
    final deducted = m.applyDoseChange(old, status);
    final r = DoseRecord(
      m.id,
      m.name,
      m.dose,
      dayKey(DateTime.now()),
      time,
      status,
      DateTime.now(),
      actualAt: status == '已服用' ? (actualAt ?? DateTime.now()) : null,
      deductedUnits: deducted,
    );
    records.removeWhere((x) => x.key == r.key);
    records.add(r);
    snoozes.remove(doseKey(m, time));
    await save();
    await syncNotifications();
    if (status == '已服用' &&
        before != null &&
        before > m.lowStockThreshold &&
        m.stock! <= m.lowStockThreshold &&
        notificationPermission) {
      await notifications.show(
        id: 1900000000 + m.id,
        title: '${m.name} 快用完了',
        body: '剩餘 ${m.stock} 顆，請安排補藥。',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('medication_stock', '補藥提醒'),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }
  }

  Future<void> addHealth(String type, String value) async {
    health.add(HealthRecord(type, value, DateTime.now()));
    await save();
  }

  Future<void> saveProfile(String n, DateTime? b, bool r) async {
    name = n;
    birthday = b;
    reminders = r;
    await save();
    await syncNotifications();
  }
}

class MedicationApp extends StatefulWidget {
  const MedicationApp({super.key});
  @override
  State<MedicationApp> createState() => _MedicationAppState();
}

class _MedicationAppState extends State<MedicationApp>
    with WidgetsBindingObserver {
  final store = AppStore();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && store.ready) {
      store.refreshNotificationPermission().then(
        (_) => store.syncNotifications(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '服藥提醒',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.teal,
      scaffoldBackgroundColor: const Color(0xfff7faf9),
    ),
    home: AnimatedBuilder(
      animation: store,
      builder: (context, child) => store.ready
          ? MainPage(store: store)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.store});
  final AppStore store;
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(store: widget.store),
      MedicinePage(store: widget.store),
      RecordPage(store: widget.store),
      HealthPage(store: widget.store),
      ProfilePage(store: widget.store),
    ];
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '今日'),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            label: '藥物',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '紀錄'),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            label: '健康',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final doses = <(Medicine, int)>[
      for (final m in store.medicines.where((m) => m.active))
        for (final t in m.times) (m, t),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final done = doses
        .where((x) => store.recordFor(x.$1, x.$2, today)?.status == '已服用')
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(store.name.isEmpty ? '今日服藥' : '${store.name}的今日服藥'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${today.month} 月 ${today.day} 日',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '今日已服用 $done / ${doses.length} 次',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (doses.isEmpty)
            const EmptyState(Icons.medication_outlined, '還沒有藥物，請到「藥物」新增。'),
          for (final dose in doses)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.medication, color: Colors.teal),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dose.$1.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(dose.$1.dose),
                              if (dose.$1.stock != null)
                                Text(
                                  '剩餘 ${dose.$1.stock} 顆${dose.$1.stock! <= dose.$1.lowStockThreshold ? '・需要補藥' : ''}',
                                  style: TextStyle(
                                    color:
                                        dose.$1.stock! <=
                                            dose.$1.lowStockThreshold
                                        ? Colors.deepOrange
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          clockTime(dose.$2),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (store.recordFor(dose.$1, dose.$2, today) case final r?)
                      Row(
                        children: [
                          Icon(
                            r.status == '已服用'
                                ? Icons.check_circle
                                : Icons.remove_circle,
                            color: r.status == '已服用'
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.status == '已服用' && r.actualAt != null
                                  ? '已服用・實際 ${clockTime(r.actualAt!.hour * 60 + r.actualAt!.minute)}'
                                  : r.status,
                            ),
                          ),
                          TextButton(
                            onPressed: () => r.status == '已服用'
                                ? store.mark(dose.$1, dose.$2, '略過')
                                : markTaken(context, dose.$1, dose.$2),
                            child: const Text('更改'),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          if (store.snoozes[store.doseKey(dose.$1, dose.$2)]
                              case final until?)
                            Text(
                              '稍後提醒：${clockTime(until.hour * 60 + until.minute)}',
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      store.mark(dose.$1, dose.$2, '略過'),
                                  child: const Text('略過'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      markTaken(context, dose.$1, dose.$2),
                                  child: const Text('已服用'),
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                snoozeDose(context, dose.$1, dose.$2),
                            icon: const Icon(Icons.snooze),
                            label: const Text('稍後提醒'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> markTaken(
    BuildContext context,
    Medicine medicine,
    int time,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: '實際服用時間',
    );
    if (picked == null) return;
    final now = DateTime.now();
    final actual = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (actual.isAfter(now)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('實際服用時間不能晚於現在')));
      }
      return;
    }
    await store.mark(medicine, time, '已服用', actualAt: actual);
  }

  Future<void> snoozeDose(
    BuildContext context,
    Medicine medicine,
    int time,
  ) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('稍後提醒')),
            for (final value in [10, 30, 60])
              ListTile(
                title: Text('$value 分鐘後'),
                onTap: () => Navigator.pop(sheetContext, value),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    try {
      await store.snooze(medicine, time, Duration(minutes: minutes));
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }
}

class MedicinePage extends StatelessWidget {
  const MedicinePage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的藥物')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MedicineEditor(store: store)),
      ),
      icon: const Icon(Icons.add),
      label: const Text('新增藥物'),
    ),
    body: store.medicines.isEmpty
        ? const EmptyState(Icons.medication_outlined, '尚未新增藥物')
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in store.medicines)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.medication)),
                    title: Text(m.name),
                    subtitle: Text(
                      '${m.dose}・${m.active ? '每天' : '已暫停'} ${m.times.map(clockTime).join('、')}${m.stock == null ? '' : '\n剩餘 ${m.stock} 顆'}',
                    ),
                    isThreeLine: m.stock != null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MedicineEditor(store: store, medicine: m),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'edit') {
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MedicineEditor(store: store, medicine: m),
                              ),
                            );
                          }
                        } else if (action == 'active') {
                          try {
                            await store.setMedicineActive(m, !m.active);
                          } on StateError catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(error.message.toString()),
                                ),
                              );
                            }
                          }
                        } else if (action == 'delete') {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('刪除藥物？'),
                              content: Text('將停止 ${m.name} 的提醒，過去紀錄會保留。'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('刪除'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) await store.deleteMedicine(m);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('編輯')),
                        PopupMenuItem(
                          value: 'active',
                          child: Text(m.active ? '暫停提醒' : '恢復提醒'),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('刪除')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

class MedicineEditor extends StatefulWidget {
  const MedicineEditor({super.key, required this.store, this.medicine});
  final AppStore store;
  final Medicine? medicine;
  @override
  State<MedicineEditor> createState() => _MedicineEditorState();
}

class _MedicineEditorState extends State<MedicineEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final dose = TextEditingController();
  final stock = TextEditingController();
  final unitsPerDose = TextEditingController(text: '1');
  final lowStockThreshold = TextEditingController(text: '3');
  late final times = <TimeOfDay>[const TimeOfDay(hour: 8, minute: 0)];
  bool active = true;
  @override
  void initState() {
    super.initState();
    final medicine = widget.medicine;
    if (medicine != null) {
      name.text = medicine.name;
      dose.text = medicine.dose;
      stock.text = medicine.stock?.toString() ?? '';
      unitsPerDose.text = medicine.unitsPerDose.toString();
      lowStockThreshold.text = medicine.lowStockThreshold.toString();
      active = medicine.active;
      times
        ..clear()
        ..addAll(
          medicine.times.map((m) => TimeOfDay(hour: m ~/ 60, minute: m % 60)),
        );
    }
  }

  @override
  void dispose() {
    name.dispose();
    dose.dispose();
    stock.dispose();
    unitsPerDose.dispose();
    lowStockThreshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.medicine == null ? '新增藥物' : '編輯藥物')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(
              labelText: '藥名',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v?.trim().isEmpty ?? true) ? '請輸入藥名' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: dose,
            decoration: const InputDecoration(
              labelText: '每次劑量（例如 1 顆、500 mg）',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v?.trim().isEmpty ?? true) ? '請輸入劑量' : null,
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('啟用每日提醒'),
            value: active,
            onChanged: (value) => setState(() => active = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: stock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '剩餘藥量（顆，留空則不追蹤）',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final n = int.tryParse(value.trim());
              return n == null || n < 0 ? '請輸入 0 或正整數' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: unitsPerDose,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '每次扣幾顆',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final n = int.tryParse(value?.trim() ?? '');
              return n == null || n <= 0 ? '請輸入正整數' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: lowStockThreshold,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '剩幾顆時提醒補藥',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final n = int.tryParse(value?.trim() ?? '');
              return n == null || n < 0 ? '請輸入 0 或正整數' : null;
            },
          ),
          const SizedBox(height: 20),
          Text(
            '每天 ${times.length} 次',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (var i = 0; i < times.length; i++)
            ListTile(
              title: Text('第 ${i + 1} 次'),
              subtitle: Text(times[i].format(context)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: times[i],
                );
                if (picked != null) setState(() => times[i] = picked);
              },
              trailing: times.length > 1
                  ? IconButton(
                      onPressed: () => setState(() => times.removeAt(i)),
                      icon: const Icon(Icons.remove_circle_outline),
                    )
                  : null,
            ),
          TextButton.icon(
            onPressed: times.length >= 9
                ? null
                : () => setState(
                    () => times.add(const TimeOfDay(hour: 12, minute: 0)),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('增加服藥時間'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final minutes = times.map((e) => e.hour * 60 + e.minute).toList();
              if (minutes.toSet().length != minutes.length) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('服藥時間不可重複')));
                return;
              }
              try {
                final stockCount = stock.text.trim().isEmpty
                    ? null
                    : int.parse(stock.text.trim());
                if (widget.medicine == null) {
                  await widget.store.addMedicine(
                    name.text.trim(),
                    dose.text.trim(),
                    minutes,
                    active: active,
                    stock: stockCount,
                    unitsPerDose: int.parse(unitsPerDose.text.trim()),
                    lowStockThreshold: int.parse(lowStockThreshold.text.trim()),
                  );
                } else {
                  await widget.store.updateMedicine(
                    widget.medicine!,
                    name.text.trim(),
                    dose.text.trim(),
                    minutes,
                    active: active,
                    stock: stockCount,
                    unitsPerDose: int.parse(unitsPerDose.text.trim()),
                    lowStockThreshold: int.parse(lowStockThreshold.text.trim()),
                  );
                }
              } on StateError catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.message.toString())),
                  );
                }
                return;
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('儲存藥物'),
          ),
        ],
      ),
    ),
  );
}

class RecordPage extends StatelessWidget {
  const RecordPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    final sorted = [...store.records]..sort((a, b) => b.at.compareTo(a.at));
    return Scaffold(
      appBar: AppBar(title: const Text('服藥紀錄')),
      body: sorted.isEmpty
          ? const EmptyState(Icons.history, '尚無服藥紀錄')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final r in sorted)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        r.status == '已服用'
                            ? Icons.check_circle
                            : Icons.remove_circle,
                        color: r.status == '已服用' ? Colors.green : Colors.orange,
                      ),
                      title: Text(r.name),
                      subtitle: Text(
                        '${r.day} 預定 ${clockTime(r.time)}・${r.dose}${r.actualAt == null ? '' : '\n實際 ${clockTime(r.actualAt!.hour * 60 + r.actualAt!.minute)}'}',
                      ),
                      isThreeLine: r.actualAt != null,
                      trailing: Text(r.status),
                    ),
                  ),
              ],
            ),
    );
  }
}

class HealthPage extends StatelessWidget {
  const HealthPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    final sorted = [...store.health]..sort((a, b) => b.at.compareTo(a.at));
    return Scaffold(
      appBar: AppBar(title: const Text('健康紀錄')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => add(context),
        icon: const Icon(Icons.add),
        label: const Text('新增紀錄'),
      ),
      body: sorted.isEmpty
          ? const EmptyState(Icons.favorite_outline, '可記錄血壓、體重或血糖')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final r in sorted)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.favorite,
                        color: Colors.redAccent,
                      ),
                      title: Text('${r.type}　${r.value}'),
                      subtitle: Text(
                        '${dayKey(r.at)} ${clockTime(r.at.hour * 60 + r.at.minute)}',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> add(BuildContext context) async {
    var type = '血壓';
    final value = TextEditingController();
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('新增健康紀錄'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const ['血壓', '體重', '血糖']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => refresh(() => type = v!),
                  decoration: const InputDecoration(labelText: '項目'),
                ),
                TextFormField(
                  controller: value,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: type == '血壓'
                        ? '收縮壓/舒張壓（mmHg）'
                        : type == '體重'
                        ? '公斤（kg）'
                        : 'mg/dL',
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (type == '血壓') {
                      final parts = text.split('/');
                      return parts.length == 2 &&
                              parts.every(
                                (e) => double.tryParse(e.trim()) != null,
                              )
                          ? null
                          : '請輸入例如 120/80';
                    }
                    return double.tryParse(text) != null ? null : '請輸入數字';
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                await store.addHealth(type, value.text.trim());
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    value.dispose();
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.store});
  final AppStore store;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final name = TextEditingController(text: widget.store.name);
  DateTime? birthday;
  bool reminders = true;
  @override
  void initState() {
    super.initState();
    birthday = widget.store.birthday;
    reminders = widget.store.reminders;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('個人資料')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(
          child: CircleAvatar(radius: 42, child: Icon(Icons.person, size: 44)),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: '姓名',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('生日'),
          subtitle: Text(birthday == null ? '尚未設定' : dayKey(birthday!)),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: birthday ?? DateTime(1990),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => birthday = picked);
          },
        ),
        SwitchListTile(
          title: const Text('服藥提醒'),
          subtitle: Text(
            widget.store.notificationPermission
                ? '按設定時間發送通知'
                : '請在 iPhone 設定中允許通知',
          ),
          value: reminders,
          onChanged: (v) => setState(() => reminders = v),
        ),
        if (!widget.store.notificationPermission && !kIsWeb && Platform.isIOS)
          TextButton.icon(
            onPressed: () =>
                widget.store.notifications.openAppNotificationSettings(),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('開啟 iPhone 通知設定'),
          ),
        if (widget.store.notificationError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.store.notificationError!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await widget.store.saveProfile(
              name.text.trim(),
              birthday,
              reminders,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('設定已儲存')));
            }
          },
          child: const Text('儲存設定'),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.teal),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
