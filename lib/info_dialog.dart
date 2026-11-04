import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json5/json5.dart';
import 'package:url_launcher/url_launcher.dart';

/// Элемент инструкции с заголовком и текстом.
class ManualItem {
  final String title;
  final String text;

  const ManualItem({
    required this.title,
    required this.text,
  });

  factory ManualItem.fromJson(Map<String, dynamic> json) {
    return ManualItem(
      title: json['title'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

/// Содержимое окна «О приложении», загружаемое из assets/info.json.
class AppInfo {
  final String title;
  final List<String> credits;
  final String manualTitle;
  final List<ManualItem> manual;

  const AppInfo({
    required this.title,
    required this.credits,
    required this.manualTitle,
    required this.manual,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
    List<ManualItem> manualItems() =>
        (json['manual'] as List<dynamic>? ?? const [])
            .map((e) => ManualItem.fromJson(e as Map<String, dynamic>))
            .toList();
    return AppInfo(
      title: json['title'] as String? ?? 'О приложении',
      credits: strings('credits'),
      manualTitle: json['manualTitle'] as String? ?? '',
      manual: manualItems(),
    );
  }

  static Future<AppInfo> load({String asset = 'assets/info.json5'}) async {
    final raw = await rootBundle.loadString(asset);
    return AppInfo.fromJson(json5Decode(raw) as Map<String, dynamic>);
  }
}

/// Кнопка «i» (жирный курсив) для leading в AppBar.
class InfoButton extends StatelessWidget {
  final Color color;

  const InfoButton({super.key, this.color = const Color(0x99FFFFFF)});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: 'О приложении',
      onPressed: () => showInfoDialog(context),
      icon: Text(
        'i',
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
          fontFamily: 'serif',
          height: 1,
        ),
      ),
    );
  }
}

Future<void> showInfoDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const InfoDialog(),
  );
}

class InfoDialog extends StatelessWidget {
  const InfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenWidth,
        ),
        child: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: FutureBuilder<AppInfo>(
                    future: AppInfo.load(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child:
                              Text('Не удалось загрузить info.json:\n${snapshot.error}'),
                        );
                      }
                      final info = snapshot.data;
                      if (info == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _InfoText(info: info);
                    },
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoText extends StatefulWidget {
  final AppInfo info;

  const _InfoText({required this.info});

  @override
  State<_InfoText> createState() => _InfoTextState();
}

class _InfoTextState extends State<_InfoText> {
  // Общий контроллер: иначе полоса прокрутки не связана с содержимым
  // и перетаскивание её ползунка ничего не двигает
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildClickableText(String text, TextStyle? style) {
    final url = Uri.tryParse(text);
    final isUrl = url != null && (url.hasScheme && (url.scheme == 'http' || url.scheme == 'https'));

    if (isUrl) {
      return InkWell(
        onTap: () async {
          final uri = Uri.parse(text);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
        child: Text(
          text,
          style: style?.copyWith(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    }

    return Text(
      text,
      style: style,
      textAlign: TextAlign.justify,
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context).textTheme;
    // Текст выделяемый (долгое нажатие / мышь), с системным меню
    // «Копировать»/«Выделить всё». Перетаскивание мышью выделяет, а не
    // прокручивает — прокрутка колесом, пальцем и ползунком.
    return SelectionArea(
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.title,
                style: theme.titleLarge?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              for (final line in info.credits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line, style: theme.bodyMedium?.copyWith(fontSize: 12)),
                ),
              const SizedBox(height: 16),
              Text(info.manualTitle, style: theme.titleMedium?.copyWith(fontSize: 12)),
              const SizedBox(height: 8),
              for (final item in info.manual)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          item.title,
                          style: theme.bodyMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildClickableText(
                        item.text,
                        theme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
