import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'web_preferences_stub.dart'
    if (dart.library.js_interop) 'web_preferences_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) registerWebPreferences();
  runApp(const HealthTrackApp());
}

const teal = Color(0xff14766f);
const canvas = Color(0xfff5f8f7);

String dateText(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class Profile {
  Profile({
    this.name = '',
    this.age,
    this.gender = '',
    this.height,
    this.weight,
  });
  String name;
  int? age;
  String gender;
  double? height;
  double? weight;
  bool get complete =>
      name.trim().isNotEmpty && age != null && gender.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'gender': gender,
    'height': height,
    'weight': weight,
  };
  factory Profile.fromJson(Map<String, dynamic> x) => Profile(
    name: x['name'] as String? ?? '',
    age: x['age'] as int?,
    gender: x['gender'] as String? ?? '',
    height: (x['height'] as num?)?.toDouble(),
    weight: (x['weight'] as num?)?.toDouble(),
  );
}

class HealthEntry {
  HealthEntry({
    required this.id,
    required this.at,
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.weight,
    this.bloodSugar,
    this.water,
    this.mood = '',
    this.note = '',
  });
  final int id;
  final DateTime at;
  final double? systolic, diastolic, heartRate, weight, bloodSugar, water;
  final String mood, note;
  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'systolic': systolic,
    'diastolic': diastolic,
    'heartRate': heartRate,
    'weight': weight,
    'bloodSugar': bloodSugar,
    'water': water,
    'mood': mood,
    'note': note,
  };
  factory HealthEntry.fromJson(Map<String, dynamic> x) => HealthEntry(
    id: x['id'] as int,
    at: DateTime.parse(x['at'] as String),
    systolic: (x['systolic'] as num?)?.toDouble(),
    diastolic: (x['diastolic'] as num?)?.toDouble(),
    heartRate: (x['heartRate'] as num?)?.toDouble(),
    weight: (x['weight'] as num?)?.toDouble(),
    bloodSugar: (x['bloodSugar'] as num?)?.toDouble(),
    water: (x['water'] as num?)?.toDouble(),
    mood: x['mood'] as String? ?? '',
    note: x['note'] as String? ?? '',
  );
}

class HealthStore extends ChangeNotifier {
  final prefs = SharedPreferencesAsync();
  Profile profile = Profile();
  final entries = <HealthEntry>[];
  bool ready = false;
  bool introSeen = false;

  Future<void> load() async {
    try {
      final p = await prefs.getString('health_profile_v2');
      if (p != null) profile = Profile.fromJson(jsonDecode(p));
      final raw = jsonDecode(
        await prefs.getString('health_entries_v2') ?? '[]',
      ) as List;
      entries.addAll(
        raw.map((e) => HealthEntry.fromJson(Map<String, dynamic>.from(e))),
      );
      introSeen = await prefs.getBool('health_intro_v2') ?? false;
    } catch (_) {}
    entries.sort((a, b) => b.at.compareTo(a.at));
    ready = true;
    notifyListeners();
  }

  Future<void> saveProfile(Profile value) async {
    profile = value;
    await prefs.setString('health_profile_v2', jsonEncode(value.toJson()));
    notifyListeners();
  }

  Future<void> saveEntry(HealthEntry value) async {
    entries.insert(0, value);
    await _saveEntries();
  }

  Future<void> deleteEntry(HealthEntry value) async {
    entries.remove(value);
    await _saveEntries();
  }

  Future<void> _saveEntries() async {
    await prefs.setString(
      'health_entries_v2',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> finishIntro() async {
    introSeen = true;
    await prefs.setBool('health_intro_v2', true);
    notifyListeners();
  }

  String summary() {
    if (entries.isEmpty) return '目前還沒有健康紀錄。';
    final e = entries.first;
    final parts = <String>['最新健康紀錄，時間是${e.at.month}月${e.at.day}日'];
    if (e.systolic != null && e.diastolic != null) {
      parts.add('血壓 ${e.systolic!.round()} 比 ${e.diastolic!.round()}');
    }
    if (e.heartRate != null) parts.add('心率每分鐘 ${e.heartRate!.round()} 下');
    if (e.weight != null) parts.add('體重 ${e.weight} 公斤');
    if (e.bloodSugar != null) parts.add('血糖 ${e.bloodSugar}');
    if (e.water != null) parts.add('喝水 ${e.water!.round()} 毫升');
    if (e.mood.isNotEmpty) parts.add('心情 ${e.mood}');
    return parts.join('。');
  }
}

class HealthTrackApp extends StatefulWidget {
  const HealthTrackApp({super.key});
  @override
  State<HealthTrackApp> createState() => _HealthTrackAppState();
}

class _HealthTrackAppState extends State<HealthTrackApp> {
  final store = HealthStore();
  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '健康追蹤小幫手',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: teal,
      scaffoldBackgroundColor: canvas,
      fontFamilyFallback: const ['Noto Sans TC'],
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        bodyLarge: TextStyle(fontSize: 20, height: 1.45),
        bodyMedium: TextStyle(fontSize: 17, height: 1.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    ),
    home: AnimatedBuilder(
      animation: store,
      builder: (_, _) {
        if (!store.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!store.introSeen) return IntroPage(store: store);
        if (!store.profile.complete) {
          return ProfileEditor(store: store, firstUse: true);
        }
        return Dashboard(store: store);
      },
    ),
  );
}

class IntroPage extends StatelessWidget {
  const IntroPage({super.key, required this.store});
  final HealthStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 32, 26, 24),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: teal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HealthTrack',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '健康追蹤小幫手',
                    style: TextStyle(fontSize: 20, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 44),
          const Icon(Icons.health_and_safety, color: teal, size: 110),
          const SizedBox(height: 30),
          Text(
            '每天一點紀錄，\n更了解自己的健康',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 20),
          const Text(
            '記錄血壓、心率、體重與血糖。身體不舒服時，也可以直接用說的，讓小幫手提供一般就醫科別導引。',
            style: TextStyle(fontSize: 21, color: Colors.black54, height: 1.55),
          ),
          const SizedBox(height: 24),
          const FeatureLine(Icons.mic, '可以直接說症狀', '例如：我今天喉嚨痛、一直咳嗽'),
          const FeatureLine(Icons.volume_up, '會用語音回答', '例如：建議先諮詢家醫科'),
          const FeatureLine(Icons.show_chart, '健康數字更清楚', '大字、大按鈕、趨勢直接比較'),
          const SizedBox(height: 22),
          BigButton(
            text: '開啟健康小幫手',
            icon: Icons.arrow_forward,
            onPressed: store.finishIntro,
          ),
          const SizedBox(height: 14),
          const Text(
            '健康資料只儲存在此裝置。科別導引不能取代醫師診斷。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class FeatureLine extends StatelessWidget {
  const FeatureLine(this.icon, this.title, this.subtitle, {super.key});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xffd9f2ed),
            child: Icon(icon, color: teal, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 17, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.store});
  final HealthStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('健康追蹤小幫手', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text(
            '今天需要什麼幫忙？',
            style: TextStyle(fontSize: 25, color: Colors.black54),
          ),
          const SizedBox(height: 26),
          ActionCard(
            icon: Icons.mic,
            color: const Color(0xffd9f2ed),
            title: '我身體不舒服',
            subtitle: '按一下，用說的告訴我哪裡不舒服',
            onTap: () => open(context, SymptomPage(store: store)),
          ),
          ActionCard(
            icon: Icons.favorite,
            color: const Color(0xffffe2e3),
            title: '我的健康',
            subtitle: '健康資料、紀錄、歷史與趨勢都在這裡',
            onTap: () => open(context, MyHealthPage(store: store)),
          ),
          ActionCard(
            icon: Icons.volume_up,
            color: const Color(0xffffedd7),
            title: '播放我的健康摘要',
            subtitle: '唸出最新的健康紀錄',
            onTap: () => speakSummary(context, store),
          ),
          const SizedBox(height: 16),
          const Text(
            '症狀推薦僅供就醫科別導引，不代表診斷；若有胸痛、呼吸困難、昏厥等緊急症狀，請立即尋求緊急醫療協助。',
            style: TextStyle(fontSize: 17, color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            CircleAvatar(
              radius: 39,
              backgroundColor: color,
              child: Icon(icon, color: teal, size: 38),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 18, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: teal, size: 36),
          ],
        ),
      ),
    ),
  );
}

class MyHealthPage extends StatelessWidget {
  const MyHealthPage({super.key, required this.store});
  final HealthStore store;
  @override
  Widget build(BuildContext context) {
    final p = store.profile;
    return AppScaffold(
      title: '我的健康',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: teal, size: 34),
                    const SizedBox(width: 10),
                    Text(
                      '我的健康資料',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${p.age} 歲　｜　${p.gender}',
                  style: const TextStyle(fontSize: 24),
                ),
                if (p.height != null)
                  Text(
                    '身高：${p.height} cm',
                    style: const TextStyle(fontSize: 22),
                  ),
                if (p.weight != null)
                  Text(
                    '初始體重：${p.weight} kg',
                    style: const TextStyle(fontSize: 22),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => open(context, ProfileEditor(store: store)),
                  icon: const Icon(Icons.edit),
                  label: const Text('修改我的資料', style: TextStyle(fontSize: 20)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ActionCard(
          icon: Icons.add,
          color: const Color(0xffd9f2ed),
          title: '新增健康紀錄',
          subtitle: '記錄血壓、心率、體重、血糖',
          onTap: () => open(context, EntryEditor(store: store)),
        ),
        ActionCard(
          icon: Icons.history,
          color: const Color(0xffe4f1fb),
          title: '歷史健康紀錄',
          subtitle: '查看以前記錄過的資料',
          onTap: () => open(context, HistoryPage(store: store)),
        ),
        ActionCard(
          icon: Icons.show_chart,
          color: const Color(0xffffedd7),
          title: '健康趨勢',
          subtitle: '用大字和圖表看數值變化',
          onTap: () => open(context, TrendPage(store: store)),
        ),
      ],
    );
  }
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.store, this.firstUse = false});
  final HealthStore store;
  final bool firstUse;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.store.profile.name);
  late final age = TextEditingController(
    text: widget.store.profile.age?.toString() ?? '',
  );
  late final height = TextEditingController(
    text: widget.store.profile.height?.toString() ?? '',
  );
  late final weight = TextEditingController(
    text: widget.store.profile.weight?.toString() ?? '',
  );
  late String gender = widget.store.profile.gender;
  @override
  void dispose() {
    name.dispose();
    age.dispose();
    height.dispose();
    weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.firstUse,
    child: AppScaffold(
      title: widget.firstUse ? '設定基本資料' : '修改基本資料',
      showBack: !widget.firstUse,
      subtitle: '資料只儲存在這台裝置，之後也可以再修改。',
      children: [
        Form(
          key: form,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '使用者基本資料',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '姓名（必填）',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '請填寫姓名' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '年齡（必填）',
                      prefixIcon: Icon(Icons.cake),
                    ),
                    validator: positiveInt,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '性別（必填）',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: ['男', '女', '其他']
                        .map(
                          (v) => ChoiceChip(
                            label: Text(
                              v,
                              style: const TextStyle(fontSize: 19),
                            ),
                            selected: gender == v,
                            onSelected: (_) => setState(() => gender = v),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '身高（選填，cm）',
                      prefixIcon: Icon(Icons.straighten),
                    ),
                    validator: optionalNumber,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '目前體重（選填，kg）',
                      prefixIcon: Icon(Icons.monitor_weight),
                    ),
                    validator: optionalNumber,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        BigButton(text: '儲存資料', icon: Icons.check_circle, onPressed: save),
      ],
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate() || gender.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請填寫姓名、年齡並選擇性別')));
      return;
    }
    await widget.store.saveProfile(
      Profile(
        name: name.text.trim(),
        age: int.parse(age.text),
        gender: gender,
        height: double.tryParse(height.text),
        weight: double.tryParse(weight.text),
      ),
    );
    if (!mounted) return;
    if (!widget.firstUse) Navigator.pop(context);
  }
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, required this.store});
  final HealthStore store;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  final fields = List.generate(7, (_) => TextEditingController());
  String mood = '';
  final note = TextEditingController();
  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    note.dispose();
    super.dispose();
  }

  double? value(int i) => double.tryParse(fields[i].text.trim());
  @override
  Widget build(BuildContext context) => AppScaffold(
    title: '新增健康紀錄',
    subtitle:
        '${widget.store.profile.age} 歲・${widget.store.profile.gender}｜不用每格都填，有量測到的資料再記錄即可。',
    children: [
      Form(
        key: form,
        child: Column(
          children: [
            SectionCard(
              icon: Icons.monitor_heart,
              color: const Color(0xffffe2e3),
              title: '血壓與心率',
              subtitle: '輸入今天量測的數值',
              children: [
                Row(
                  children: [
                    Expanded(child: numberField(0, '收縮壓', 'mmHg')),
                    const SizedBox(width: 12),
                    Expanded(child: numberField(1, '舒張壓', 'mmHg')),
                  ],
                ),
                const SizedBox(height: 14),
                numberField(2, '心率', '次／分鐘'),
              ],
            ),
            SectionCard(
              icon: Icons.spa,
              color: const Color(0xffd9f2ed),
              title: '日常健康',
              subtitle: '體重、血糖與飲水量',
              children: [
                numberField(3, '體重', 'kg'),
                const SizedBox(height: 14),
                numberField(4, '血糖', 'mg/dL'),
                const SizedBox(height: 14),
                numberField(5, '今日飲水', 'mL'),
              ],
            ),
            SectionCard(
              icon: Icons.sentiment_satisfied,
              color: const Color(0xffffedd7),
              title: '今天的感受',
              subtitle: '簡單記下心情與身體狀況',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: mood.isEmpty ? null : mood,
                  decoration: const InputDecoration(
                    labelText: '心情',
                    prefixIcon: Icon(Icons.mood),
                  ),
                  items: ['很好', '不錯', '普通', '疲累', '不舒服']
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, style: const TextStyle(fontSize: 19)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => mood = v ?? '',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: note,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '備註'),
                ),
              ],
            ),
          ],
        ),
      ),
      BigButton(text: '儲存健康紀錄', icon: Icons.check_circle, onPressed: save),
    ],
  );
  Widget numberField(int i, String label, String unit) => TextFormField(
    controller: fields[i],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, suffixText: unit),
    validator: optionalNumber,
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final values = [for (var i = 0; i < 6; i++) value(i)];
    if ((values[0] == null) != (values[1] == null)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('收縮壓和舒張壓請一起填寫')));
      return;
    }
    if (values.every((e) => e == null) &&
        mood.isEmpty &&
        note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請至少填寫一項健康資料')));
      return;
    }
    final entry = HealthEntry(
      id: DateTime.now().microsecondsSinceEpoch,
      at: DateTime.now(),
      systolic: values[0],
      diastolic: values[1],
      heartRate: values[2],
      weight: values[3],
      bloodSugar: values[4],
      water: values[5],
      mood: mood,
      note: note.text.trim(),
    );
    await widget.store.saveEntry(entry);
    if (!mounted) return;
    final alerts = healthAlerts(entry);
    if (alerts.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.info, color: Colors.deepOrange, size: 46),
          title: const Text('健康數值提醒'),
          content: Text(
            '${alerts.join('\n')}\n\n此提醒不代表疾病診斷；若身體明顯不適，請儘快就醫。',
            style: const TextStyle(fontSize: 19),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.store});
  final HealthStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (_, _) => AppScaffold(
      title: '歷史健康紀錄',
      subtitle: '共 ${store.entries.length} 筆資料',
      children: store.entries.isEmpty
          ? [
              const EmptyPanel(
                icon: Icons.history,
                title: '目前沒有紀錄',
                message: '新增健康資料後，這裡會依時間顯示每一筆紀錄。',
              ),
            ]
          : store.entries
                .map(
                  (e) => EntryCard(
                    entry: e,
                    onDelete: () => confirmDelete(context, e),
                  ),
                )
                .toList(),
    ),
  );
  Future<void> confirmDelete(BuildContext context, HealthEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除這筆紀錄？'),
        content: Text(dateText(entry.at)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (yes == true) await store.deleteEntry(entry);
  }
}

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry, required this.onDelete});
  final HealthEntry entry;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final rows = <String>[];
    if (entry.systolic != null && entry.diastolic != null) {
      rows.add(
        '血壓 ${entry.systolic!.round()}/${entry.diastolic!.round()} mmHg',
      );
    }
    if (entry.heartRate != null) {
      rows.add('心率 ${entry.heartRate!.round()} 次／分鐘');
    }
    if (entry.weight != null) rows.add('體重 ${entry.weight} kg');
    if (entry.bloodSugar != null) rows.add('血糖 ${entry.bloodSugar} mg/dL');
    if (entry.water != null) rows.add('飲水 ${entry.water!.round()} mL');
    if (entry.mood.isNotEmpty) rows.add('心情 ${entry.mood}');
    if (entry.note.isNotEmpty) rows.add('備註 ${entry.note}');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xffd9f2ed),
              child: Icon(Icons.favorite, color: teal),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateText(entry.at),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...rows.map(
                    (e) => Text(e, style: const TextStyle(fontSize: 19)),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: '刪除',
            ),
          ],
        ),
      ),
    );
  }
}

enum Metric {
  weight('體重', 'kg'),
  systolic('收縮壓', 'mmHg'),
  heartRate('心率', '次／分'),
  bloodSugar('血糖', 'mg/dL');

  const Metric(this.label, this.unit);
  final String label, unit;
}

class TrendPage extends StatefulWidget {
  const TrendPage({super.key, required this.store});
  final HealthStore store;
  @override
  State<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends State<TrendPage> {
  Metric metric = Metric.weight;
  double? getValue(HealthEntry e) => switch (metric) {
    Metric.weight => e.weight,
    Metric.systolic => e.systolic,
    Metric.heartRate => e.heartRate,
    Metric.bloodSugar => e.bloodSugar,
  };
  @override
  Widget build(BuildContext context) {
    final points = widget.store.entries
        .map(getValue)
        .whereType<double>()
        .toList()
        .reversed
        .toList();
    final latest = points.isEmpty ? null : points.last;
    final avg = points.isEmpty
        ? null
        : points.reduce((a, b) => a + b) / points.length;
    return AppScaffold(
      title: '健康趨勢',
      subtitle: '看最近的健康數值變化',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Metric.values
              .map(
                (m) => ChoiceChip(
                  label: Text(m.label, style: const TextStyle(fontSize: 18)),
                  selected: metric == m,
                  onSelected: (_) => setState(() => metric = m),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${metric.label} 變化',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const CircleAvatar(
                      backgroundColor: Color(0xffd9f2ed),
                      child: Icon(Icons.show_chart, color: teal),
                    ),
                  ],
                ),
                Text(
                  '最近 ${points.length} 筆有效資料',
                  style: const TextStyle(fontSize: 17, color: Colors.black54),
                ),
                const SizedBox(height: 22),
                if (points.length < 2)
                  const EmptyPanel(
                    icon: Icons.insert_chart_outlined,
                    title: '至少需要 2 筆資料',
                    message: '再新增一筆，就能直接比較前後變化。',
                  )
                else ...[
                  SizedBox(
                    height: 230,
                    width: double.infinity,
                    child: CustomPaint(painter: TrendPainter(points)),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      StatBox('最新', latest!, metric.unit),
                      StatBox('平均', avg!, metric.unit),
                      StatBox('最高', points.reduce(math.max), metric.unit),
                      StatBox('最低', points.reduce(math.min), metric.unit),
                      StatBox(
                        '與上一筆',
                        latest - points[points.length - 2],
                        metric.unit,
                        signed: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const InfoBox('箭頭只表示與上一筆紀錄相比是上升或下降，不代表健康狀況好或壞；趨勢資料不能取代醫療診斷。'),
      ],
    );
  }
}

class TrendPainter extends CustomPainter {
  TrendPainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce(math.min), maxV = values.reduce(math.max);
    final range = math.max(maxV - minV, 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y =
          size.height - 18 - ((values[i] - minV) / range) * (size.height - 36);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawLine(
      Offset(0, size.height - 18),
      Offset(size.width, size.height - 18),
      Paint()
        ..color = Colors.black12
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = teal
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y =
          size.height - 18 - ((values[i] - minV) / range) * (size.height - 36);
      canvas.drawCircle(Offset(x, y), 7, Paint()..color = teal);
    }
  }

  @override
  bool shouldRepaint(covariant TrendPainter oldDelegate) =>
      oldDelegate.values != values;
}

class StatBox extends StatelessWidget {
  const StatBox(
    this.label,
    this.value,
    this.unit, {
    this.signed = false,
    super.key,
  });
  final String label, unit;
  final double value;
  final bool signed;
  @override
  Widget build(BuildContext context) {
    final text = '${signed && value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';
    return Container(
      width: 145,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffedf7f5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
          Text(
            text,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          Text(unit),
        ],
      ),
    );
  }
}

class SymptomPage extends StatefulWidget {
  const SymptomPage({super.key, required this.store});
  final HealthStore store;
  @override
  State<SymptomPage> createState() => _SymptomPageState();
}

class _SymptomPageState extends State<SymptomPage> {
  final speech = stt.SpeechToText();
  final tts = FlutterTts();
  final text = TextEditingController();
  bool listening = false;
  String? department;
  String? reason;
  @override
  void dispose() {
    speech.stop();
    tts.stop();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: '我身體不舒服',
    subtitle: '用說的或打字，告訴我哪裡不舒服',
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Icon(
                listening ? Icons.graphic_eq : Icons.mic,
                color: teal,
                size: 78,
              ),
              const SizedBox(height: 12),
              Text(
                listening ? '正在聽你說…' : '按下麥克風開始說',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: text,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(fontSize: 21),
                decoration: const InputDecoration(hintText: '例如：我今天喉嚨痛、一直咳嗽'),
              ),
              const SizedBox(height: 18),
              BigButton(
                text: listening ? '停止錄音' : '開始語音輸入',
                icon: listening ? Icons.stop : Icons.mic,
                onPressed: toggleSpeech,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: analyze,
        icon: const Icon(Icons.search),
        label: const Text('分析症狀並提供科別', style: TextStyle(fontSize: 20)),
      ),
      if (department != null)
        Card(
          color: const Color(0xffd9f2ed),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '建議就醫科別',
                  style: TextStyle(
                    fontSize: 18,
                    color: teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  department!,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(reason!, style: const TextStyle(fontSize: 19)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () =>
                      speak('依照你描述的症狀，建議先諮詢$department。這只是一般科別導引，不能取代醫師診斷。'),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('播放語音建議'),
                ),
              ],
            ),
          ),
        ),
      const InfoBox(
        '此功能只提供一般就醫科別導引，不代表診斷。若有胸痛、呼吸困難、意識不清、單側無力或大量出血，請立即聯絡當地緊急醫療服務。',
      ),
    ],
  );
  Future<void> toggleSpeech() async {
    if (listening) {
      await speech.stop();
      setState(() => listening = false);
      return;
    }
    final available = await speech.initialize(
      onStatus: (s) {
        if (s == 'done' && mounted) setState(() => listening = false);
      },
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法使用語音辨識，請確認麥克風權限或直接打字。')),
        );
      }
      return;
    }
    setState(() => listening = true);
    await speech.listen(
      onResult: (r) => setState(() => text.text = r.recognizedWords),
      listenOptions: stt.SpeechListenOptions(localeId: 'zh_TW'),
    );
  }

  void analyze() {
    if (text.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請先說出或輸入症狀')));
      return;
    }
    final result = guideDepartment(text.text);
    setState(() {
      department = result.$1;
      reason = result.$2;
    });
    speak('依照你描述的症狀，建議先諮詢$department。');
  }

  Future<void> speak(String value) async {
    await tts.setLanguage('zh-TW');
    await tts.setSpeechRate(0.42);
    await tts.speak(value);
  }
}

(String, String) guideDepartment(String input) {
  final s = input.toLowerCase();
  if (['胸痛', '呼吸困難', '昏倒', '意識不清', '大量出血', '單側無力'].any(s.contains)) {
    return ('立即尋求緊急醫療協助', '這些症狀可能需要緊急處理，請不要等待一般門診。');
  }
  if (['喉嚨', '鼻塞', '流鼻水', '耳朵', '耳痛', '聲音沙啞'].any(s.contains)) {
    return ('耳鼻喉科', '描述中包含耳、鼻或喉嚨相關症狀。');
  }
  if (['皮膚', '紅疹', '發癢', '痘痘', '掉髮'].any(s.contains)) {
    return ('皮膚科', '描述中包含皮膚或毛髮相關症狀。');
  }
  if (['牙痛', '牙齒', '牙齦', '口腔'].any(s.contains)) {
    return ('牙科', '描述中包含牙齒、牙齦或口腔相關症狀。');
  }
  if (['眼睛', '眼痛', '視力', '紅眼'].any(s.contains)) {
    return ('眼科', '描述中包含眼睛或視力相關症狀。');
  }
  if (['骨頭', '關節', '扭傷', '腰痛', '膝蓋', '肩膀'].any(s.contains)) {
    return ('骨科', '描述中包含骨骼、關節或運動傷害相關症狀。');
  }
  if (['肚子', '腹痛', '胃痛', '拉肚子', '便秘', '嘔吐'].any(s.contains)) {
    return ('腸胃內科', '描述中包含腸胃道相關症狀。');
  }
  if (['頭痛', '頭暈', '手麻', '腳麻'].any(s.contains)) {
    return ('神經內科', '描述中包含頭痛、暈眩或神經相關症狀。');
  }
  return ('家醫科', '目前描述較廣泛，可先由家醫科進行初步評估與轉介。');
}

List<String> healthAlerts(HealthEntry e) {
  final result = <String>[];
  if (e.systolic != null && e.diastolic != null) {
    if (e.systolic! >= 180 || e.diastolic! >= 120) {
      result.add('血壓數值明顯偏高；若同時不舒服，請儘速尋求醫療協助。');
    } else if (e.systolic! >= 140 || e.diastolic! >= 90) {
      result.add('這次血壓偏高，建議休息後再量一次並持續留意。');
    } else if (e.systolic! < 90 || e.diastolic! < 60) {
      result.add('這次血壓偏低；若有暈眩或虛弱，請尋求醫療建議。');
    }
  }
  if (e.heartRate != null && (e.heartRate! < 50 || e.heartRate! > 120)) {
    result.add('這次心率需要留意；若有胸悶、暈眩或不適，請尋求醫療建議。');
  }
  return result;
}

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.showBack = true,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBack)
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back, size: 38),
                ),
              if (showBack) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          ...children,
        ],
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color,
                child: Icon(icon, color: teal, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
    child: Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: const Color(0xffd9f2ed),
          child: Icon(icon, color: teal, size: 42),
        ),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, fontSize: 18),
        ),
      ],
    ),
  );
}

class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xffe6f1fa),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info, color: teal, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 17, color: Color(0xff315a57)),
          ),
        ),
      ],
    ),
  );
}

class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onPressed,
  });
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 68,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 30),
      label: Text(
        text,
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: teal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
  );
}

String? positiveInt(String? value) {
  final n = int.tryParse(value?.trim() ?? '');
  return n == null || n <= 0 || n > 120 ? '請輸入正確數字' : null;
}

String? optionalNumber(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final n = double.tryParse(value.trim());
  return n == null || n < 0 ? '請輸入正確數字' : null;
}

void open(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
Future<void> speakSummary(BuildContext context, HealthStore store) async {
  final tts = FlutterTts();
  await tts.setLanguage('zh-TW');
  await tts.setSpeechRate(0.42);
  await tts.speak(store.summary());
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(store.summary())));
  }
}
