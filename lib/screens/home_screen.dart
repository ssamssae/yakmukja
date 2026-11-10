import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../config.dart';
import '../main.dart';
import '../models/medicine.dart';
import '../services/app_review_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/renewal_theme.dart';
import '../widgets/pill_glyph.dart';
import '../widgets/renewal_check.dart';
import 'history_screen.dart';
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

/// 복용 시각이 이만큼(분) 지나도록 안 먹었으면 「지금」 대신 지난 시간을 알린다.
/// (T-261110-033)
const int doseOverdueAfterMinutes = 30;

/// 복용 시각이 [doseOverdueAfterMinutes] 넘게 지났는가.
bool isDoseOverdue(int doseMinute, int nowMinute) =>
    nowMinute - doseMinute >= doseOverdueAfterMinutes;

/// 「20분」「2시간」「1시간 30분」.
String _spanText(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes분';
  if (minutes == 0) return '$hours시간';
  return '$hours시간 $minutes분';
}

/// 큰 카드의 남은 시간. 시각이 됐으면 "지금", 30분 넘게 지났으면 "N분 지남".
String doseRemainText(int doseMinute, int nowMinute) {
  final remain = doseMinute - nowMinute;
  if (remain > 0) return '${_spanText(remain)} 남음';
  if (isDoseOverdue(doseMinute, nowMinute)) return '${_spanText(-remain)} 지남';
  return '지금';
}

/// 큰 카드의 「먹었어요」를 누른 뒤 다음 누름을 받지 않는 시간. 누르면 같은 자리에 다음
/// 약의 단추가 올라오므로, 연달아 눌러 다음 약까지 표시되는 것을 막는다. 일부러 이어
/// 누르는 것은 막지 않을 만큼 짧다. (T-261110-036)
const Duration takeTapGuard = Duration(milliseconds: 400);

/// 「모두 먹었어요」를 누른 뒤 다음 누름을 받지 않는 시간. 한 번에 여러 약이 바뀌므로
/// 더 길게 둔다. (T-261110-036)
const Duration takeAllTapGuard = Duration(seconds: 1);

/// 「모두 먹었어요」 뒤의 되돌리기 안내가 떠 있는 시간. (T-261110-036)
const Duration takeAllNoticeDuration = Duration(seconds: 6);

/// 오늘 약을 다 먹은 뒤 평가를 부탁하기까지의 기다림 — 「다 먹었어요」 화면을 먼저
/// 보게 한다. (T-261110-040)
const Duration reviewAskDelay = Duration(milliseconds: 1200);

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

  // 평가 부탁 — 「먹었어요」를 눌러 오늘 약을 다 먹은 순간을 알아챈다. (T-261110-040)
  late final Box<Medicine> _box;
  late final Listenable _boxChanges;
  int _lastTaken = 0;
  int _lastTotal = 0;
  Timer? _reviewTimer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoSnack;
  bool _reviewInFlight = false;
  int _reviewEpoch = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _onResume,
      onHide: _cancelReviewAsk,
      onPause: () {
        _minuteTick?.cancel();
        _cancelReviewAsk();
      },
    );
    NotificationService.enabled.addListener(_onPermissionChanged);
    _box = Hive.box<Medicine>(medicineBoxName);
    _boxChanges = _box.listenable()..addListener(_onDosesChanged);
    _rememberDoseCounts();
    _armMinuteTick();
  }

  void _onPermissionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _minuteTick?.cancel();
    _takeGuard?.cancel();

    _reviewTimer?.cancel();
    _boxChanges.removeListener(_onDosesChanged);
    _lifecycle.dispose();
    NotificationService.enabled.removeListener(_onPermissionChanged);
    super.dispose();
  }

  /// 오늘 먹을 약 개수와 먹은 개수를 기억해 둔다. 다음 변화와 견주는 기준이다.
  void _rememberDoseCounts() {
    final entries = _todayEntries(_box, _now());
    _lastTotal = entries.length;
    _lastTaken = entries.where((entry) => entry.taken).length;
  }

  /// 약 저장이 바뀔 때마다: 약 구성은 그대로인데 체크가 늘어 오늘 약을 다 먹은
  /// 상태가 됐으면 잠시 뒤 평가를 부탁한다. 약을 지우거나 시간을 고쳐서 다 먹은
  /// 상태가 된 것은 치지 않는다.
  void _onDosesChanged() {
    final beforeTotal = _lastTotal;
    final beforeTaken = _lastTaken;
    _rememberDoseCounts();
    final allTaken = _lastTotal > 0 && _lastTaken == _lastTotal;
    if (allTaken && _lastTotal == beforeTotal && _lastTaken > beforeTaken) {
      _scheduleReviewAsk();
    } else if (!allTaken) {
      // 되돌렸다. 이미 스토어에 묻는 중이면 그것도 횟수에 넣지 않는다.
      _cancelReviewAsk();
    }
  }

  void _cancelReviewAsk() {
    _reviewTimer?.cancel();
    _reviewTimer = null;
    // 이미 스토어에 묻는 중이거나 되돌리기 안내를 기다리는 부탁도 함께 버린다.
    _reviewEpoch++;
  }

  void _scheduleReviewAsk() {
    // 스토어 화면 캡처 때는 평가 창을 띄우지 않는다.
    if (kScreenshotMode) return;
    _reviewTimer?.cancel();
    final epoch = _reviewEpoch;
    _reviewTimer = Timer(reviewAskDelay, () {
      if (epoch != _reviewEpoch) return;
      _fireReviewAsk();
    });
  }

  /// 1.2초가 지났거나, 되돌리기 안내가 내려간 뒤. 아직 부탁할 자리인지 다시 본다.
  void _fireReviewAsk() {
    _reviewTimer = null;
    if (!mounted || _reviewInFlight) return;
    final epoch = _reviewEpoch;
    final undo = _undoSnack;
    if (undo != null) {
      // 「모두 먹었어요」 되돌리기가 남아 있다. 안내가 내려간 뒤에 다시 본다.
      undo.closed.then((_) {
        if (!mounted || epoch != _reviewEpoch) return;
        _fireReviewAsk();
      });
      return;
    }
    if (!_reviewStillWanted()) return;
    _reviewInFlight = true;
    unawaited(() async {
      try {
        await AppReviewService.maybeAskForReview(
          _box.values,
          stillWanted: () => epoch == _reviewEpoch && _reviewStillWanted(),
        );
      } finally {
        _reviewInFlight = false;
      }
    }());
  }

  /// 지금 이 자리에서 평가를 부탁해도 되는가.
  /// 설정 탭은 같은 경로라 [ModalRoute.isCurrent] 가 참이다. IndexedStack 이
  /// 감싼 [Visibility] 로 홈이 가려졌는지를 따로 본다.
  bool _reviewStillWanted() {
    if (!mounted || kScreenshotMode) return false;
    final entries = _todayEntries(_box, _now());
    if (entries.isEmpty || entries.any((entry) => !entry.taken)) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (!_isHomeShown()) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    return true;
  }

  bool _isHomeShown() {
    var shown = true;
    context.visitAncestorElements((element) {
      final ancestor = element.widget;
      if (ancestor is Visibility && !ancestor.visible) {
        shown = false;
        return false;
      }
      return true;
    });
    return shown;
  }

  void _onResume() {
    _refreshNow();
    // 기기 설정에서 알림을 켜거나 끄고 돌아왔을 수 있다. (T-261110-026)
    unawaited(NotificationService.refreshPermission());
  }

  bool _enablingNotifications = false;

  /// 「알림 켜기」 — 권한을 다시 묻고, 앱에서 켤 수 없으면 켜는 길을 알려 준다.
  Future<void> _enableNotifications() async {
    // 권한 창이 떠 있는 동안 또 눌렀다 — 안내가 두 번 나가지 않게 한다.
    if (_enablingNotifications) return;
    _enablingNotifications = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await NotificationService.requestEnable();
      if (result == NotificationEnableResult.needsManual) {
        messenger.showSnackBar(
          const SnackBar(content: Text('휴대폰 설정에서 약먹자 알림을 켜 주세요')),
        );
      }
    } finally {
      _enablingNotifications = false;
    }
  }

  // 큰 카드의 복용 단추를 방금 눌렀다 — 잠깐 다음 누름을 받지 않는다. (T-261110-036)
  Timer? _takeGuard;

  /// 지금 누름을 받아도 되면 true 를 돌려주고, [guard] 동안 다음 누름을 막는다.
  bool _acceptTakeTap(Duration guard) {
    if (_takeGuard != null) return false;
    _takeGuard = Timer(guard, () => _takeGuard = null);
    return true;
  }

  /// 큰 카드의 「먹었어요」.
  void _takeOne(_Entry entry) {
    if (!_acceptTakeTap(takeTapGuard)) return;
    entry.medicine.toggleTaken(entry.time);
  }

  /// 큰 카드의 「모두 먹었어요」 — 같은 시각의 안 먹은 약을 한 번에 먹음으로 표시하고,
  /// 되돌릴 길을 준다. (T-261110-036)
  void _takeAll(List<_Entry> sameTime, String when) {
    if (!_acceptTakeTap(takeAllTapGuard)) return;
    final messenger = ScaffoldMessenger.of(context);
    // 화면 읽기 탐색을 쓰는 사람은 스스로 닫을 때까지 안내를 둔다.
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final marked = <_Entry>[];
    for (final item in sameTime) {
      if (item.taken) continue;
      item.medicine.toggleTaken(item.time);
      marked.add(item);
    }
    if (marked.isEmpty) return;
    messenger.hideCurrentSnackBar();
    final shown = messenger.showSnackBar(
      SnackBar(
        content: Text('$when 약 ${marked.length}개를 먹었다고 표시했어요'),
        // 단추가 있는 안내는 기본이 「계속 떠 있음」이다. 그대로 두면 다른 화면의
        // 단추를 가리고 다른 안내도 막으므로 몇 초 뒤 내린다.
        duration: takeAllNoticeDuration,
        persist: accessible,
        showCloseIcon: accessible,
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            for (final item in marked) {
              // 그 사이 지워진 약은 건드리지 않는다. 이미 되돌린 약도 그대로 둔다.
              if (item.medicine.isInBox && item.taken) {
                item.medicine.toggleTaken(item.time);
              }
            }
          },
        ),
      ),
    );
    _undoSnack = shown;
    shown.closed.whenComplete(() {
      if (identical(_undoSnack, shown)) _undoSnack = null;
    });
  }

  void _refreshNow() {
    if (!mounted) return;
    // 날짜가 넘어갔을 수 있다 — 오늘 기준으로 다시 잡는다. (T-261110-040)
    _rememberDoseCounts();
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
              final offDay = _offDayMedicines(box, now);
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
              // 큰 카드의 약과 같은 시각에 아직 안 먹은 약(큰 카드의 약 포함).
              // (T-261110-036)
              final sameTime = next == null
                  ? const <_Entry>[]
                  : [
                      for (final entry in entries)
                        if (!entry.taken &&
                            entry.minuteOfDay == next.minuteOfDay)
                          entry,
                    ];
              final takenCount = entries.where((entry) => entry.taken).length;
              // 기기에서 알림이 꺼져 있는데 알려 줄 약이 있다. (T-261110-026)
              final notificationsOff =
                  NotificationService.enabled.value == false;
              final warnNotificationsOff =
                  notificationsOff && (entries.isNotEmpty || offDay.isNotEmpty);
              return ListView(
                physics: entries.isEmpty && offDay.isEmpty
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
                    offDayOnly: entries.isEmpty && offDay.isNotEmpty,
                    onOpenHistory: _openHistory,
                  ),
                  if (warnNotificationsOff) ...[
                    const SizedBox(height: 16),
                    _NotificationOffCard(onEnable: _enableNotifications),
                  ],
                  const SizedBox(height: 22),
                  if (entries.isEmpty && offDay.isEmpty)
                    const _EmptyState()
                  else if (entries.isEmpty)
                    const _EmptyState.offDay()
                  else if (next == null)
                    const _AllDoneCard()
                  else
                    _NowCard(
                      entry: next,
                      sameTime: sameTime,
                      nowMinute: nowMinute,
                      notificationsOff: notificationsOff,
                      onTake: () => _takeOne(next),
                      onTakeAll: () => _takeAll(sameTime, next.when),
                    ),
                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    _RestHeader(count: rest.length),
                    const SizedBox(height: 12),
                    _RestList(entries: rest, nowMinute: nowMinute),
                  ],
                  if (offDay.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    _RestHeader(title: '오늘 쉬는 약', count: offDay.length),
                    const SizedBox(height: 12),
                    _OffDayList(medicines: offDay),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 머리말을 누르면 지난 기록을 연다. 홈의 시계를 그대로 넘긴다. (T-261110-039)
  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(clock: widget.clock),
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

  /// 등록은 돼 있지만 오늘 먹는 요일이 아닌 약. 휴지통 약은 뺀다. (T-261110-021)
  List<Medicine> _offDayMedicines(Box<Medicine> box, DateTime now) {
    final today = now.weekday;
    return [
      for (final medicine in box.values)
        if (medicine.deletedAt == null && !medicine.isOnWeekday(today))
          medicine,
    ];
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
    required this.onOpenHistory,
    this.offDayOnly = false,
  });

  final String dateLabel;
  final int taken;
  final int total;

  /// 머리말을 누르면 지난 기록을 연다. (T-261110-039)
  final VoidCallback onOpenHistory;

  /// 약은 있지만 오늘 먹는 요일의 약이 하나도 없는 날.
  final bool offDayOnly;

  @override
  Widget build(BuildContext context) {
    final title = total > 0
        ? '오늘 $taken/$total 먹었어요'
        : offDayOnly
        ? '오늘은 먹을 약이 없어요'
        : '아직 등록된 약이 없어요';
    // 머리말 전체가 「지난 기록」으로 가는 단추다. 날짜 옆 화살표가 그 표시다.
    return Semantics(
      key: const Key('home-history-link'),
      container: true,
      button: true,
      label: '$dateLabel, $title, 지난 기록 보기',
      onTap: onOpenHistory,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpenHistory,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              dateLabel,
                              style: renewalStyle(
                                14,
                                FontWeight.w600,
                                RenewalColors.date,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: RenewalColors.date,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: renewalStyle(
                          24,
                          FontWeight.w800,
                          RenewalColors.ink,
                        ),
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
          ),
        ),
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
  const _NowCard({
    required this.entry,
    required this.sameTime,
    required this.nowMinute,
    required this.onTake,
    required this.onTakeAll,
    this.notificationsOff = false,
  });

  final _Entry entry;

  /// 「먹었어요」를 눌렀다.
  final VoidCallback onTake;

  /// 「모두 먹었어요」를 눌렀다.
  final VoidCallback onTakeAll;

  /// [entry] 와 같은 시각에 아직 안 먹은 약([entry] 포함). 2개 이상이면
  /// 한 번에 표시하는 단추를 보인다. (T-261110-036)
  final List<_Entry> sameTime;
  final int nowMinute;

  /// 기기에서 알림이 꺼져 있다 — 알림 예고를 하지 않는다.
  final bool notificationsOff;

  @override
  Widget build(BuildContext context) {
    final medicine = entry.medicine;
    final look = lookForMedicineName(medicine.name);
    final remain = doseRemainText(entry.minuteOfDay, nowMinute);
    // 시간이 한참 지났는데 안 먹은 약 — 「다음 약」이 아니라 「지난 약」으로 알린다.
    // (T-261110-033)
    final overdue = isDoseOverdue(entry.minuteOfDay, nowMinute);
    final accent = overdue ? RenewalColors.danger : RenewalColors.greenDeep;
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
                    // 한 줄에 다 안 들어가면(큰 글씨·좁은 화면) 남은 시간이 다음 줄로
                    // 내려간다. 들어가면 종전처럼 양 끝에 붙는다. (T-261110-037)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                          decoration: BoxDecoration(
                            color: overdue
                                ? RenewalColors.danger50
                                : RenewalColors.green50,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: overdue
                                      ? RenewalColors.danger
                                      : RenewalColors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                overdue ? '지난 약' : '다음 약',
                                style: renewalStyle(
                                  13,
                                  FontWeight.w700,
                                  accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 18,
                              color: accent,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                remain,
                                style: renewalStyle(
                                  15,
                                  FontWeight.w800,
                                  accent,
                                ),
                              ),
                            ),
                          ],
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
                              // 요일이 많거나 단위가 길면 다음 줄로 내려간다.
                              // (T-261110-037)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (medicine.dosage.isNotEmpty)
                                    _Tag(text: medicine.dosage),
                                  _Tag(text: medicine.weekdayLabel),
                                ],
                              ),
                              // 먹을 차례에 볼 메모(예: 식후 30분). (T-261110-031)
                              if (medicine.memo.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  key: const Key('home-next-memo'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.sticky_note_2_outlined,
                                        size: 16,
                                        color: RenewalColors.faint,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        medicine.memo.trim(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: renewalStyle(
                                          14,
                                          FontWeight.w600,
                                          RenewalColors.body,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                onTap: onTake,
              ),
              // 같은 시각에 먹는 약이 더 있으면 한 번에 표시할 수 있다. (T-261110-036)
              if (sameTime.length >= 2) ...[
                const SizedBox(height: 10),
                _TakeAllButton(
                  text: '${entry.when} 약 ${sameTime.length}개 모두 먹었어요',
                  label: '${entry.when} 약 ${sameTime.length}개 모두 복용 완료로 표시',
                  onTap: onTakeAll,
                ),
              ],
              // 알림 안내는 복용 시각 전에만 보인다. 시각이 지나면 「지금」 카드에 미래형 문구가 남지 않게 한다.
              // 기기에서 알림이 꺼져 있으면 지키지 못할 예고라 보이지 않는다. (T-261110-026)
              if (entry.minuteOfDay > nowMinute && !notificationsOff) ...[
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

/// 같은 시각 약을 한 번에 표시하는 보조 단추. 「먹었어요」보다 덜 눈에 띄게 둔다.
/// (T-261110-036)
class _TakeAllButton extends StatelessWidget {
  const _TakeAllButton({
    required this.text,
    required this.label,
    required this.onTap,
  });

  final String text;

  /// 보조 기술이 읽는 글.
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
        child: Material(
          key: const Key('home-take-all-button'),
          color: RenewalColors.green50,
          borderRadius: BorderRadius.circular(RenewalRadius.button),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(RenewalRadius.button),
            // 누르기 쉬운 크기(높이 48 이상)를 지킨다. 글이 길면 두 줄이 된다.
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.done_all_rounded,
                    size: 20,
                    color: RenewalColors.greenDeep,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: renewalStyle(
                        15,
                        FontWeight.w700,
                        RenewalColors.greenDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
  const _RestHeader({required this.count, this.title = '오늘 나머지'});

  final int count;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            title,
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
  const _RestList({required this.entries, required this.nowMinute});

  final List<_Entry> entries;
  final int nowMinute;

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
              _RestRow(entry: entry, nowMinute: nowMinute),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestRow extends StatelessWidget {
  const _RestRow({required this.entry, required this.nowMinute});

  final _Entry entry;
  final int nowMinute;

  @override
  Widget build(BuildContext context) {
    final taken = entry.taken;
    final medicine = entry.medicine;
    final look = lookForMedicineName(medicine.name);
    final detail = medicine.dosage.isEmpty
        ? entry.when
        : '${entry.when} · ${medicine.dosage}';
    // 지나갔는데 아직 안 먹은 약. (T-261110-033)
    final overdue = !taken && isDoseOverdue(entry.minuteOfDay, nowMinute);
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
                              if (overdue)
                                TextSpan(
                                  text:
                                      '  ${doseRemainText(entry.minuteOfDay, nowMinute)}',
                                  style: renewalStyle(
                                    13,
                                    FontWeight.w700,
                                    RenewalColors.danger,
                                  ),
                                ),
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
  const _EmptyState()
    : cardKey = const Key('home-empty'),
      message = '아래 + 약등록을 눌러\n약을 추가해 보세요';

  /// 약은 있지만 오늘 먹는 요일이 아닌 날. (T-261110-021)
  const _EmptyState.offDay()
    : cardKey = const Key('home-off-day'),
      message = '오늘은 쉬는 날이에요';

  final Key cardKey;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: cardKey,
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
              message,
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

/// 오늘 먹는 요일이 아닌 약 목록. 누르면 그 약의 수정 화면으로 간다. (T-261110-021)
class _OffDayList extends StatelessWidget {
  const _OffDayList({required this.medicines});

  final List<Medicine> medicines;

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
            for (final (i, medicine) in medicines.indexed) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 72,
                  endIndent: 18,
                  color: RenewalColors.line,
                ),
              _OffDayRow(medicine: medicine),
            ],
          ],
        ),
      ),
    );
  }
}

class _OffDayRow extends StatelessWidget {
  const _OffDayRow({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final look = lookForMedicineName(medicine.name);
    final times = [
      for (final time in medicine.times)
        '${homePeriodLabel(time.hour)} ${homeClockLabel(time.hour, time.minute)}',
    ].join(', ');
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MedicineEditScreen(medicine: medicine),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
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
                opacity: 0.55,
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
                    style: renewalStyle(16, FontWeight.w700, RenewalColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${medicine.weekdayLabel} · $times',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: renewalStyle(
                      13,
                      FontWeight.w400,
                      RenewalColors.faint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: RenewalColors.hush,
            ),
          ],
        ),
      ),
    );
  }
}

/// 기기에서 알림이 꺼져 있을 때의 안내. 약 시간에 알려 주지 못하므로 눈에 띄게 둔다.
/// 단추는 글 아래에 둔다 — 옆에 두면 좁은 화면·큰 글씨에서 글 칸이 좁아져
/// 「…있어 / 요」처럼 꺾인다. (T-261110-026)
class _NotificationOffCard extends StatelessWidget {
  const _NotificationOffCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('home-notification-off'),
      decoration: renewalCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFEEEE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_off_rounded,
                    size: 22,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '알림이 꺼져 있어요',
                        style: renewalStyle(
                          16,
                          FontWeight.w800,
                          RenewalColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '약 먹을 시간에 알려드리지 못해요',
                        style: renewalStyle(
                          13,
                          FontWeight.w500,
                          RenewalColors.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              button: true,
              label: '알림 켜기',
              onTap: onEnable,
              child: ExcludeSemantics(
                child: Material(
                  color: RenewalColors.green,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: onEnable,
                    borderRadius: BorderRadius.circular(999),
                    // 누르기 쉬운 크기(높이 48 이상)를 지킨다.
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '알림 켜기',
                        textAlign: TextAlign.center,
                        style: renewalStyle(15, FontWeight.w700, Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
