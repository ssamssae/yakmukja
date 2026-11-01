import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/iap_service.dart';
import '../theme/app_theme.dart';
import 'medicine_edit_screen.dart';

String takenButtonSemanticsLabel({
  required String prefix,
  required bool taken,
}) {
  return taken ? '$prefix 복용 완료 취소' : '$prefix 복용 완료로 표시';
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Medicine>(medicineBoxName);

    return Scaffold(
      body: ValueListenableBuilder<Box<Medicine>>(
        valueListenable: box.listenable(),
        builder: (context, box, _) {
          final entries = _todayEntries(box);
          final grouped = _groupByPeriod(entries);
          final takenCount = entries
              .where((e) => e.medicine.isTaken(e.time))
              .length;

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
                        // 날짜(좌) + 광고제거 진입(우상단). 설정은 하단 탭으로 이동(T-260614-12).
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _todayString(),
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textFaint,
                                  letterSpacing: -0.2,
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
                                  color: AppColors.textFaint,
                                  tooltip: '광고 제거',
                                  onPressed: () async {
                                    final result =
                                        await IapService.buyRemoveAds();
                                    final msg = IapService.purchaseMessage(
                                      result,
                                    );
                                    if (msg != null && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(msg)),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entries.isEmpty
                              ? '등록된 약이 없어요'
                              : '오늘 $takenCount / ${entries.length} 완료',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.6,
                            color: AppColors.textStrong,
                          ),
                        ),
                        if (entries.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: takenCount / entries.length,
                              minHeight: 8,
                              backgroundColor: AppColors.trackGrey,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                takenCount == entries.length
                                    ? AppColors.success
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                        // 축하 배너 자리는 약이 있으면 항상 예약(Visibility maintainSize) —
                        // 모두복용 체크/해제 시 아래 리스트가 위아래로 점프하지 않게 한다.
                        // (T-260614-12 카운트다운 제거 후 점프 재발 방지, 아니키 요청)
                        if (entries.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Visibility(
                            visible: takenCount == entries.length,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.greenSoft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.success.withValues(
                                    alpha: 0.25,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.celebration_rounded,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    '오늘 약을 모두 복용했어요!',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontFamily,
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              if (entries.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else ...[
                ..._buildGroupedSlivers(context, grouped),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
          );
        },
      ),
      // 푸터(버전·배너)·탭바는 MainShell 이 소유. 떠있는 약등록 FAB 제거 (T-260614-12)
    );
  }

  String _todayString() {
    final now = DateTime.now();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일';
  }

  List<_Entry> _todayEntries(Box<Medicine> box) {
    final today = DateTime.now().weekday; // ISO 1=월 … 7=일
    final list = <_Entry>[];
    for (final m in box.values) {
      if (m.deletedAt != null) continue; // 휴지통 약은 목록 제외 (T-260614-12)
      // 오늘 요일에 복용하는 약만 노출. 매일 약은 항상 포함.
      if (!m.isOnWeekday(today)) continue;
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
    BuildContext context,
    Map<String, List<_Entry>> grouped,
  ) {
    final slivers = <Widget>[];

    for (final entry in grouped.entries) {
      slivers.add(
        SliverToBoxAdapter(
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
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value.length}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
        ),
      );
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

class _MedicineCard extends StatelessWidget {
  final Medicine medicine;
  final DoseTime time;
  const _MedicineCard({required this.medicine, required this.time});

  @override
  Widget build(BuildContext context) {
    final taken = medicine.isTaken(time);
    final accentFill = taken ? AppColors.success : AppColors.primary;
    final radius = BorderRadius.circular(AppRadius.homeCard);
    final cardColor = taken ? const Color(0xFFF1F3F5) : AppColors.surface;
    return DecoratedBox(
      decoration: appCardDecoration(color: cardColor, radius: radius),
      child: Material(
        color: cardColor,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
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
                    color: accentFill.withValues(alpha: taken ? 0.18 : 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accentFill.withValues(alpha: taken ? 0.25 : 0.22),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        time.periodLabel,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour)}:${time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
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
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          decoration: taken ? TextDecoration.lineThrough : null,
                          color: taken
                              ? AppColors.textFaint
                              : AppColors.textStrong,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (medicine.dosage.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.medical_services_outlined,
                              size: 14,
                              color: AppColors.textFaint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              medicine.dosage,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textBody,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // 요일 정보는 모든 약 카드에 항상 표시(매일→"매일", 특정요일→"월·수·금").
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.event_repeat_outlined,
                            size: 14,
                            color: AppColors.textFaint,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            medicine.weekdayLabel,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textBody,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _TakenButton(
                  taken: taken,
                  semanticsPrefix: '${medicine.name} ${time.format()}',
                  onTap: () => medicine.toggleTaken(time),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TakenButton extends StatelessWidget {
  final bool taken;
  final String semanticsPrefix;
  final VoidCallback onTap;
  const _TakenButton({
    required this.taken,
    required this.semanticsPrefix,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = takenButtonSemanticsLabel(
      prefix: semanticsPrefix,
      taken: taken,
    );
    return Semantics(
      container: true,
      button: true,
      selected: taken,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: taken ? AppColors.success : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: taken ? AppColors.success : AppColors.textFaint,
                width: taken ? 0 : 1.5,
              ),
            ),
            child: Icon(
              Icons.check_rounded,
              color: taken ? Colors.white : AppColors.textFaint,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
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
            const Text(
              '아직 등록된 약이 없어요',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '아래 버튼을 눌러 약을 추가해 보세요',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.textBody,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
