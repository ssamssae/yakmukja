import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/app_review_service.dart';
import '../services/backup_file_gateway.dart';
import '../services/iap_service.dart';
import '../services/medicine_backup.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/renewal_theme.dart';
import '../widgets/renewal_page.dart';
import 'history_screen.dart';
import 'policy_screen.dart';
import 'trash_screen.dart';

/// 설정 — 평가 / 피드백 / 지난 기록 / 휴지통 / 광고제거 / 구매복원 / 약관 / 개인정보.
/// 광고 제거 구매와 구매 복원 줄은 구매 후에도 남긴다. (애플 심사 3.1.1)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.backupFiles, this.medicineBox});

  /// 시험이 공유 창·파일 고르기 대신 넣는다. 비우면 기기 구현을 쓴다.
  final BackupFileGateway? backupFiles;

  /// 시험이 약 상자 대신 넣는다. 비우면 앱 약 상자를 쓴다.
  final Box<Medicine>? medicineBox;

  static const String feedbackEmail = 'minusbetastudio@gmail.com';

  BackupFileGateway get _backupFiles =>
      backupFiles ?? const PlatformBackupFileGateway();

  Box<Medicine> _box() => medicineBox ?? Hive.box<Medicine>(medicineBoxName);

  Future<void> _rate(BuildContext context) async {
    final ok = await AppReviewService.openReview();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('지금은 평가를 열 수 없어요')));
    }
  }

  Future<void> _sendFeedback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'v${info.version} (${info.buildNumber})';
    } catch (_) {}
    final device =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    final body =
        '\n\n\n--- 아래 정보는 문제 해결에 도움이 돼요 (지워도 됩니다) ---\n'
        '앱: 약먹자 $version\n'
        '기기: $device';
    final uri = Uri(
      scheme: 'mailto',
      path: feedbackEmail,
      query: _encodeQuery({'subject': '[약먹자] 피드백', 'body': body}),
    );
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('메일 앱을 열 수 없어요')));
    }
  }

  String _encodeQuery(Map<String, String> params) => params.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _buyRemoveAds(BuildContext context) async {
    final result = await IapService.buyRemoveAds();
    final msg = IapService.purchaseMessage(result);
    if (msg != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _backupMedicines(BuildContext context) async {
    final box = _box();
    final messenger = ScaffoldMessenger.of(context);
    if (box.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('백업할 약이 없어요')));
      return;
    }
    var appVersion = '';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      appVersion = '';
    }
    final now = DateTime.now();
    final bytes = MedicineBackup.encode(
      box.values,
      now: now,
      appVersion: appVersion,
    );
    try {
      await _backupFiles.share(bytes, medicineBackupFileName(now));
    } catch (_) {
      // 공유 창을 닫은 경우와 같이, 여기서는 안내를 띄우지 않는다.
    }
  }

  Future<void> _restoreMedicines(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final Uint8List? bytes;
    try {
      bytes = await _backupFiles.pick();
    } catch (_) {
      return;
    }
    if (bytes == null || !context.mounted) return;
    final MedicineBackupData data;
    try {
      data = MedicineBackup.decode(bytes);
    } on MedicineBackupException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!context.mounted) return;
    final box = _box();
    final incomingActive = data.medicines.where((m) => !m.isInTrash).length;
    final currentActive = box.values.where((m) => !m.isInTrash).length;
    final confirmed = await _confirmRestore(
      context,
      incomingActive: incomingActive,
      currentActive: currentActive,
    );
    if (!confirmed) return;
    try {
      await MedicineBackup.restore(box, data.medicines);
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('복원하지 못했어요. 약 목록은 그대로예요')),
        );
      }
      return;
    }
    unawaited(NotificationService.syncAll(box.values.toList()));
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('약 $incomingActive개를 복원했어요')),
    );
  }

  Future<bool> _confirmRestore(
    BuildContext context, {
    required int incomingActive,
    required int currentActive,
  }) async {
    final first = '백업 파일의 약 $incomingActive개로 바꿔요.';
    final message = currentActive == 0
        ? first
        : '$first 지금 등록된 약 $currentActive개는 지워져요.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '백업에서 복원할까요?',
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
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              '복원',
              style: renewalStyle(15, FontWeight.w700, Colors.white),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restorePurchases(BuildContext context) async {
    final ok = await IapService.restorePurchases();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? '구매 내역을 확인했어요.' : '스토어에 연결할 수 없어요. 잠시 후 다시 시도해주세요.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RenewalPage(
      title: '설정',
      subtitle: '구매와 기록을 여기서 관리해요',
      children: [
        const RenewalSectionLabel('앱'),
        RenewalMenuCard(
          children: [
            RenewalMenuRow(
              icon: Icons.star_rounded,
              label: '앱 평가하기',
              onTap: () => _rate(context),
            ),
            RenewalMenuRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: '피드백 보내기',
              onTap: () => _sendFeedback(context),
            ),
            RenewalMenuRow(
              icon: Icons.history_rounded,
              label: '지난 기록',
              onTap: () => _push(context, const HistoryScreen()),
            ),
            RenewalMenuRow(
              icon: Icons.delete_outline_rounded,
              label: '휴지통',
              onTap: () => _push(context, const TrashScreen()),
            ),
          ],
        ),
        const RenewalSectionLabel('백업'),
        RenewalMenuCard(
          children: [
            RenewalMenuRow(
              icon: Icons.upload_file_rounded,
              label: '약 목록 백업',
              onTap: () => _backupMedicines(context),
            ),
            RenewalMenuRow(
              icon: Icons.settings_backup_restore_rounded,
              label: '백업에서 복원',
              onTap: () => _restoreMedicines(context),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            '백업 파일에는 약 이름과 복용 기록이 들어 있어요. 믿을 수 있는 곳에 보관해 주세요.',
            style: renewalStyle(
              13,
              FontWeight.w500,
              RenewalColors.faint,
              height: 1.45,
            ),
          ),
        ),
        const RenewalSectionLabel('구매'),
        ValueListenableBuilder<bool>(
          valueListenable: IapService.adsRemoved,
          builder: (context, removed, _) {
            return RenewalMenuCard(
              children: [
                RenewalMenuRow(
                  icon: Icons.block_rounded,
                  label: '광고 제거',
                  subtitle: removed ? '이미 광고가 제거되어 있어요' : null,
                  onTap: () => _buyRemoveAds(context),
                ),
                RenewalMenuRow(
                  icon: Icons.restore_rounded,
                  label: '구매 복원',
                  onTap: () => _restorePurchases(context),
                ),
              ],
            );
          },
        ),
        const RenewalSectionLabel('안내'),
        RenewalMenuCard(
          children: [
            RenewalMenuRow(
              icon: Icons.description_outlined,
              label: '이용약관',
              onTap: () => _push(
                context,
                const PolicyScreen(
                  title: '이용약관',
                  assetPath: 'docs/legal/terms-of-service.md',
                ),
              ),
            ),
            RenewalMenuRow(
              icon: Icons.verified_user_outlined,
              label: '개인정보처리방침',
              onTap: () => _push(
                context,
                const PolicyScreen(
                  title: '개인정보처리방침',
                  assetPath: 'docs/legal/privacy-policy.md',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
