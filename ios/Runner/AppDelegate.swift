import Flutter
import UIKit

@_silgen_name("lokal_soulseek_suspend") private func suspendSoulseek()
@_silgen_name("lokal_soulseek_resume") private func resumeSoulseek()

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var lokalPlatform: LokalPlatform?
  private let transferHost = LokalTransferHost()
  private var transferBridge: LokalTransferBridge?
  #if DEBUG
  private var transferIntegrationHarness: LokalTransferIntegrationHarness?
  private var daemonProbe: LokalTransferDaemonProbe?
  #endif
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var protectedDataObserver: NSObjectProtocol?
  private var pendingDocuments: [URL] = []

  func openDocuments(_ urls: [URL]) {
    if let platform = lokalPlatform { platform.openDocuments(urls) }
    else { pendingDocuments.append(contentsOf: urls.filter { $0.isFileURL }) }
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    transferHost.start()
    #if DEBUG
    do { daemonProbe = try LokalTransferDaemonProbe(); daemonProbe?.start() }
    catch { NSLog("Isolated daemon probe configuration refused") }
    #endif
    lifecycleObservers = [
      NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
        object: nil, queue: .main) { [weak self] _ in
          suspendSoulseek()
          #if DEBUG
          DispatchQueue.main.async { self?.daemonProbe?.backgrounded() }
          #endif
        },
      NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
        object: nil, queue: .main) { _ in resumeSoulseek() },
    ]
    protectedDataObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification,
      object: nil, queue: .main) { [host = transferHost] _ in host.start() }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    #if DEBUG
    if let probe = daemonProbe, probe.identifier == identifier {
      probe.handleBackgroundEvents(completionHandler)
      return
    }
    #endif
    guard identifier == LokalTransferRuntime.sessionIdentifier else {
      super.application(application, handleEventsForBackgroundURLSession: identifier,
        completionHandler: completionHandler)
      return
    }
    // This path works before Flutter initializes; importing into the library
    // is separate from retaining files and acknowledging native OS delivery.
    transferHost.handleBackgroundEvents(completion: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    lokalPlatform = LokalPlatform(messenger: engineBridge.applicationRegistrar.messenger())
    transferBridge = LokalTransferBridge(
      messenger: engineBridge.applicationRegistrar.messenger(), host: transferHost)
    #if DEBUG
    transferIntegrationHarness = LokalTransferIntegrationHarness(
      messenger: engineBridge.applicationRegistrar.messenger())
    #endif
    lokalPlatform?.openDocuments(pendingDocuments)
    pendingDocuments = []
  }
}
