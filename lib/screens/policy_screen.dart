import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/renewal_theme.dart';
import '../widgets/renewal_page.dart';

/// 약관·개인정보처리방침 등 법적 문서를 asset(.md)에서 읽어 렌더한다.
/// 간단한 마크다운(제목/불릿/문단)만 처리. (T-260614-12)
class PolicyScreen extends StatelessWidget {
  final String title;
  final String assetPath;
  const PolicyScreen({super.key, required this.title, required this.assetPath});

  String get _subtitle {
    if (title.contains('개인정보')) return '어떤 정보를 다루는지 적혀 있어요';
    return '앱을 쓰는 조건이 적혀 있어요';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(assetPath),
      builder: (context, snapshot) {
        final children = <Widget>[];
        if (!snapshot.hasData) {
          children.add(
            const SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(color: RenewalColors.green),
              ),
            ),
          );
        } else {
          final lines = snapshot.data!.split('\n');
          children.add(
            DecoratedBox(
              decoration: renewalCardDecoration(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final raw in lines) _line(raw)],
                ),
              ),
            ),
          );
        }
        return RenewalPage(
          title: title,
          subtitle: _subtitle,
          onBack: () => Navigator.maybePop(context),
          children: children,
        );
      },
    );
  }

  Widget _line(String raw) {
    final line = raw.trimRight();
    String clean(String s) => s.replaceAll('**', '').replaceAll('`', '').trim();

    if (line.trim().isEmpty) return const SizedBox(height: 10);
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          clean(line.substring(4)),
          style: renewalStyle(
            15,
            FontWeight.w700,
            RenewalColors.ink,
            height: 1.45,
          ),
        ),
      );
    }
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          clean(line.substring(3)),
          style: renewalStyle(
            18,
            FontWeight.w800,
            RenewalColors.ink,
            height: 1.35,
          ),
        ),
      );
    }
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          clean(line.substring(2)),
          style: renewalStyle(
            22,
            FontWeight.w800,
            RenewalColors.ink,
            height: 1.3,
          ),
        ),
      );
    }
    if (line.startsWith('- ') || line.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          '•  ${clean(line.substring(2))}',
          style: renewalStyle(
            15,
            FontWeight.w500,
            RenewalColors.body,
            height: 1.55,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        clean(line),
        style: renewalStyle(
          15,
          FontWeight.w500,
          RenewalColors.body,
          height: 1.55,
        ),
      ),
    );
  }
}
