import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/medicine.dart';
import '../services/app_review_service.dart';
import '../services/backup_file_gateway.dart';
import '../services/iap_service.dart';
import '../services/icloud_medicine_backup.dart';
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
  const SettingsScreen({
    super.key,
    this.backupFiles,
    this.medicineBox,
    this.icloud,
    this.platform,
  });

  /// 시험이 공유 창·파일 고르기 대신 넣는다. 비우면 기기 구현을 쓴다.
  final BackupFileGateway? backupFiles;

  /// 시험이 약 상자 대신 넣는다. 비우면 앱 약 상자를 쓴다.
  final Box<Medicine>? medicineBox;

  /// 시험이 iCloud 통로 대신 넣는다. 비우면 기기 구현을 쓴다.
  final ICloudMedicineBackup? icloud;

  /// 시험이 기기 종류 대신 넣는다. 비우면 실제 기기 종류를 쓴다.
  final TargetPlatform? platform;

  static const String feedbackEmail = 'minusbetastudio@gmail.com';

  BackupFileGateway get _backupFiles =>
      backupFiles ?? const PlatformBackupFileGateway();

  Box<Medicine> _box() => medicineBox ?? Hive.box<Medicine>(medicineBoxName);

  ICloudMedicineBackup get _icloud => icloud ?? ICloudMedicineBackup();

  /// 아이폰·아이패드만 iCloud 백업 줄을 보여 준다 (T-261116-043).
  bool get _isIOS => (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

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

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _backupMedicines(BuildContext context) async {
    final box = _box();
    final messenger = ScaffoldMessenger.of(context);
    if (box.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('백업할 약이 없어요')));
      return;
    }
    final appVersion = await _appVersion();
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
    final Uint8List? bytes;
    try {
      bytes = await _backupFiles.pick();
    } catch (_) {
      return;
    }
    if (bytes == null || !context.mounted) return;
    await _restoreFromBytes(context, bytes);
  }

  /// 파일·iCloud 복원이 함께 쓴다: 검사 → 확인 창 → 상자 바꾸기 → 알림 다시 맞추기.
  Future<void> _restoreFromBytes(BuildContext context, Uint8List bytes) async {
    final messenger = ScaffoldMessenger.of(context);
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

  static const String _icloudUnavailableText =
      'iCloud를 쓸 수 없어요. 설정에서 Apple 계정에 로그인하고 iCloud Drive를 켜 주세요';
  static const String _icloudFetchFailedText =
      'iCloud에서 백업을 가져오지 못했어요. 인터넷 연결과 iCloud Drive를 확인해 주세요';

  Future<void> _backupToICloud(BuildContext context) async {
    final box = _box();
    final messenger = ScaffoldMessenger.of(context);
    if (box.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('백업할 약이 없어요')));
      return;
    }
    final appVersion = await _appVersion();
    final now = DateTime.now();
    final bytes = MedicineBackup.encode(
      box.values,
      now: now,
      appVersion: appVersion,
    );
    if (!context.mounted) return;
    final icloud = _icloud;
    String message;
    try {
      await _withProgress(context, 'iCloud에 백업하고 있어요', () async {
        if (!await icloud.isAvailable()) throw const _ICloudUnavailable();
        await icloud.upload(bytes, now: now);
      });
      message = 'iCloud에 백업했어요';
    } catch (error) {
      message = _isUnavailable(error)
          ? _icloudUnavailableText
          : 'iCloud에 백업하지 못했어요. 저장 공간과 iCloud Drive를 확인해 주세요';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restoreFromICloud(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final icloud = _icloud;
    final List<ICloudBackupFile> files;
    try {
      files = await _withProgress(context, 'iCloud에서 백업을 찾고 있어요', () async {
        if (!await icloud.isAvailable()) throw const _ICloudUnavailable();
        return icloud.list();
      });
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isUnavailable(error)
                ? _icloudUnavailableText
                : _icloudFetchFailedText,
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (files.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('iCloud에 약먹자 백업이 없어요')),
      );
      return;
    }
    final name = await _chooseICloudBackup(context, files);
    if (name == null || !context.mounted) return;
    final Uint8List bytes;
    try {
      bytes = await _withProgress(
        context,
        'iCloud에서 백업을 받고 있어요',
        () => icloud.download(name),
      );
    } on MedicineBackupException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isUnavailable(error)
                ? _icloudUnavailableText
                : _icloudFetchFailedText,
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await _restoreFromBytes(context, bytes);
  }

  static bool _isUnavailable(Object error) =>
      error is _ICloudUnavailable ||
      (error is PlatformException && error.code == 'unavailable');

  /// iCloud 는 처음 열 때나 새 기기에서 내려받을 때 오래 걸릴 수 있다.
  /// 그동안 닫히지 않는 안내 창을 띄워 두고, 끝나면 닫는다.
  Future<T> _withProgress<T>(
    BuildContext context,
    String message,
    Future<T> Function() task,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var showing = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    message,
                    style: renewalStyle(
                      15,
                      FontWeight.w600,
                      RenewalColors.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() => showing = false),
    );
    try {
      return await task();
    } finally {
      if (showing) navigator.pop();
    }
  }

  Future<String?> _chooseICloudBackup(
    BuildContext context,
    List<ICloudBackupFile> files,
  ) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '어느 백업으로 복원할까요?',
          style: renewalStyle(20, FontWeight.w800, RenewalColors.ink),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final file in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    file.label,
                    style: renewalStyle(16, FontWeight.w700, RenewalColors.ink),
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(file.name),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '취소',
              style: renewalStyle(15, FontWeight.w700, RenewalColors.faint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backupNotice(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        text,
        style: renewalStyle(
          13,
          FontWeight.w500,
          RenewalColors.faint,
          height: 1.45,
        ),
      ),
    );
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
        // 아이폰 기본 = 로그인 없는 iCloud, 파일은 안드로이드로 옮길 때 (T-261116-043).
        if (_isIOS) ...[
          RenewalMenuCard(
            children: [
              RenewalMenuRow(
                icon: Icons.cloud_upload_outlined,
                label: 'iCloud에 백업',
                onTap: () => _backupToICloud(context),
              ),
              RenewalMenuRow(
                icon: Icons.cloud_download_outlined,
                label: 'iCloud에서 복원',
                onTap: () => _restoreFromICloud(context),
              ),
            ],
          ),
          _backupNotice(
            '로그인 없이 이 기기의 iCloud에 약 목록과 복용 기록을 저장해요. '
            '같은 Apple 계정의 새 아이폰·아이패드에서 복원할 수 있어요. 최근 백업 5개를 보관해요.',
          ),
          const SizedBox(height: 12),
        ],
        RenewalMenuCard(
          children: [
            RenewalMenuRow(
              icon: Icons.upload_file_rounded,
              label: '파일로 백업',
              onTap: () => _backupMedicines(context),
            ),
            RenewalMenuRow(
              icon: Icons.settings_backup_restore_rounded,
              label: '파일에서 복원',
              onTap: () => _restoreMedicines(context),
            ),
          ],
        ),
        _backupNotice(
          _isIOS
              ? '안드로이드 폰으로 옮길 때는 파일로 백업해 새 폰에서 복원하세요. '
                    '백업 파일에는 약 이름과 복용 기록이 들어 있어요. 믿을 수 있는 곳에 보관해 주세요.'
              : '폰을 바꾸거나 아이폰으로 옮길 때도 이 파일로 복원하면 돼요. '
                    '백업 파일에는 약 이름과 복용 기록이 들어 있어요. 믿을 수 있는 곳에 보관해 주세요.',
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

/// iCloud 에 로그인돼 있지 않거나 iCloud Drive 가 꺼져 있다.
class _ICloudUnavailable implements Exception {
  const _ICloudUnavailable();
}
