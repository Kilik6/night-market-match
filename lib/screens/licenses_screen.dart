import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/night_scaffold.dart';

/// 開源授權：列出 App 用到的開源套件（Flutter 打包時自動收集的授權聲明），點進去看全文。
/// MIT、BSD、Apache 等授權都要求附上原作者的版權聲明。
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  /// 套件名稱 → 授權全文（一個套件可能有好幾份）。
  late final Future<Map<String, List<String>>> _licenses = _load();

  static Future<Map<String, List<String>>> _load() async {
    final result = <String, List<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs
          .map((p) => p.indent == LicenseParagraph.centeredIndent ? p.text : '${'  ' * p.indent}${p.text}')
          .join('\n\n');
      for (final package in entry.packages) {
        result.putIfAbsent(package, () => []).add(text);
      }
    }
    final names = result.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final n in names) n: result[n]!};
  }

  @override
  Widget build(BuildContext context) {
    return NightScaffold(
      title: '開源授權',
      child: FutureBuilder<Map<String, List<String>>>(
        future: _licenses,
        builder: (context, snapshot) {
          final licenses = snapshot.data;
          if (licenses == null) {
            return const Center(child: CircularProgressIndicator(color: NightColors.glow));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  '夜市翻牌使用了以下開源軟體，感謝這些作者。點選套件可以看授權全文。',
                  style: TextStyle(color: NightColors.mist, fontSize: 14, height: 1.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(color: NightColors.stall, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    for (final MapEntry(key: name, value: texts) in licenses.entries)
                      ListTile(
                        key: ValueKey('license_$name'),
                        title: Text(name, style: const TextStyle(color: NightColors.paper, fontSize: 15)),
                        subtitle: Text('${texts.length} 份授權',
                            style: const TextStyle(color: NightColors.mist, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: NightColors.mist),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => _LicenseDetail(name: name, texts: texts),
                        )),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 單一套件的授權全文。
class _LicenseDetail extends StatelessWidget {
  const _LicenseDetail({required this.name, required this.texts});

  final String name;
  final List<String> texts;

  @override
  Widget build(BuildContext context) {
    return NightScaffold(
      title: name,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: texts.length,
        separatorBuilder: (_, __) => const Divider(color: NightColors.mist, height: 32),
        itemBuilder: (context, i) => SelectableText(
          texts[i],
          style: const TextStyle(color: NightColors.paper, fontSize: 12, height: 1.45),
        ),
      ),
    );
  }
}
