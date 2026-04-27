/// (c) 2018 Daniel Galasko
/// Ref: https://medium.com/over-engineering/monitoring-a-folder-for-changes-in-ios-dc3f8614f902
/// Modified from FolderMonitor for use with a single file.
import Foundation

public class FileMonitor {
  // MARK: Properties

  /// A file descriptor for the monitored file.
  private var monitoredFileFD: CInt = -1
  /// A dispatch queue used for sending file changes in the file.
  private let fileMonitorQueue = DispatchQueue(label: "com.iina.FileMonitorQueue", attributes: .concurrent)
  /// A dispatch source to monitor a file descriptor created from the file.
  private var monitorSource: DispatchSourceFileSystemObject?
  /// URL for the file being monitored.
  public let url: URL

  public var fileDidChange: (() -> Void)?

  // MARK: Initializers

  public init(url: URL) {
    self.url = url
  }

  // MARK: Monitoring

  /// Listen for changes to the file (if we are not already).
  public func startMonitoring() {
    guard monitorSource == nil, monitoredFileFD == -1 else {
      return
    }
    // Open the file referenced by URL for monitoring only.
    monitoredFileFD = open(url.path, O_EVTONLY)
    // Define a dispatch source monitoring the file for additions, deletions, and renamings.
    monitorSource = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: monitoredFileFD, eventMask: .all, queue: fileMonitorQueue
    )
    // Define the block to call when a file change is detected.
    monitorSource?.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.fileDidChange?()
    }
    // Define a cancel handler to ensure the file is closed when the source is cancelled.
    monitorSource?.setCancelHandler { [weak self] in
      guard let self = self else { return }
      close(self.monitoredFileFD)
      self.monitoredFileFD = -1
      self.monitorSource = nil
    }
    // Start monitoring the file via the source.
    monitorSource?.resume()
  }

  /// Stop listening for changes to the file, if the source has been created.
  public func stopMonitoring() {
    monitorSource?.cancel()
  }
}
