import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/renewal_theme.dart';
import '../widgets/pill_glyph.dart';

class MedicineEditScreen extends StatefulWidget {
  final Medicine? medicine;
  const MedicineEditScreen({super.key, this.medicine});

  bool get isEditing => medicine != null;

  @override
  State<MedicineEditScreen> createState() => _MedicineEditScreenState();
}

class _MedicineEditScreenState extends State<MedicineEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late List<DoseTime> _times;
  // 복용 요일 (ISO: 1=월 … 7=일). 기본 = 매일(전체 선택).
  late Set<int> _weekdays;
  bool _isSaving = false;

  // 요일 칩 라벨 (월→일, ISO 1..7 순서)
  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  // 용량: 0.5 ~ 10 (0.5 단위)
  static final List<String> _dosageOptions = [
    for (int i = 1; i <= 20; i++) (i * 0.5).toString().replaceAll('.0', ''),
  ];
  String? _dosage; // null이면 아직 선택 안 함

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _times = m == null
        ? <DoseTime>[]
        : m.times.map((t) => DoseTime(hour: t.hour, minute: t.minute)).toList();
    // 신규 등록 기본 = 매일. 수정 시 기존 요일(마이그레이션 안전 게터) 사용.
    _weekdays = m == null ? {...Medicine.allWeekdays} : {...m.activeWeekdays};

    if (m != null && m.dosage.isNotEmpty) {
      _dosage = m.dosage;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _showDosagePicker() {
    final currentRaw = _dosage?.replaceAll('알', '').trim();
    int tempIndex = _dosageOptions.indexOf(currentRaw ?? '1');
    if (tempIndex < 0) tempIndex = 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        '복용량 선택',
                        style: renewalStyle(
                          17,
                          FontWeight.w800,
                          RenewalColors.ink,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          '취소',
                          style: renewalStyle(
                            15,
                            FontWeight.w700,
                            RenewalColors.faint,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(
                            () => _dosage = '${_dosageOptions[tempIndex]}알',
                          );
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          '확인',
                          style: renewalStyle(
                            15,
                            FontWeight.w800,
                            RenewalColors.greenDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: tempIndex,
                    ),
                    itemExtent: 44,
                    onSelectedItemChanged: (i) => tempIndex = i,
                    children: [
                      for (final d in _dosageOptions)
                        Center(
                          child: Text(
                            '$d알',
                            style: renewalStyle(
                              22,
                              FontWeight.w600,
                              RenewalColors.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 12시간제 시 표시: 12, 1, 2, 3 ... 11
  static const _hourLabels = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

  void _showTimePicker() {
    int amPmIndex = 0; // 0=오전, 1=오후
    int hourIndex = 9; // 기본 오전 9시 (_hourLabels[9] = 9)
    int minuteIndex = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        '복용 시간',
                        style: renewalStyle(
                          17,
                          FontWeight.w800,
                          RenewalColors.ink,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          '취소',
                          style: renewalStyle(
                            15,
                            FontWeight.w700,
                            RenewalColors.faint,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // 12시간제 -> 24시간제 변환
                          final displayHour =
                              _hourLabels[hourIndex]; // 12,1,2...11
                          int h;
                          if (amPmIndex == 0) {
                            // 오전: 12->0, 1->1, ... 11->11
                            h = displayHour == 12 ? 0 : displayHour;
                          } else {
                            // 오후: 12->12, 1->13, ... 11->23
                            h = displayHour == 12 ? 12 : displayHour + 12;
                          }
                          final min = minuteIndex * 5;
                          final duplicate = _times.any(
                            (t) => t.hour == h && t.minute == min,
                          );
                          if (duplicate) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('이미 등록된 시간입니다.')),
                            );
                            return;
                          }
                          setState(() {
                            _times.add(DoseTime(hour: h, minute: min));
                            _times.sort(
                              (a, b) => (a.hour * 60 + a.minute).compareTo(
                                b.hour * 60 + b.minute,
                              ),
                            );
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          '추가',
                          style: renewalStyle(
                            15,
                            FontWeight.w800,
                            RenewalColors.greenDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: amPmIndex,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (i) => amPmIndex = i,
                          children: [
                            Center(
                              child: Text(
                                '오전',
                                style: renewalStyle(
                                  18,
                                  FontWeight.w600,
                                  RenewalColors.ink,
                                ),
                              ),
                            ),
                            Center(
                              child: Text(
                                '오후',
                                style: renewalStyle(
                                  18,
                                  FontWeight.w600,
                                  RenewalColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: hourIndex,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (i) => hourIndex = i,
                          children: [
                            for (final h in _hourLabels)
                              Center(
                                child: Text(
                                  '$h시',
                                  style: renewalStyle(
                                    18,
                                    FontWeight.w600,
                                    RenewalColors.ink,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: minuteIndex,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (i) => minuteIndex = i,
                          children: [
                            for (int m = 0; m < 60; m += 5)
                              Center(
                                child: Text(
                                  '${m.toString().padLeft(2, '0')}분',
                                  style: renewalStyle(
                                    18,
                                    FontWeight.w600,
                                    RenewalColors.ink,
                                  ),
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
        );
      },
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_dosage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('복용량을 추가해 주세요.')));
      return;
    }
    if (_times.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('복용 시간을 1개 이상 추가해 주세요.')));
      return;
    }
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('복용 요일을 1개 이상 선택해 주세요.')));
      return;
    }

    final weekdays = _weekdays.toList()..sort();

    setState(() => _isSaving = true);
    try {
      final box = Hive.box<Medicine>(medicineBoxName);
      final existing = widget.medicine;
      if (existing == null) {
        final medicine = Medicine(
          name: _nameCtrl.text.trim(),
          dosage: _dosage!,
          times: _times,
          memo: '',
          createdAt: DateTime.now(),
          weekdays: weekdays,
        );
        await box.add(medicine);
      } else {
        existing
          ..name = _nameCtrl.text.trim()
          ..dosage = _dosage!
          ..times = _times
          ..weekdays = weekdays;
        await existing.save();
      }
      // 저장이 끝난 뒤 기기 알림을 약 목록과 다시 맞춘다. 화면은 기다리지 않는다 —
      // 알림 쪽이 늦거나 실패해도 저장은 끝났고, 다음에 앱을 켤 때 다시 맞춰진다.
      // (T-261110-023)
      unawaited(NotificationService.syncAll(box.values));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '약 삭제',
          style: renewalStyle(20, FontWeight.w800, RenewalColors.ink),
        ),
        content: Text(
          '"${widget.medicine!.name}"을(를) 삭제할까요?\n삭제한 약은 휴지통에서 30일간 복원할 수 있어요.',
          style: renewalStyle(15, FontWeight.w500, RenewalColors.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '취소',
              style: renewalStyle(15, FontWeight.w700, RenewalColors.faint),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    // 휴지통으로 이동(소프트 삭제) — 알림은 약 목록대로 다시 맞춘다(휴지통 약은
    // 빠진다). 복원하면 다시 걸린다. (T-260614-12, T-261110-023)
    widget.medicine!.deletedAt = DateTime.now();
    await widget.medicine!.save();
    unawaited(
      NotificationService.syncAll(Hive.box<Medicine>(medicineBoxName).values),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: RenewalColors.page,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
            child: _EditBackdrop(),
          ),
          Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(20, top + 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          title: widget.isEditing ? '약 수정' : '약 등록',
                          onClose: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(height: 10),
                        _NameCard(controller: _nameCtrl),
                        const SizedBox(height: 10),
                        _SectionCard(
                          title: '복용량',
                          trailing: _AddPillButton(
                            semanticsLabel: '복용량 추가',
                            onTap: _showDosagePicker,
                          ),
                          child: _dosage == null
                              ? _EmptyPlaceholder(
                                  text: '복용량 추가하기',
                                  onTap: _showDosagePicker,
                                )
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: _ValueChip(
                                    label: _dosage!,
                                    onDeleted: () =>
                                        setState(() => _dosage = null),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 10),
                        _SectionCard(
                          title: '복용 시간',
                          trailing: _AddPillButton(
                            semanticsLabel: '복용 시간 추가',
                            onTap: _showTimePicker,
                          ),
                          child: _times.isEmpty
                              ? _EmptyPlaceholder(
                                  text: '복용 시간 추가하기',
                                  onTap: _showTimePicker,
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (int i = 0; i < _times.length; i++)
                                          _ValueChip(
                                            label: _times[i].format(),
                                            icon: Icons.schedule_rounded,
                                            onDeleted: () => setState(
                                              () => _times.removeAt(i),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const _AlarmNote(),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 10),
                        _SectionCard(
                          title: '복용 요일',
                          trailing: _AllDaysToggle(
                            allSelected: _weekdays.length == 7,
                            onTap: () {
                              setState(() {
                                if (_weekdays.length == 7) {
                                  // 매일 → 평일(월~금)로 빠른 전환(전체 해제 시 저장 불가라 평일로).
                                  _weekdays
                                    ..clear()
                                    ..addAll([1, 2, 3, 4, 5]);
                                } else {
                                  _weekdays
                                    ..clear()
                                    ..addAll(Medicine.allWeekdays);
                                }
                              });
                            },
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = ((constraints.maxWidth - 36) / 7)
                                      .clamp(30.0, 40.0);
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      for (int wd = 1; wd <= 7; wd++)
                                        _WeekdayChip(
                                          label: _weekdayLabels[wd - 1],
                                          selected: _weekdays.contains(wd),
                                          size: size,
                                          onTap: () {
                                            setState(() {
                                              if (_weekdays.contains(wd)) {
                                                _weekdays.remove(wd);
                                              } else {
                                                _weekdays.add(wd);
                                              }
                                            });
                                          },
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _weekdays.length == 7
                                    ? '매일 알림을 받아요'
                                    : _weekdays.isEmpty
                                    ? '요일을 1개 이상 선택해 주세요'
                                    : '선택한 요일에만 알림을 받아요',
                                style: renewalStyle(
                                  12,
                                  FontWeight.w600,
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
              ),
              _SaveBar(
                busy: _isSaving,
                onSave: _isSaving ? null : _save,
                onDelete: widget.isEditing ? _delete : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Tooltip(
              message: '취소',
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: RenewalColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: renewalStyle(28, FontWeight.w800, RenewalColors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '이름과 먹는 시간을 정해 주세요',
          style: renewalStyle(15, FontWeight.w600, RenewalColors.body),
        ),
      ],
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: renewalCardDecoration(
        radius: RenewalRadius.nowCard,
        shadows: renewalNowShadows,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '약 이름',
                    style: renewalStyle(
                      13,
                      FontWeight.w700,
                      RenewalColors.greenDeep,
                    ),
                  ),
                  TextFormField(
                    controller: controller,
                    maxLines: 2,
                    minLines: 1,
                    textInputAction: TextInputAction.done,
                    style: renewalStyle(
                      26,
                      FontWeight.w800,
                      RenewalColors.ink,
                      height: 1.2,
                    ),
                    cursorColor: RenewalColors.green,
                    decoration: InputDecoration(
                      hintText: '예: 비타민 D, 혈압약',
                      hintStyle: renewalStyle(
                        20,
                        FontWeight.w700,
                        RenewalColors.hush,
                        height: 1.2,
                      ),
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      errorStyle: renewalStyle(
                        13,
                        FontWeight.w600,
                        AppColors.danger,
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final typed = value.text.trim();
                final look = typed.isEmpty
                    ? PillLook.mascot
                    : lookForMedicineName(typed);
                return Container(
                  width: 76,
                  height: 76,
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
                  child: PillGlyph(
                    look: look,
                    size: 54,
                    face: typed.isEmpty,
                    shadow: true,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: renewalCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: renewalStyle(16, FontWeight.w800, RenewalColors.ink),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.label,
    required this.onDeleted,
    this.icon = Icons.medication_rounded,
  });

  final String label;
  final VoidCallback onDeleted;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: RenewalColors.greenDeep),
      label: Text(
        label,
        style: renewalStyle(14, FontWeight.w700, RenewalColors.ink),
      ),
      deleteIcon: const Icon(
        Icons.close_rounded,
        size: 18,
        color: RenewalColors.faint,
      ),
      onDeleted: onDeleted,
      backgroundColor: RenewalColors.fill,
      side: BorderSide.none,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final double size;
  final VoidCallback onTap;
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label요일 선택',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? RenewalColors.green : RenewalColors.fill,
                border: selected ? null : Border.all(color: RenewalColors.ring),
              ),
              child: Center(
                child: Text(
                  label,
                  style: renewalStyle(
                    14,
                    FontWeight.w800,
                    selected ? Colors.white : RenewalColors.body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDaysToggle extends StatelessWidget {
  final bool allSelected;
  final VoidCallback onTap;
  const _AllDaysToggle({required this.allSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RenewalColors.green50,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            allSelected ? '매일' : '매일 선택',
            style: renewalStyle(13, FontWeight.w700, RenewalColors.greenDeep),
          ),
        ),
      ),
    );
  }
}

class _AddPillButton extends StatelessWidget {
  final String semanticsLabel;
  final VoidCallback onTap;
  const _AddPillButton({required this.semanticsLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: RenewalColors.green50,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: RenewalColors.greenDeep,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '추가',
                    style: renewalStyle(
                      13,
                      FontWeight.w700,
                      RenewalColors.greenDeep,
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

class _EmptyPlaceholder extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _EmptyPlaceholder({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RenewalColors.green50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_rounded,
                size: 18,
                color: RenewalColors.greenDeep,
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: renewalStyle(
                  15,
                  FontWeight.w700,
                  RenewalColors.greenDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.busy, required this.onSave, this.onDelete});

  final bool busy;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RenewalColors.page,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SaveButton(busy: busy, onTap: onSave),
              if (onDelete != null)
                TextButton(
                  onPressed: onDelete,
                  child: Text(
                    '삭제',
                    style: renewalStyle(15, FontWeight.w700, AppColors.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RenewalRadius.button),
        child: Ink(
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
              if (busy) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '저장',
                style: renewalStyle(18, FontWeight.w700, Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditBackdrop extends StatelessWidget {
  const _EditBackdrop();

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
          top: -120,
          right: -90,
          child: _Blob(size: 280, color: RenewalColors.blobRight),
        ),
        Positioned(
          top: 36,
          left: -130,
          child: _Blob(size: 240, color: RenewalColors.blobLeft),
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

/// 복용 시간 아래 알림 안내. 기기에서 알림이 꺼져 있으면 발송된다고 말하지 않는다.
/// (T-261110-026)
class _AlarmNote extends StatelessWidget {
  const _AlarmNote();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: NotificationService.enabled,
      builder: (context, enabled, _) {
        final off = enabled == false;
        final color = off ? AppColors.danger : RenewalColors.faint;
        return Row(
          children: [
            Icon(
              off
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_none_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                off ? '알림이 꺼져 있어요. 홈에서 알림을 켜 주세요' : '설정된 시간에 푸시 알림이 발송됩니다',
                style: renewalStyle(12, FontWeight.w600, color),
              ),
            ),
          ],
        );
      },
    );
  }
}
