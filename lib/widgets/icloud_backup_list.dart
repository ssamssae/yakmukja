import 'dart:async';

import 'package:flutter/material.dart';

import '../services/icloud_medicine_backup.dart';
import '../theme/app_theme.dart';
import '../theme/renewal_theme.dart';
import 'renewal_page.dart';

/// 아이폰 백업 칸의 iCloud 목록 (T-261117-063).
///
/// 칸이 보일 때 [ICloudMedicineBackup.list] 를 불러 최신 백업부터 그린다.
/// 줄의 복원은 고르는 창 없이 그 파일로 기존 복원 흐름을 타고,
/// 지우기는 확인 뒤에 [ICloudMedicineBackup.delete] 를 부른다.
class ICloudBackupList extends StatefulWidget {
  const ICloudBackupList({
    super.key,
    required this.icloud,
    required this.onBackup,
    required this.onRestore,
    this.listTimeout = const Duration(seconds: 15),
  });

  final ICloudMedicineBackup icloud;
  final Future<void> Function() onBackup;
  final Future<void> Function(String name) onRestore;
  final Duration listTimeout;

  @override
  State<ICloudBackupList> createState() => _ICloudBackupListState();
}

class _ICloudBackupListState extends State<ICloudBackupList> {
  bool _loading = true;
  bool _failed = false;
  bool _wasVisible = false;
  bool _acting = false;
  int _request = 0;
  List<ICloudBackupFile> _files = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible && !_wasVisible) {
      unawaited(_load());
    }
    _wasVisible = visible;
  }

  Future<void> _load() async {
    final request = ++_request;
    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final files = await widget.icloud.list().timeout(widget.listTimeout);
      if (!mounted || request != _request) return;
      final sorted = [...files]..sort((a, b) => b.name.compareTo(a.name));
      setState(() {
        _files = sorted;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _files = const [];
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _onBackup() async {
    if (_acting) return;
    _acting = true;
    try {
      await widget.onBackup();
    } catch (_) {
      // 백업 함수가 실패 안내를 띄운다. 목록은 끝난 뒤에 다시 읽는다.
    } finally {
      _acting = false;
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _delete(ICloudBackupFile file) async {
    final phrases = _BackupPhrases.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          phrases.deleteConfirm,
          style: renewalStyle(20, FontWeight.w800, RenewalColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              phrases.cancel,
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
              phrases.delete,
              style: renewalStyle(15, FontWeight.w700, Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.icloud.delete(file.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_BackupPhrases.of(context).deleteFailed)),
      );
    }
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final phrases = _BackupPhrases.of(context);
    return RenewalMenuCard(
      children: [
        RenewalMenuRow(
          icon: Icons.cloud_upload_outlined,
          label: phrases.backup,
          onTap: () => unawaited(_onBackup()),
        ),
        _body(phrases),
      ],
    );
  }

  Widget _body(_BackupPhrases phrases) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                phrases.loading,
                style: renewalStyle(15, FontWeight.w600, RenewalColors.body),
              ),
            ),
          ],
        ),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              phrases.loadFailed,
              style: renewalStyle(15, FontWeight.w600, RenewalColors.body),
            ),
            TextButton(
              onPressed: () => unawaited(_load()),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.primaryDark,
              ),
              child: Text(
                phrases.retry,
                style: renewalStyle(15, FontWeight.w700, AppColors.primaryDark),
              ),
            ),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text(
          phrases.empty,
          style: renewalStyle(15, FontWeight.w600, RenewalColors.body),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _files.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: RenewalColors.line,
            ),
          _row(phrases, _files[i]),
        ],
      ],
    );
  }

  Widget _row(_BackupPhrases phrases, ICloudBackupFile file) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final actions = Wrap(
      spacing: 0,
      children: [
        TextButton(
          onPressed: () => unawaited(widget.onRestore(file.name)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.primaryDark,
          ),
          child: Text(
            phrases.restore,
            style: renewalStyle(15, FontWeight.w700, AppColors.primaryDark),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(_delete(file)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.danger,
          ),
          child: Text(
            phrases.delete,
            style: renewalStyle(15, FontWeight.w700, AppColors.danger),
          ),
        ),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          file.label,
          style: renewalStyle(16, FontWeight.w700, RenewalColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          file.sizeLabel,
          style: renewalStyle(13, FontWeight.w600, RenewalColors.faint),
        ),
      ],
    );
    return KeyedSubtree(
      key: ValueKey('icloud-backup-${file.name}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: scale >= 1.6
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, actions],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  actions,
                ],
              ),
      ),
    );
  }
}

/// 새 백업 목록 문구. 앱 언어가 한국어면 한국어, 아니면 영어.
class _BackupPhrases {
  const _BackupPhrases.ko() : korean = true;
  const _BackupPhrases.en() : korean = false;

  factory _BackupPhrases.of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'ko' ? const _BackupPhrases.ko() : const _BackupPhrases.en();
  }

  final bool korean;

  String get backup => korean ? 'iCloud에 백업' : 'Back up to iCloud';
  String get loading => korean ? '불러오는 중' : 'Loading…';
  String get loadFailed =>
      korean ? '목록을 불러오지 못했어요' : "Couldn't load the backup list.";
  String get retry => korean ? '다시 시도' : 'Try again';
  String get empty => korean ? '아직 백업이 없어요' : 'No backups yet.';
  String get restore => korean ? '복원' : 'Restore';
  String get delete => korean ? '지우기' : 'Delete';
  String get cancel => korean ? '취소' : 'Cancel';
  String get deleteConfirm => korean
      ? '이 백업을 지울까요? 지우면 되돌릴 수 없어요.'
      : "Delete this backup? This can't be undone.";
  String get deleteFailed =>
      korean ? '백업을 지우지 못했어요' : "Couldn't delete this backup.";
}
