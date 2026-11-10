import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../main.dart';
import '../models/dose_history.dart';
import '../models/medicine.dart';
import '../theme/renewal_theme.dart';
import '../widgets/pill_glyph.dart';
import '../widgets/renewal_page.dart';
import 'home_screen.dart' show homeClockLabel, homePeriodLabel;

/// 지난 기록 — 어제부터 거꾸로 날짜별로 먹은 약을 본다. 읽기 전용이다.
/// (T-261110-039)
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, this.clock});

  /// 화면의 오늘 시각. 비우면 [DateTime.now].
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final today = (clock ?? DateTime.now)();
    final history = buildDoseHistory(
      Hive.box<Medicine>(medicineBoxName).values,
      today,
    );
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    return RenewalPage(
      title: '지난 기록',
      subtitle: '최근 $doseHistoryDays일 동안 먹은 약을 볼 수 있어요',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        const SizedBox(height: 12),
        if (history.isEmpty)
          const _EmptyHistory()
        else ...[
          for (final day in history) ...[
            _DayCard(day: day, isYesterday: day.date == yesterday),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              '기록은 최근 $doseHistoryDays일까지 남아요. 약 시간이나 요일을 바꾸면 '
              '지난 날의 "기록 없음" 표시가 달라질 수 있어요.',
              style: renewalStyle(
                13,
                FontWeight.w500,
                RenewalColors.faint,
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _dateLabel(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 ${weekdays[date.weekday - 1]}요일';
}

String _dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.isYesterday});

  final HistoryDay day;
  final bool isYesterday;

  @override
  Widget build(BuildContext context) {
    final allTaken = day.takenCount == day.total;
    final label = _dateLabel(day.date);
    return DecoratedBox(
      key: Key('history-day-${_dayKey(day.date)}'),
      decoration: renewalCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 한 줄에 안 들어가면(큰 글씨·좁은 화면) 개수가 다음 줄로 내려간다.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  isYesterday ? '어제 · $label' : label,
                  style: renewalStyle(16, FontWeight.w800, RenewalColors.ink),
                ),
                Text(
                  '${day.takenCount}/${day.total} 먹었어요',
                  style: renewalStyle(
                    14,
                    FontWeight.w700,
                    allTaken ? RenewalColors.greenDeep : RenewalColors.body,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (i, dose) in day.doses.indexed) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: RenewalColors.line,
                ),
              _DoseRow(dose: dose),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});

  final HistoryDose dose;

  @override
  Widget build(BuildContext context) {
    final look = lookForMedicineName(dose.name);
    final when =
        '${homePeriodLabel(dose.hour)} ${homeClockLabel(dose.hour, dose.minute)}';
    final detail = dose.dosage.isEmpty ? when : '$when · ${dose.dosage}';
    final status = dose.taken ? '먹었어요' : '기록 없음';
    return Semantics(
      container: true,
      label: [
        when,
        dose.name,
        if (dose.dosage.isNotEmpty) dose.dosage,
        status,
      ].join(' '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: look.soft,
                  shape: BoxShape.circle,
                ),
                child: Opacity(
                  opacity: dose.taken ? 1 : 0.55,
                  child: PillGlyph(look: look, size: 23),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dose.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: renewalStyle(
                        15,
                        FontWeight.w700,
                        RenewalColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: renewalStyle(
                        13,
                        FontWeight.w400,
                        RenewalColors.faint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (dose.taken) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: RenewalColors.green,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                status,
                style: renewalStyle(
                  13,
                  FontWeight.w700,
                  dose.taken ? RenewalColors.greenDeep : RenewalColors.hush,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: renewalCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: RenewalColors.green50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 28,
                color: RenewalColors.greenDeep,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '아직 지난 기록이 없어요',
              textAlign: TextAlign.center,
              style: renewalStyle(17, FontWeight.w800, RenewalColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '약을 먹고 "먹었어요"를 누르면\n다음 날부터 여기에 쌓여요',
              textAlign: TextAlign.center,
              style: renewalStyle(
                14,
                FontWeight.w500,
                RenewalColors.faint,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
