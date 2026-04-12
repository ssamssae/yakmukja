import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/medicine.dart';
import 'medicine_edit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    // 매초 리빌드하여 카운트다운 갱신
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Medicine>(medicineBoxName);
    final theme = Theme.of(context);

    return Scaffold(
      body: ValueListenableBuilder<Box<Medicine>>(
        valueListenable: box.listenable(),
        builder: (context, box, _) {
          final entries = _todayEntries(box);
          final grouped = _groupByPeriod(entries);
          final takenCount = entries.where((e) => e.medicine.isTaken(e.time)).length;
          final nextEntry = _nextUntaken(entries);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _todayString(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                launchUrl(
                                  Uri.parse('https://ssamssae.github.io/daejong-page'),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.favorite, size: 12, color: Colors.amber.shade300),
                                    const SizedBox(width: 4),
                                    Text(
                                      '응원',
                                      style: TextStyle(
                                        color: Colors.amber.shade300,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entries.isEmpty
                              ? '등록된 약이 없어요'
                              : '오늘 $takenCount / ${entries.length} 완료',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (entries.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: takenCount / entries.length,
                              minHeight: 6,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                takenCount == entries.length
                                    ? Colors.green
                                    : const Color(0xFFFFC107),
                              ),
                            ),
                          ),
                        ],
                        // 다음 복용 카운트다운 (고정 높이)
                        const SizedBox(height: 12),
                        if (nextEntry != null)
                          _CountdownBanner(entry: nextEntry)
                        else if (entries.isNotEmpty && takenCount == entries.length)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(
                                  '오늘 약을 모두 복용했어요!',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              if (entries.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
              else
                ..._buildGroupedSlivers(context, grouped),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MedicineEditScreen()),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('약 등록'),
      ),
    );
  }

  /// 아직 안 먹은 것 중 가장 가까운 다음 복용
  _Entry? _nextUntaken(List<_Entry> entries) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    _Entry? best;
    int bestDiff = 999999;

    for (final e in entries) {
      if (e.medicine.isTaken(e.time)) continue;
      final eMin = e.time.hour * 60 + e.time.minute;
      // 오늘 남은 시간 기준
      int diff = eMin - nowMin;
      if (diff < -1) continue; // 이미 지나간 시간은 스킵 (1분 여유)
      if (diff < 0) diff = 0;
      if (diff < bestDiff) {
        bestDiff = diff;
        best = e;
      }
    }
    return best;
  }

  String _todayString() {
    final now = DateTime.now();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일';
  }

  List<_Entry> _todayEntries(Box<Medicine> box) {
    final list = <_Entry>[];
    for (final m in box.values) {
      for (final t in m.times) {
        list.add(_Entry(medicine: m, time: t));
      }
    }
    list.sort((a, b) {
      final am = a.time.hour * 60 + a.time.minute;
      final bm = b.time.hour * 60 + b.time.minute;
      return am.compareTo(bm);
    });
    return list;
  }

  Map<String, List<_Entry>> _groupByPeriod(List<_Entry> entries) {
    final groups = <String, List<_Entry>>{};
    for (final e in entries) {
      final period = _periodLabel(e.time.hour);
      groups.putIfAbsent(period, () => []).add(e);
    }
    return groups;
  }

  String _periodLabel(int hour) {
    if (hour < 6) return '새벽';
    if (hour < 12) return '아침';
    if (hour < 18) return '오후';
    return '저녁';
  }

  List<Widget> _buildGroupedSlivers(
      BuildContext context, Map<String, List<_Entry>> grouped) {
    final theme = Theme.of(context);
    final slivers = <Widget>[];

    for (final entry in grouped.entries) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Icon(
                _periodIcon(entry.key),
                size: 18,
                color: const Color(0xFFFFC107),
              ),
              const SizedBox(width: 6),
              Text(
                entry.key,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFFC107),
                ),
              ),
            ],
          ),
        ),
      ));

      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MedicineCard(
                medicine: entry.value[i].medicine,
                time: entry.value[i].time,
              ),
            ),
            childCount: entry.value.length,
          ),
        ),
      ));
    }
    return slivers;
  }

  IconData _periodIcon(String period) {
    switch (period) {
      case '새벽':
        return Icons.dark_mode_outlined;
      case '아침':
        return Icons.wb_sunny_outlined;
      case '오후':
        return Icons.wb_cloudy_outlined;
      default:
        return Icons.nightlight_outlined;
    }
  }
}

class _Entry {
  final Medicine medicine;
  final DoseTime time;
  _Entry({required this.medicine, required this.time});
}

class _CountdownBanner extends StatelessWidget {
  final _Entry entry;
  const _CountdownBanner({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, entry.time.hour, entry.time.minute);
    final diff = target.difference(now);

    String countdown;
    if (diff.isNegative) {
      countdown = '지금 드세요!';
    } else {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      final s = diff.inSeconds % 60;
      if (h > 0) {
        countdown = '$h시간 $m분 후';
      } else if (m > 0) {
        countdown = '$m분 $s초 후';
      } else {
        countdown = '$s초 후';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC107).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFFFC107)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: entry.medicine.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' ${entry.medicine.dosage}',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
          Text(
            countdown,
            style: const TextStyle(
              color: Color(0xFFFFC107),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final Medicine medicine;
  final DoseTime time;
  const _MedicineCard({required this.medicine, required this.time});

  static String _periodLabel2(int hour) {
    if (hour < 5) return '밤';
    if (hour < 9) return '아침';
    if (hour < 12) return '오전';
    if (hour < 14) return '낮';
    if (hour < 18) return '오후';
    return '저녁';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taken = medicine.isTaken(time);

    return Card(
      color: taken
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MedicineEditScreen(medicine: medicine),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: taken
                      ? Colors.green.withValues(alpha: 0.2)
                      : const Color(0xFFFFC107).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _periodLabel2(time.hour),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: taken ? Colors.green : const Color(0xFFFFC107),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour)}:${time.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: taken ? Colors.green : const Color(0xFFFFC107),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: taken ? TextDecoration.lineThrough : null,
                        color: taken ? theme.colorScheme.outline : null,
                      ),
                    ),
                    if (medicine.dosage.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        medicine.dosage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _TakenButton(
                taken: taken,
                onTap: () => medicine.toggleTaken(time),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TakenButton extends StatelessWidget {
  final bool taken;
  final VoidCallback onTap;
  const _TakenButton({required this.taken, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: taken ? Colors.green : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: taken ? Colors.green : Theme.of(context).colorScheme.outline,
            width: taken ? 0 : 1.5,
          ),
        ),
        child: Icon(
          Icons.check_rounded,
          color: taken ? Colors.white : Theme.of(context).colorScheme.outline,
          size: 22,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medication_outlined,
              size: 56,
              color: Color(0xFFFFC107),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '아직 등록된 약이 없어요',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '아래 버튼을 눌러 약을 추가해 보세요',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
