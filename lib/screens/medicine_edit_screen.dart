import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/notification_service.dart';

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
  bool _isSaving = false;

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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _dosage = '${_dosageOptions[tempIndex]}알');
                          Navigator.pop(ctx);
                        },
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(initialItem: tempIndex),
                    itemExtent: 44,
                    onSelectedItemChanged: (i) => tempIndex = i,
                    children: [
                      for (final d in _dosageOptions)
                        Center(
                          child: Text(
                            '$d알',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
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
    int amPmIndex = 0;  // 0=오전, 1=오후
    int hourIndex = 9;  // 기본 오전 9시 (_hourLabels[9] = 9)
    int minuteIndex = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () {
                          // 12시간제 -> 24시간제 변환
                          final displayHour = _hourLabels[hourIndex]; // 12,1,2...11
                          int h;
                          if (amPmIndex == 0) {
                            // 오전: 12->0, 1->1, ... 11->11
                            h = displayHour == 12 ? 0 : displayHour;
                          } else {
                            // 오후: 12->12, 1->13, ... 11->23
                            h = displayHour == 12 ? 12 : displayHour + 12;
                          }
                          final min = minuteIndex * 5;
                          final duplicate = _times.any((t) => t.hour == h && t.minute == min);
                          if (duplicate) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('이미 등록된 시간입니다.')),
                            );
                            return;
                          }
                          setState(() {
                            _times.add(DoseTime(hour: h, minute: min));
                            _times.sort((a, b) =>
                                (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('추가'),
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
                          scrollController: FixedExtentScrollController(initialItem: amPmIndex),
                          itemExtent: 40,
                          onSelectedItemChanged: (i) => amPmIndex = i,
                          children: const [
                            Center(child: Text('오전', style: TextStyle(fontSize: 18))),
                            Center(child: Text('오후', style: TextStyle(fontSize: 18))),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: hourIndex),
                          itemExtent: 40,
                          onSelectedItemChanged: (i) => hourIndex = i,
                          children: [
                            for (final h in _hourLabels)
                              Center(child: Text('$h시', style: const TextStyle(fontSize: 18))),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: minuteIndex),
                          itemExtent: 40,
                          onSelectedItemChanged: (i) => minuteIndex = i,
                          children: [
                            for (int m = 0; m < 60; m += 5)
                              Center(child: Text('${m.toString().padLeft(2, '0')}분', style: const TextStyle(fontSize: 18))),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복용량을 추가해 주세요.')),
      );
      return;
    }
    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복용 시간을 1개 이상 추가해 주세요.')),
      );
      return;
    }

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
        );
        await box.add(medicine);
        NotificationService.scheduleForMedicine(medicine);
      } else {
        existing
          ..name = _nameCtrl.text.trim()
          ..dosage = _dosage!
          ..times = _times;
        await existing.save();
        NotificationService.scheduleForMedicine(existing);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('약 삭제'),
        content: Text('"${widget.medicine!.name}"을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
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
    NotificationService.cancelForMedicine(widget.medicine!);
    await widget.medicine!.delete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '약 수정' : '약 등록'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: '삭제',
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: const Text(
                '저장',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFC107),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // 약 이름
            const _SectionLabel(label: '약 이름'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: '약 이름을 입력하세요',
                prefixIcon: Icon(Icons.medication_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null,
            ),

            const SizedBox(height: 24),

            // 복용량 섹션 (복용시간과 동일 레이아웃)
            Row(
              children: [
                const _SectionLabel(label: '복용량'),
                const Spacer(),
                GestureDetector(
                  onTap: _showDosagePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: Color(0xFFFFC107)),
                        SizedBox(width: 4),
                        Text(
                          '추가',
                          style: TextStyle(
                            color: Color(0xFFFFC107),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_dosage == null)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '복용량을 추가해 주세요',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(
                    Icons.medical_services_rounded,
                    size: 18,
                    color: Color(0xFFFFC107),
                  ),
                  label: Text(
                    _dosage!,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => setState(() => _dosage = null),
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // 복용 시간 섹션
            Row(
              children: [
                const _SectionLabel(label: '복용 시간'),
                const Spacer(),
                GestureDetector(
                  onTap: _showTimePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: Color(0xFFFFC107)),
                        SizedBox(width: 4),
                        Text(
                          '추가',
                          style: TextStyle(
                            color: Color(0xFFFFC107),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_times.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '시간을 추가해 주세요',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _times.length; i++)
                        Chip(
                          avatar: const Icon(
                            Icons.notifications_active_rounded,
                            size: 18,
                            color: Color(0xFFFFC107),
                          ),
                          label: Text(
                            _times[i].format(),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => setState(() => _times.removeAt(i)),
                          backgroundColor: theme.colorScheme.surfaceContainerHigh,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.notifications_outlined, size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        '설정된 시간에 푸시 알림이 발송됩니다',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFC107),
          ),
    );
  }
}
