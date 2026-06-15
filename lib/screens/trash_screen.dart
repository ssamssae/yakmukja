import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// 휴지통 — 삭제한 약(deletedAt != null)을 모아 복원/영구삭제한다.
/// 30일 지난 항목은 앱 시작 시 자동 영구삭제된다. (T-260614-12)
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  Future<void> _restore(BuildContext context, Medicine m) async {
    m.deletedAt = null;
    await m.save();
    // 복원 시 알림 다시 예약
    await NotificationService.scheduleForMedicine(m);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${m.name}"을(를) 복원했어요')),
      );
    }
  }

  Future<void> _deleteForever(BuildContext context, Medicine m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('영구 삭제'),
        content: Text('"${m.name}"을(를) 완전히 삭제할까요?\n복원할 수 없어요.'),
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
    if (ok == true) await m.delete();
  }

  Future<void> _emptyAll(BuildContext context, List<Medicine> trashed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('휴지통 비우기'),
        content: Text('휴지통의 약 ${trashed.length}개를 완전히 삭제할까요?\n복원할 수 없어요.'),
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
            child: const Text('비우기'),
          ),
        ],
      ),
    );
    if (ok == true) {
      for (final m in List<Medicine>.from(trashed)) {
        await m.delete();
      }
    }
  }

  void _showActions(BuildContext context, Medicine m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore, color: AppColors.primary),
              title: const Text('복원'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _restore(context, m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.danger),
              title: const Text('즉시 영구삭제',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _deleteForever(context, m);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _purgeLabel(Medicine m) {
    final days = m.timeUntilPurge.inDays;
    if (days <= 0) return '곧 영구삭제';
    return '$days일 후 영구삭제';
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Medicine>(medicineBoxName);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('휴지통')),
      body: ValueListenableBuilder<Box<Medicine>>(
        valueListenable: box.listenable(),
        builder: (context, box, _) {
          final trashed = box.values.where((m) => m.deletedAt != null).toList()
            ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
          if (trashed.isEmpty) return const _EmptyTrash();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '삭제한 약은 30일간 보관 후 자동으로 영구삭제돼요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _emptyAll(context, trashed),
                      child: const Text('비우기',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: trashed.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = trashed[i];
                    return Card(
                      color: AppColors.surface,
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        title: Text(
                          m.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _purgeLabel(m),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_horiz),
                          color: theme.colorScheme.outline,
                          onPressed: () => _showActions(context, m),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '휴지통이 비어있어요',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '삭제한 약은 30일간 보관돼요',
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
