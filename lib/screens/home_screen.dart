import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/ads_service.dart';
import '../services/iap_service.dart';
import '../theme/app_theme.dart';
import '../widgets/version_footer.dart';
import 'medicine_edit_screen.dart';
import 'settings_screen.dart';

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
            // 빈 상태에서 오버스크롤로 "등록된 약이 없어요" 가 화면 밖으로 밀려 나가는 이슈 방지
            physics: entries.isEmpty
                ? const NeverScrollableScrollPhysics()
                : null,
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜(좌) + 설정 진입 아이콘(우상단). (T-260614-14)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _todayString(),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.outline,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            // 광고 제거 구매 버튼 — 이미 제거됐으면 숨김.
                            ValueListenableBuilder<bool>(
                              valueListenable: IapService.adsRemoved,
                              builder: (context, removed, _) {
                                if (removed) return const SizedBox.shrink();
                                return IconButton(
                                  icon: const Icon(Icons.block),
                                  color: theme.colorScheme.outline,
                                  tooltip: '광고 제거',
                                  onPressed: IapService.buyRemoveAds,
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined),
                              color: theme.colorScheme.outline,
                              tooltip: '설정',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entries.isEmpty
                              ? '등록된 약이 없어요'
                              : '오늘 $takenCount / ${entries.length} 완료',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (entries.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: takenCount / entries.length,
                              minHeight: 8,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                takenCount == entries.length
                                    ? AppColors.success
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                        // 배너 슬롯 — 다음복용 카운트다운 / 모두복용 안내 / 없음 상태와
                        // 무관하게 고정 높이(72)로 예약해 아래 약 리스트가 위아래로
                        // 점프하지 않게 한다. 배너는 자연 높이 유지 + 상단 정렬.
                        // (T-260614-11 (B) 레이아웃 점프 수정)
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (nextEntry != null)
                                _CountdownBanner(entry: nextEntry)
                              else if (entries.isNotEmpty && takenCount == entries.length)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.success.withValues(alpha: 0.25),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.celebration_rounded, size: 20, color: AppColors.success),
                                      const SizedBox(width: 10),
                                      Text(
                                        '오늘 약을 모두 복용했어요!',
                                        style: TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
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
              else ...[
                ..._buildGroupedSlivers(context, grouped),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VersionFooter(),
          AdaptiveBanner(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // Transform.translate 로 올리면 Scaffold FAB 슬롯이 원위치라 탭이 안 잡힘.
      // Padding 으로 슬롯 자체를 키워서 시각 위치 유지 + 히트테스트 정상화.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MedicineEditScreen()),
            );
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('약 등록'),
        ),
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
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _periodIcon(entry.key),
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                entry.key,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.value.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w500,
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

    final urgent = diff.isNegative || diff.inMinutes < 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: urgent ? 0.45 : 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '다음 복용',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: entry.medicine.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '  ${entry.medicine.dosage}',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            countdown,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: -0.2,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taken = medicine.isTaken(time);

    final accent = taken ? AppColors.success : AppColors.primary;
    return Card(
      color: taken ? const Color(0xFFF1F3F5) : AppColors.surface,
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
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: taken ? 0.18 : 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accent.withValues(alpha: taken ? 0.25 : 0.22),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      time.periodLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour)}:${time.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
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
                        fontWeight: FontWeight.w700,
                        decoration: taken ? TextDecoration.lineThrough : null,
                        color: taken ? theme.colorScheme.outline : null,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (medicine.dosage.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.medical_services_outlined,
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            medicine.dosage,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
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
          color: taken ? AppColors.success : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: taken ? AppColors.success : Theme.of(context).colorScheme.outline,
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
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.primary.withValues(alpha: 0.04),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medication_rounded,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '아직 등록된 약이 없어요',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '아래 버튼을 눌러 약을 추가해 보세요',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
