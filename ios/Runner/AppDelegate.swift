import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var icloudBackup: YakmukjaICloudBackup?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "YakmukjaICloudBackup") {
      icloudBackup = YakmukjaICloudBackup(messenger: registrar.messenger())
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// 로그인 없는 iCloud 백업 (T-261116-043, 한줄일기 T-261116-040 과 같은 구조).
///
/// 이 기기에 로그인된 Apple 계정의 iCloud Drive 앱 폴더
/// (컨테이너 iCloud.com.ssamssae.yakmukja 의 Documents)에 백업 파일을 둔다.
/// Dart 쪽 = lib/services/icloud_medicine_backup.dart (채널 yakmukja/icloud_backup).
final class YakmukjaICloudBackup {
  static let containerId = "iCloud.com.ssamssae.yakmukja"

  private enum BackupError: Error {
    case unavailable
    case downloadTimeout
    case readFailed
  }

  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "yakmukja.icloud.backup", qos: .userInitiated)
  private var query: NSMetadataQuery?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yakmukja/icloud_backup", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "failed", message: "gone", details: nil))
        return
      }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status":
      queue.async {
        let available = self.documentsURL() != nil
        DispatchQueue.main.async { result(["available": available]) }
      }
    case "save":
      guard let name = args["name"] as? String, Self.isBackupName(name),
        let data = (args["bytes"] as? FlutterStandardTypedData)?.data
      else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      run(result) { dir in
        try self.coordinatedWrite(data, to: dir.appendingPathComponent(name))
        return nil
      }
    case "read":
      guard let name = args["name"] as? String, Self.isBackupName(name) else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      run(result) { dir in
        let url = dir.appendingPathComponent(name)
        try self.ensureDownloaded(url)
        return FlutterStandardTypedData(bytes: try self.coordinatedRead(url))
      }
    case "delete":
      guard let name = args["name"] as? String, Self.isBackupName(name) else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      run(result) { dir in
        try self.coordinatedDelete(dir.appendingPathComponent(name))
        return nil
      }
    case "list":
      queue.async {
        guard self.documentsURL() != nil else {
          DispatchQueue.main.async { result(Self.flutterError(BackupError.unavailable)) }
          return
        }
        DispatchQueue.main.async { self.gather(result: result) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 파일 작업은 백그라운드 줄에서 하고 결과만 메인 줄로 돌려준다.
  private func run(_ result: @escaping FlutterResult, _ work: @escaping (URL) throws -> Any?) {
    queue.async {
      do {
        guard let dir = self.documentsURL() else { throw BackupError.unavailable }
        let value = try work(dir)
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async { result(Self.flutterError(error)) }
      }
    }
  }

  /// iCloud 에 로그인돼 있지 않거나 iCloud Drive 가 꺼져 있으면 nil.
  /// url(forUbiquityContainerIdentifier:) 는 오래 걸릴 수 있어 메인 줄에서 부르지 않는다.
  private func documentsURL() -> URL? {
    let manager = FileManager.default
    guard manager.ubiquityIdentityToken != nil,
      let root = manager.url(forUbiquityContainerIdentifier: Self.containerId)
    else { return nil }
    let docs = root.appendingPathComponent("Documents", isDirectory: true)
    if !manager.fileExists(atPath: docs.path) {
      try? manager.createDirectory(at: docs, withIntermediateDirectories: true)
    }
    return docs
  }

  private static func isBackupName(_ name: String) -> Bool {
    name.hasPrefix("yakmukja-backup-") && name.hasSuffix(".json")
      && !name.contains("/") && !name.contains("..")
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    if case BackupError.unavailable = error {
      return FlutterError(code: "unavailable", message: "iCloud unavailable", details: nil)
    }
    return FlutterError(code: "failed", message: String(describing: error), details: nil)
  }

  private func coordinatedWrite(_ data: Data, to url: URL) throws {
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) { target in
      do { try data.write(to: target, options: .atomic) } catch { writeError = error }
    }
    if let error = coordinationError ?? writeError { throw error }
  }

  private func coordinatedRead(_ url: URL) throws -> Data {
    var coordinationError: NSError?
    var output: Result<Data, Error> = .failure(BackupError.readFailed)
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: [], error: &coordinationError
    ) { target in
      output = Result { try Data(contentsOf: target) }
    }
    if let error = coordinationError { throw error }
    return try output.get()
  }

  private func coordinatedDelete(_ url: URL) throws {
    var coordinationError: NSError?
    var deleteError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forDeleting, error: &coordinationError
    ) { target in
      do { try FileManager.default.removeItem(at: target) } catch { deleteError = error }
    }
    if let error = coordinationError ?? deleteError { throw error }
  }

  /// 새 기기에서는 백업이 아직 내려받아지지 않았을 수 있다. 받기를 시작하고 끝날 때까지 기다린다.
  private func ensureDownloaded(_ url: URL) throws {
    func status() -> URLUbiquitousItemDownloadingStatus? {
      var fresh = url
      fresh.removeAllCachedResourceValues()
      return try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        .ubiquitousItemDownloadingStatus
    }
    let current = status()
    if current == .current { return }
    if current == nil && FileManager.default.fileExists(atPath: url.path) { return }
    try FileManager.default.startDownloadingUbiquitousItem(at: url)
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
      if status() == .current { return }
      Thread.sleep(forTimeInterval: 0.5)
    }
    throw BackupError.downloadTimeout
  }

  /// 아직 내려받지 않은 파일까지 보이도록 NSMetadataQuery 로 목록을 모은다(메인 줄).
  private func gather(result: @escaping FlutterResult) {
    let metadataQuery = NSMetadataQuery()
    metadataQuery.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    metadataQuery.predicate = NSPredicate(
      format: "%K LIKE %@", NSMetadataItemFSNameKey, "yakmukja-backup-*.json")
    var observer: NSObjectProtocol?
    var finished = false
    let finish = { [weak self] in
      guard !finished else { return }
      finished = true
      metadataQuery.disableUpdates()
      metadataQuery.stop()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      let items: [[String: Any]] = metadataQuery.results.compactMap { raw in
        guard let item = raw as? NSMetadataItem,
          let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String
        else { return nil }
        let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
        let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber
        return [
          "name": name,
          "modified": Int((date?.timeIntervalSince1970 ?? 0) * 1000),
          "size": size?.intValue ?? 0,
        ]
      }
      self?.query = nil
      result(items)
    }
    observer = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering, object: metadataQuery, queue: .main
    ) { _ in finish() }
    query = metadataQuery
    if !metadataQuery.start() {
      finish()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish() }
  }
}
