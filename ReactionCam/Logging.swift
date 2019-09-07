import Crashlytics
import FBSDKCoreKit
import Foundation

class Logging {
    static let instance = Logging()

    static func danger(_ eventName: String, _ props: [String: Any]? = nil) {
        Logging.instance.log(eventName, class: .danger, props)
    }

    static func debug(_ eventName: String, _ props: [String: Any]? = nil) {
        Logging.instance.log(eventName, class: .debug, props)
    }

    static func info(_ eventName: String, _ props: [String: Any]? = nil) {
        Logging.instance.log(eventName, class: .info, props)
    }

    static func log(_ eventName: String, _ props: [String: Any]? = nil) {
        Logging.instance.log(eventName, props)
    }

    static func success(_ eventName: String, _ props: [String: Any]? = nil) {
        Logging.instance.log(eventName, class: .success, props)
    }

    static func warning(_ eventName: String, _ props: [String: Any]? = nil) {
        Logging.instance.log(eventName, class: .warning, props)
    }

    deinit {
        self.timer?.invalidate()
        self.queue.sync {
            self.flush(force: true)
        }
    }

    func log(_ eventName: String, class cls: EventClass = .normal, _ props: [String: Any]? = nil) {
        #if DEBUG
            print("\(eventName): \(props ?? [:])")
        #else
            if let props = props {
                Answers.logCustomEvent(withName: eventName, customAttributes: self.sanitize(props, supportsBool: false))
                FBSDKAppEvents.logEvent(eventName, parameters: self.sanitize(props))
            } else {
                Answers.logCustomEvent(withName: eventName)
                FBSDKAppEvents.logEvent(eventName)
            }
        #endif
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        self.queue.async {
            let prefixText = "\(timestamp)\t\(eventName)\t\(cls.rawValue)\t"
            guard let prefix = prefixText.data(using: .utf8) else {
                NSLog("%@", "WARNING: Failed to convert string to UTF-8 data")
                return
            }
            let json: Data
            do {
                json = try JSONSerialization.data(
                    withJSONObject: props.flatMap { self.sanitize($0) } ?? [:],
                    options: [])
            } catch {
                NSLog("%@", "WARNING: Failed to convert data to JSON (\(error))")
                return
            }
            var line = Data()
            line.append(prefix)
            line.append(json)
            line.append(contentsOf: [10])
            if self.currentFile == nil {
                self.setNewLogFile()
            }
            if let file = self.currentFile {
                do {
                    // Don't use fh.write(...) because it can't handle errors.
                    try file.handle.writeThrows(line)
                    try file.handle.synchronizeFileThrows()
                    self.pendingEvents += 1
                    if self.pendingEvents >= 500 {
                        self.flush(force: true)
                    }
                } catch {
                    Intent.reportBatch(events: line).perform(BackendClient.api)
                    NSLog("%@", "WARNING: Failed to write to log file (\(error))")
                }
            } else {
                Intent.reportBatch(events: line).perform(BackendClient.api)
            }
        }
    }

    // MARK: - Private

    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.Logging.Queue")

    private var currentFile: (url: URL, handle: FileHandle)?
    private var lastFlush = Date()
    private var pendingEvents = 0
    private weak var timer: Timer?
    private var workspace: URL?

    private init() {
        self.queue.async {
            var url: URL
            do {
                let fs = FileManager.default
                url = try fs.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask, appropriateFor: nil,
                                 create: true)
                url.appendPathComponent("Logging")
                try fs.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                NSLog("%@", "WARNING: Failed to set up logging workspace (\(error))")
                return
            }
            self.workspace = url
            // Flush anything that was left over from last session.
            self.flush(directory: url)
        }
        // Auto flush every 60 seconds.
        self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.queue.async {
                if let url = self.workspace {
                    // Attempt to flush remaining log files every 60 seconds.
                    self.flush(directory: url)
                }
                self.flush()
            }
        }
    }

    private func setNewLogFile() {
        // Assume this is running on the queue.
        guard var url = self.workspace else {
            NSLog("%@", "WARNING: Failed to get logging workspace")
            return
        }
        url.appendPathComponent("\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            NSLog("%@", "WARNING: Failed to get create log file \(url)")
            return
        }
        do {
            self.currentFile = (url, try FileHandle(forWritingTo: url))
        } catch {
            NSLog("%@", "WARNING: Failed to create new log file (\(error))")
        }
    }

    private func flush(directory url: URL) {
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: url.path)
        } catch {
            NSLog("%@", "WARNING: Failed to scan logging workspace (\(error))")
            return
        }
        for file in files {
            let fileURL = url.appendingPathComponent(file)
            guard fileURL != self.currentFile?.url else { continue }
            self.flush(file: fileURL)
        }
    }

    private func flush(file url: URL) {
        // Assume this is running on the queue.
        let events: Data
        do {
            events = try Data(contentsOf: url)
        } catch {
            NSLog("%@", "WARNING: Failed to read log file \(url) (\(error))")
            return
        }
        #if DEBUG
            NSLog("%@", "[Logging] Starting flush of events in \(url)")
        #endif
        Intent.reportBatch(events: events).performWithoutDispatch(BackendClient.api) {
            if let error = $0.error {
                NSLog("%@", "WARNING: Failed to report events (\(error))")
                return
            }
            do {
                try FileManager.default.removeItem(at: url)
                #if DEBUG
                    NSLog("%@", "[Logging] Successfully flushed events to backend from \(url.path)")
                #endif
            } catch {
                NSLog("%@", "WARNING: Failed to delete log file \(url) (\(error))")
            }
        }
    }

    private func flush(force: Bool = false) {
        // Assume this is running on the queue.
        let now = Date()
        guard self.pendingEvents > 0 && (force || now.timeIntervalSince(self.lastFlush) > 1) else {
            // Only flush at most once per second, unless forced.
            return
        }
        guard let file = self.currentFile else {
            return
        }
        file.handle.closeFile()
        self.currentFile = nil
        self.lastFlush = now
        self.pendingEvents = 0
        self.flush(file: file.url)
    }

    private func sanitize(_ parameters: [String: Any], supportsBool: Bool = true) -> [String: Any] {
        var params = [String: Any]()
        for (key, value) in parameters {
            switch value {
            case let v as Bool:
                if supportsBool {
                    params[key] = NSNumber(value: v)
                } else {
                    params[key] = v ? "Yes" : "No"
                }
            case let v as Double:
                if v.isFinite {
                    params[key] = NSNumber(value: v)
                } else {
                    params[key] = NSNull()
                }
            case let v as Float:
                if v.isFinite {
                    params[key] = NSNumber(value: v)
                } else {
                    params[key] = NSNull()
                }
            case let v as String:
                params[key] = v
            case let v as Int:
                params[key] = NSNumber(value: v)
            case let v as Int64:
                params[key] = NSNumber(value: v)
            default:
                params[key] = String(describing: value)
            }
        }
        return params
    }
}
