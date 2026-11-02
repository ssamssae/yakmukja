import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/renewal_theme.dart';
import '../widgets/renewal_page.dart';

/// 휴지통 — 삭제한 약(deletedAt != null)을 모아 복원/영구삭제한다.
/// 30일 지난 항목은 앱 시작 시 자동 영구삭제된다. (T-260614-12)
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          title,
          style: renewalStyle(20, FontWeight.w800, RenewalColors.ink),
        ),
        content: Text(
          message,
          style: renewalStyle(
            15,
            FontWeight.w500,
            RenewalColors.body,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '취소',
              style: renewalStyle(15, FontWeight.w700, RenewalColors.faint),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              confirmLabel,
              style: renewalStyle(15, FontWeight.w700, Colors.white),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restore(BuildContext context, Medicine m) async {
    m.deletedAt = null;
    await m.save();
    await NotificationService.scheduleForMedicine(m);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${m.name}"을(를) 복원했어요')));
    }
  }

  Future<void> _deleteForever(BuildContext context, Medicine m) async {
    final ok = await _confirm(
      context,
      title: '영구 삭제',
      message: '"${m.name}"을(를) 완전히 삭제할까요?\n복원할 수 없어요.',
      confirmLabel: '삭제',
    );
    if (ok) await m.delete();
  }

  Future<void> _emptyAll(BuildContext context, List<Medicine> trashed) async {
    final ok = await _confirm(
      context,
      title: '휴지통 비우기',
      message: '휴지통의 약 ${trashed.length}개를 완전히 삭제할까요?\n복원할 수 없어요.',
      confirmLabel: '비우기',
    );
    if (ok) {
      for (final m in List<Medicine>.from(trashed)) {
        await m.delete();
      }
    }
  }

  String _purgeLabel(Medicine m) {
    final days = m.timeUntilPurge.inDays;
    if (days <= 0) return '곧 영구삭제';
    return '$days일 후 영구삭제';
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Medicine>(medicineBoxName);
    return ValueListenableBuilder<Box<Medicine>>(
      valueListenable: box.listenable(),
      builder: (context, box, _) {
        final trashed = box.values.where((m) => m.deletedAt != null).toList()
          ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
        return RenewalPage(
          title: '휴지통',
          subtitle: '삭제한 약은 30일간 보관돼요',
          onBack: () => Navigator.maybePop(context),
          children: [
            if (trashed.isEmpty)
              const _EmptyTrash()
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '삭제한 약은 30일간 보관 후 자동으로 영구삭제돼요.',
                      style: renewalStyle(
                        13,
                        FontWeight.w600,
                        RenewalColors.faint,
                        height: 1.4,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _emptyAll(context, trashed),
                    child: Text(
                      '비우기',
                      style: renewalStyle(
                        15,
                        FontWeight.w700,
                        AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < trashed.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _TrashCard(
                  medicine: trashed[i],
                  purgeLabel: _purgeLabel(trashed[i]),
                  onRestore: () => _restore(context, trashed[i]),
                  onDelete: () => _deleteForever(context, trashed[i]),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({
    required this.medicine,
    required this.purgeLabel,
    required this.onRestore,
    required this.onDelete,
  });

  final Medicine medicine;
  final String purgeLabel;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: renewalCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              medicine.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: renewalStyle(18, FontWeight.w800, RenewalColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              purgeLabel,
              style: renewalStyle(13, FontWeight.w600, RenewalColors.faint),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniButton(
                    label: '복원',
                    foreground: RenewalColors.greenDeep,
                    background: RenewalColors.green50,
                    onTap: onRestore,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniButton(
                    label: '삭제',
                    foreground: AppColors.danger,
                    background: const Color(0xFFFFEEEE),
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            label,
            style: renewalStyle(15, FontWeight.w700, foreground),
          ),
        ),
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: renewalCardDecoration(
        radius: RenewalRadius.nowCard,
        shadows: renewalNowShadows,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 36, 22, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: RenewalColors.green50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 34,
                color: RenewalColors.greenDeep,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '휴지통이 비어있어요',
              style: renewalStyle(20, FontWeight.w800, RenewalColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '삭제한 약은 30일간 보관돼요',
              style: renewalStyle(14, FontWeight.w600, RenewalColors.faint),
            ),
          ],
        ),
      ),
    );
  }
}
