import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../theme/renewal_theme.dart';
import '../widgets/pill_glyph.dart';
import '../widgets/renewal_check.dart';
import 'medicine_edit_screen.dart';

String takenButtonSemanticsLabel({
  required String prefix,
  required bool taken,
}) {
  return taken ? '$prefix 복용 완료 취소' : '$prefix 복용 완료로 표시';
}

/// 아직 안 먹은 칸 중 지금과 시간 차이가 가장 작은 칸.
/// 차이가 같으면 더 이른 시간을 고른다. 없으면 null.
int? pickNextDoseIndex(
  List<({int minuteOfDay, bool taken})> doses,
  int nowMinute,
) {
  int? best;
  var bestGap = 1 << 30;
  for (var i = 0; i < doses.length; i++) {
    if (doses[i].taken) continue;
    final gap = (doses[i].minuteOfDay - nowMinute).abs();
    final earlierTie =
        best != null &&
        gap == bestGap &&
        doses[i].minuteOfDay < doses[best].minuteOfDay;
    if (best == null || gap < bestGap || earlierTie) {
      best = i;
      bestGap = gap;
    }
  }
  return best;
}

/// 큰 카드의 남은 시간. 시각이 지났으면 "지금".
String doseRemainText(int doseMinute, int nowMinute) {
  final remain = doseMinute - nowMinute;
  if (remain <= 0) return '지금';
  final hours = remain ~/ 60;
  final minutes = remain % 60;
  if (hours == 0) return '$minutes분 남음';
  if (minutes == 0) return '$hours시간 남음';
  return '$hours시간 $minutes분 남음';
}

/// 메인 시간대. 새벽 · 아침 · 오후 · 저녁.
String homePeriodLabel(int hour) {
  if (hour < 6) return '새벽';
  if (hour < 12) return '아침';
  if (hour < 18) return '오후';
  return '저녁';
}

/// 12시간제 "8:00" · "9:30".
String homeClockLabel(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')}';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.clock});

  /// 화면의 오늘 시각. 비우면 [DateTime.now].
  /// 복용 기록 키는 [Medicine.isTaken] 이 실제 오늘로 만든다.
  /// 시험용 시계도 그 오늘 날짜를 쓴다.
  final DateTime Function()? clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 약 저장이 바뀔 때뿐 아니라 시간이 흐를 때도 다시 그린다. (T-261110-020)
/// - 앱이 다시 앞으로 올 때: 밤에 닫고 아침에 열면 어제 화면이 남던 문제.
/// - 켜 둔 동안 분이 바뀔 때: 남은 시간 · 「지금」 · 자정 날짜 넘김.
class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _minuteTick;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _refreshNow,
      onPause: () => _minuteTick?.cancel(),
    );
    _armMinuteTick();
  }

  @override
  void dispose() {
    _minuteTick?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _refreshNow() {
    if (!mounted) return;
    setState(() {});
    _armMinuteTick();
  }

  /// 다음 분이 시작된 직후에 한 번 다시 그리고, 그 뒤 다시 건다.
  void _armMinuteTick() {
    _minuteTick?.cancel();
    final now = _now();
    final untilNextMinute = Duration(
      milliseconds: 60000 - (now.second * 1000 + now.millisecond) + 50,
    );
    _minuteTick = Timer(untilNextMinute, _refreshNow);
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Medicine>(medicineBoxName);
    return Scaffold(
      backgroundColor: RenewalColors.page,
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 500,
            child: _MintHead(),
          ),
          ValueListenableBuilder<Box<Medicine>>(
            valueListenable: box.listenable(),
            builder: (context, box, _) {
              final now = _now();
              final entries = _todayEntries(box, now);
              final nowMinute = now.hour * 60 + now.minute;
              final nextIndex = pickNextDoseIndex([
                for (final entry in entries)
                  (minuteOfDay: entry.minuteOfDay, taken: entry.taken),
              ], nowMinute);
              final next = nextIndex == null ? null : entries[nextIndex];
              final rest = [
                for (var i = 0; i < entries.length; i++)
                  if (i != nextIndex) entries[i],
              ];
              final takenCount = entries.where((entry) => entry.taken).length;
              return ListView(
                physics: entries.isEmpty
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 12,
                  20,
                  28,
                ),
                children: [
                  _Head(
                    dateLabel: _dateLabel(now),
                    taken: takenCount,
                    total: entries.length,
                  ),
                  const SizedBox(height: 22),
                  if (entries.isEmpty)
                    const _EmptyState()
                  else if (next == null)
                    const _AllDoneCard()
                  else
                    _NowCard(entry: next, nowMinute: nowMinute),
                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    _RestHeader(count: rest.length),
                    const SizedBox(height: 12),
                    _RestList(entries: rest),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime now) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일';
  }

  List<_Entry> _todayEntries(Box<Medicine> box, DateTime now) {
    final today = now.weekday;
    final list = <_Entry>[];
    for (final medicine in box.values) {
      if (medicine.deletedAt != null) continue;
      if (!medicine.isOnWeekday(today)) continue;
      for (final time in medicine.times) {
        list.add(_Entry(medicine: medicine, time: time));
      }
    }
    list.sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    return list;
  }
}

class _Entry {
  _Entry({required this.medicine, required this.time});

  final Medicine medicine;
  final DoseTime time;

  int get minuteOfDay => time.hour * 60 + time.minute;
  bool get taken => medicine.isTaken(time);

  String get when =>
      '${homePeriodLabel(time.hour)} ${homeClockLabel(time.hour, time.minute)}';
}

class _MintHead extends StatelessWidget {
  const _MintHead();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                RenewalColors.mintTop,
                RenewalColors.mintMid,
                RenewalColors.page,
              ],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          top: -140,
          right: -110,
          child: _Blob(size: 360, color: RenewalColors.blobRight),
        ),
        Positioned(
          top: 70,
          left: -150,
          child: _Blob(size: 320, color: RenewalColors.blobLeft),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({
    required this.dateLabel,
    required this.taken,
    required this.total,
  });

  final String dateLabel;
  final int taken;
  final int total;

  @override
  Widget build(BuildContext context) {
    final title = total == 0 ? '아직 등록된 약이 없어요' : '오늘 $taken/$total 먹었어요';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: renewalStyle(14, FontWeight.w600, RenewalColors.date),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: renewalStyle(24, FontWeight.w800, RenewalColors.ink),
                ),
              ],
            ),
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 12),
              child: _ProgressBars(taken: taken, total: total),
            ),
        ],
      ),
    );
  }
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.taken, required this.total});

  final int taken;
  final int total;

  @override
  Widget build(BuildContext context) {
    final natural = 22.0 * total + 4.0 * (total - 1);
    if (natural <= 120) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < total; i++) _bar(i, width: 22)],
      );
    }
    return SizedBox(
      width: 120,
      child: Row(
        children: [for (var i = 0; i < total; i++) Expanded(child: _bar(i))],
      ),
    );
  }

  Widget _bar(int index, {double? width}) {
    return Container(
      width: width,
      height: 8,
      margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
      decoration: BoxDecoration(
        color: index < taken
            ? RenewalColors.green
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.entry, required this.nowMinute});

  final _Entry entry;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    final medicine = entry.medicine;
    final look = lookForMedicineName(medicine.name);
    final remain = doseRemainText(entry.minuteOfDay, nowMinute);
    return DecoratedBox(
      decoration: renewalCardDecoration(
        radius: RenewalRadius.nowCard,
        shadows: renewalNowShadows,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RenewalRadius.nowCard),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => _open(context),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                          decoration: BoxDecoration(
                            color: RenewalColors.green50,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: RenewalColors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '다음 약',
                                style: renewalStyle(
                                  13,
                                  FontWeight.w700,
                                  RenewalColors.greenDeep,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: RenewalColors.greenDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          remain,
                          style: renewalStyle(
                            15,
                            FontWeight.w800,
                            RenewalColors.greenDeep,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.when,
                                style: renewalStyle(
                                  16,
                                  FontWeight.w600,
                                  RenewalColors.body,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                medicine.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: renewalStyle(
                                  40,
                                  FontWeight.w800,
                                  RenewalColors.ink,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (medicine.dosage.isNotEmpty) ...[
                                    _Tag(text: medicine.dosage),
                                    const SizedBox(width: 6),
                                  ],
                                  _Tag(text: medicine.weekdayLabel),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 122,
                          height: 122,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                look.soft,
                                Color.lerp(look.soft, look.cap, 0.6)!,
                              ],
                            ),
                          ),
                          child: PillGlyph(look: look, size: 86, shadow: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _TakeButton(
                label: takenButtonSemanticsLabel(
                  prefix: '${medicine.name} ${entry.time.format()}',
                  taken: false,
                ),
                onTap: () => medicine.toggleTaken(entry.time),
              ),
              // 알림 안내는 복용 시각 전에만 보인다. 시각이 지나면 「지금」 카드에 미래형 문구가 남지 않게 한다.
              if (entry.minuteOfDay > nowMinute) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      size: 16,
                      color: RenewalColors.faint,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${entry.when}에 알림을 보내드릴게요',
                        textAlign: TextAlign.center,
                        style: renewalStyle(
                          13,
                          FontWeight.w600,
                          RenewalColors.faint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MedicineEditScreen(medicine: entry.medicine),
      ),
    );
  }
}

class _TakeButton extends StatelessWidget {
  const _TakeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const Key('home-take-button'),
          onTap: onTap,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RenewalRadius.button),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF30D46D), Color(0xFF1FBA56)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D22C55E),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_rounded, size: 24, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  '먹었어요',
                  style: renewalStyle(18, FontWeight.w700, Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: RenewalColors.fill,
        borderRadius: BorderRadius.circular(RenewalRadius.tag),
      ),
      child: Text(
        text,
        style: renewalStyle(13, FontWeight.w600, RenewalColors.body),
      ),
    );
  }
}

class _RestHeader extends StatelessWidget {
  const _RestHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            '오늘 나머지',
            style: renewalStyle(18, FontWeight.w800, RenewalColors.ink),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: renewalStyle(16, FontWeight.w700, RenewalColors.hush),
          ),
        ],
      ),
    );
  }
}

class _RestList extends StatelessWidget {
  const _RestList({required this.entries});

  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: renewalCardDecoration(),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RenewalRadius.restCard),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (i, entry) in entries.indexed) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 72,
                  endIndent: 18,
                  color: RenewalColors.line,
                ),
              _RestRow(entry: entry),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestRow extends StatelessWidget {
  const _RestRow({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final taken = entry.taken;
    final medicine = entry.medicine;
    final look = lookForMedicineName(medicine.name);
    final detail = medicine.dosage.isEmpty
        ? entry.when
        : '${entry.when} · ${medicine.dosage}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MedicineEditScreen(medicine: medicine),
                  ),
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: look.soft,
                      shape: BoxShape.circle,
                    ),
                    child: Opacity(
                      opacity: taken ? 0.55 : 1,
                      child: PillGlyph(look: look, size: 27),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          medicine.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: renewalStyle(
                            16,
                            FontWeight.w700,
                            taken ? RenewalColors.faint : RenewalColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: detail),
                              if (taken)
                                TextSpan(
                                  text: '  먹었어요',
                                  style: renewalStyle(
                                    13,
                                    FontWeight.w700,
                                    RenewalColors.greenDeep,
                                  ),
                                ),
                            ],
                          ),
                          style: renewalStyle(
                            13,
                            FontWeight.w400,
                            RenewalColors.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            selected: taken,
            label: takenButtonSemanticsLabel(
              prefix: '${medicine.name} ${entry.time.format()}',
              taken: taken,
            ),
            onTap: () => medicine.toggleTaken(entry.time),
            child: ExcludeSemantics(
              child: RenewalCheck(
                taken: taken,
                size: 32,
                onTap: () => medicine.toggleTaken(entry.time),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllDoneCard extends StatelessWidget {
  const _AllDoneCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('home-all-done'),
      decoration: renewalCardDecoration(
        radius: RenewalRadius.nowCard,
        shadows: renewalNowShadows,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: RenewalColors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '오늘 약을 다 먹었어요',
              textAlign: TextAlign.center,
              style: renewalStyle(22, FontWeight.w800, RenewalColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('home-empty'),
      decoration: renewalCardDecoration(
        radius: RenewalRadius.nowCard,
        shadows: renewalNowShadows,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
        child: Column(
          children: [
            Container(
              width: 122,
              height: 122,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    PillLook.mascot.soft,
                    Color.lerp(PillLook.mascot.soft, PillLook.mascot.cap, 0.6)!,
                  ],
                ),
              ),
              child: const PillGlyph(
                look: PillLook.mascot,
                size: 86,
                face: true,
                shadow: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '아래 + 약등록을 눌러\n약을 추가해 보세요',
              textAlign: TextAlign.center,
              style: renewalStyle(
                16,
                FontWeight.w600,
                RenewalColors.body,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
