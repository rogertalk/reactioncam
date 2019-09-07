import AVFoundation
import UIKit

fileprivate let EXTENSION_DATA = "data"
fileprivate let EXTENSION_RESUME_DATA = "dataresume"
fileprivate let EXTENSION_JOB = "job"
fileprivate let EXTENSION_JSON = "json"

struct CompletedUploadJob {
    let id: String
    let bytes: Int64
    let contentType: String
    let created, started, completed: Date
    let metadata: [String: Any]
    let token: UploadToken
}

struct UploadJob {
    let id: String
    let bytes: Int64
    let contentType: String
    let created: Date

    var completed: Date?
    var metadata: [String: Any]
    var progress: Int64 = 0
    var restarts = 0
    var started: Date?
    var token: UploadToken?

    var isCompleted: Bool {
        return self.completed != nil
    }
    
    var isVisible: Bool {
        guard let tags = self.metadata["tags"] as? [String] else {
            return false
        }
        return tags.contains("reaction")
    }

    init(bytes: Int64, contentType: String, metadata: [String: Any] = [:]) {
        self.id = UUID().uuidString
        self.bytes = bytes
        self.contentType = contentType
        self.created = Date()
        self.metadata = metadata
    }

    init?(url: URL) {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let id = dict["id"] as? String,
            let bytes = dict["bytes"] as? NSNumber,
            let contentType = dict["content_type"] as? String,
            let createdUnix = dict["created"] as? NSNumber
            else
        {
            return nil
        }
        self.id = id
        self.bytes = bytes.int64Value
        self.completed = (dict["completed"] as? NSNumber).flatMap { Date(timeIntervalSince1970: $0.doubleValue) }
        self.contentType = contentType
        self.created = Date(timeIntervalSince1970: createdUnix.doubleValue)
        self.started = (dict["started"] as? NSNumber).flatMap { Date(timeIntervalSince1970: $0.doubleValue) }
        self.metadata = dict["metadata"] as? [String: Any] ?? [:]
        self.restarts = dict["restarts"] as? Int ?? 0
        if self.isCompleted {
            // A completed job is assumed to have uploaded everything.
            self.progress = self.bytes
        }
        if dict["token"] is NSNull {
            return
        }
        guard
            let tokenData = dict["token"] as? [String: Any],
            let token = UploadToken(json: tokenData)
            else { return nil }
        self.token = token
    }

    func asCompletedJob(token: UploadToken, completed: Date) -> CompletedUploadJob {
        return CompletedUploadJob(id: self.id, bytes: self.bytes, contentType: contentType,
                                  created: self.created, started: self.started ?? self.created,
                                  completed: completed, metadata: self.metadata, token: token)
    }

    func toDict() -> [String: Any] {
        return [
            "id": self.id,
            "bytes": self.bytes,
            "completed": self.completed.flatMap { NSNumber(value: $0.timeIntervalSince1970) } ?? NSNull(),
            "content_type": self.contentType,
            "created": NSNumber(value: self.created.timeIntervalSince1970),
            "started": self.started.flatMap { NSNumber(value: $0.timeIntervalSince1970) } ?? NSNull(),
            "metadata": self.metadata,
            "token": self.token?.toDict() ?? NSNull(),
        ]
    }
}

struct UploadToken {
    static let freshAge = TimeInterval(86400)
    static let usableAge = TimeInterval(3600)

    let id: String
    let url: URL
    let publicURL: URL
    let contentType: String
    let expires: Date
    let provider: String
    let isResumeSupported: Bool

    var isFresh: Bool {
        return self.expires.timeIntervalSinceNow >= UploadToken.freshAge
    }

    var isUsable: Bool {
        return self.expires.timeIntervalSinceNow >= UploadToken.usableAge
    }

    var isValid: Bool {
        return self.expires.timeIntervalSinceNow >= 0
    }

    init?(json: [String: Any]) {
        guard
            let id = json["id"] as? String,
            let urlString = json["url"] as? String,
            let url = URL(string: urlString),
            let publicURLString = json["public_url"] as? String,
            let publicURL = URL(string: publicURLString),
            let expiresUnix = json["expires"] as? NSNumber
            else { return nil }
        self.id = id
        self.url = url
        self.publicURL = publicURL
        self.contentType = (json["content_type"] as? String) ?? "video/mp4"
        self.expires = Date(timeIntervalSince1970: expiresUnix.doubleValue)
        self.provider = (json["provider"] as? String) ?? "GCS"
        self.isResumeSupported = (json["supports_resume"] as? Bool) ?? true
    }

    func isUsable(for contentType: String) -> Bool {
        return self.isUsable && self.contentType == contentType
    }

    func toDict() -> [String: Any] {
        return [
            "id": self.id,
            "url": self.url.absoluteString,
            "public_url": self.publicURL.absoluteString,
            "content_type": self.contentType,
            "expires": NSNumber(value: self.expires.timeIntervalSince1970),
            "provider": self.provider,
            "resume_supported": NSNumber(value: self.isResumeSupported),
        ]
    }
}

enum UploadServiceError: Error {
    case couldNotClaimToken
    case internalError
    case invalidFile
    case invalidSession
    case noWorkspace
}

extension UploadServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .couldNotClaimToken:
            return "There were no upload tokens available"
        case .internalError:
            return "An internal state error occurred"
        case .invalidFile:
            return "The provided URL to upload was not a valid local file"
        case .invalidSession:
            return "Attempted to upload without a valid user session"
        case .noWorkspace:
            return "Attempted to upload but there was no workspace initialized"
        }
    }
}

class UploadService {
    static let instance = UploadService()

    let backgroundEventsCompleted = Event<Void>()
    let uploadCompleted = Event<CompletedUploadJob>()
    let uploadProgress = Event<UploadJob>()
    let uploadStarted = Event2<UploadJob, UploadToken>()

    private(set) var jobs = [String: UploadJob]()
    private(set) var session: URLSession!

    func cancel(jobId: String) {
        self.queue.async {
            guard let job = self.jobs.removeValue(forKey: jobId) else {
                Logging.warning("Upload Service", [
                    "Id": jobId,
                    "Status": "Upload job cancelled but service wasn't tracking it"])
                return
            }
            self.manager.cancel(job: job)
            self.cleanUpJobData(for: job)
            self.cleanUpJobInfo(for: job)
            Logging.debug("Upload Service", [
                "Id": jobId,
                "Status": "Cancelled upload"])
        }
    }

    func finish(jobId: String) {
        self.queue.async {
            guard let job = self.jobs.removeValue(forKey: jobId) else {
                Logging.warning("Upload Service", [
                    "Id": jobId,
                    "Status": "Upload job marked finished but service wasn't tracking it"])
                return
            }
            guard job.isCompleted else {
                Logging.danger("Upload Service", [
                    "Id": jobId,
                    "Status": "Upload job marked finished but didn't have a completion timestamp"])
                return
            }
            self.cleanUpJobInfo(for: job)
            Logging.debug("Upload Service", [
                "Id": jobId,
                "Status": "Finished upload job"])
        }
    }

    func save(assetFor job: UploadJob, source: String, completion: ((String?) -> ())? = nil) {
        let dataURL = self.url(forDataOf: job)
        let mp4URL = dataURL.appendingPathExtension("mp4")
        let fs = FileManager.default
        try? fs.linkItem(at: dataURL, to: mp4URL)
        let asset = AVURLAsset(url: mp4URL)
        MediaManager.save(asset: asset, source: source) { id in
            try? fs.removeItem(at: mp4URL)
            completion?(id)
        }
    }

    @discardableResult
    func setMetadata(_ newData: [String: Any], for jobId: String) -> Bool {
        var result = false
        self.queue.sync {
            guard var job = self.jobs[jobId] else {
                return
            }
            for (key, value) in newData {
                job.metadata[key] = value
            }
            self.jobs[jobId] = job
            self.tryWrite(job: job)
            result = true
        }
        return result
    }

    func startReporting() {
        self.queue.async {
            self.isReadyToReportCompletedJobs = true
            self.pendingCompletedJobs.forEach(self.uploadCompleted.emit(_:))
            self.pendingCompletedJobs = []
        }
    }

    func upload(file url: URL, move: Bool = false, metadata: [String: Any] = [:]) throws -> UploadJob {
        guard let workspace = self.workspace else {
            throw UploadServiceError.noWorkspace
        }
        guard let session = BackendClient.api.session, session.id == self.accountId else {
            throw UploadServiceError.invalidSession
        }
        guard let fileSize = url.fileSize else {
            throw UploadServiceError.invalidFile
        }
        // TODO: Dynamic content type.
        let job = UploadJob(bytes: fileSize, contentType: "video/mp4", metadata: metadata)
        let dataURL = self.url(forDataOf: job)
        if move {
            Logging.debug("Upload Service", [
                "Bytes": fileSize,
                "Id": job.id,
                "Status": "Moving upload data to data file",
                "Path": dataURL.path])
            try FileManager.default.moveItem(at: url, to: dataURL)
        } else {
            Logging.debug("Upload Service", [
                "Bytes": fileSize,
                "Id": job.id,
                "Status": "Copying upload data to data file",
                "Path": dataURL.path])
            try FileManager.default.copyItem(at: url, to: dataURL)
        }
        self.queue.async {
            guard workspace == self.workspace else {
                Logging.danger("Upload Service", [
                    "Id": job.id,
                    "Status": "Workspace changed while creating upload job"])
                return
            }
            do {
                try self.write(job: job)
            } catch {
                Logging.danger("Upload Service", [
                    "Id": job.id,
                    "Status": "Failed to save upload job to file",
                    "Error": self.errorWithVariables(error, job: job)])
            }
            self.configure(job: job, start: true)
        }
        return job
    }

    // MARK: - Private

    private class SessionManager: NSObject, URLSessionDataDelegate {
        weak var service: UploadService?
        var tasks = [String: URLSessionUploadTask]()

        func cancel(job: UploadJob) {
            guard let task = self.tasks.removeValue(forKey: job.id) else {
                return
            }
            task.cancel()
            Logging.debug("Upload Service", [
                "Id": job.id,
                "Status": "Cancelled upload",
                "TotalBytes": job.bytes,
                "URL": job.token?.publicURL.absoluteString ?? "N/A"])
        }

        func start(task: URLSessionUploadTask) {
            // Assume we're running on service dispatch queue.
            guard let id = task.taskDescription else {
                Logging.danger("Upload Service", [
                    "Status": "Attempted to start upload task without a job id"])
                return
            }
            if let task = self.tasks[id], task.state == .running {
                Logging.danger("Upload Service", [
                    "Id": id,
                    "Status": "Encountered duplicate upload task"])
                task.cancel()
                return
            }
            self.tasks[id] = task
            task.resume()
        }

        func start(job: UploadJob) {
            // Assume we're running on service dispatch queue.
            guard let service = self.service else {
                Logging.danger("Upload Service", [
                    "Status": "UploadService was released before job could be started"])
                return
            }
            guard !job.isCompleted else {
                Logging.warning("Upload Service", ["Id": job.id, "Status": "Re-reporting job complete"])
                service.complete(jobId: job.id)
                return
            }
            if let task = self.tasks[job.id] {
                task.resume()
                return
            }
            if job.started != nil, let task = service.resumeInfoTask(for: job) {
                // Job was started previously - start request to check resume state of job.
                // TODO: Make sure that two calls to start(job:) doesn't cause two of these.
                task.resume()
                Logging.debug("Upload Service", ["Id": job.id, "Status": "Requesting resume state"])
                return
            }
            // (Re)start the job from scratch.
            guard let (task, token) = service.uploadTask(for: job) else {
                Logging.warning("Upload Service", [
                    "Id": job.id,
                    "Status": "Could not start upload job",
                    "TotalBytes": job.bytes,
                    "URL": job.token?.publicURL.absoluteString ?? "N/A"])
                return
            }
            self.start(task: task)
            service.uploadStarted.emit(job, token)
            Logging.debug("Upload Service", [
                "Id": job.id,
                "Status": "Started upload",
                "TotalBytes": job.bytes,
                "URL": token.publicURL.absoluteString])
        }

        // MARK: - URLSessionDataDelegate

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            Logging.warning("Upload Service", [
                "Status": "URL session became invalid",
                "Error": error?.localizedDescription ?? "N/A"])
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let jobId = dataTask.taskDescription else {
                return
            }
            Logging.debug("Upload Service", [
                "Id": jobId,
                "Status": "Preliminary response",
                "Code": (response as? HTTPURLResponse).flatMap({ String($0.statusCode) }) ?? "N/A"])
            completionHandler(.allow)
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            // Avoid race conditions in initialization.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.service?.backgroundEventsCompleted.emit()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let jobId = task.taskDescription else {
                Logging.danger("Upload Service", [
                    "Status": "Got completion for task without a job id"])
                return
            }
            guard let service = self.service else {
                Logging.danger("Upload Service", [
                    "Id": jobId,
                    "Status": "UploadService was released before job could be completed"])
                return
            }
            if let error = error {
                Logging.warning("Upload Service", [
                    "Id": jobId,
                    "Status": "Failed to complete upload due to error",
                    "Error": service.errorWithVariables(error, jobId: jobId)])
                // Trash the upload task.
                task.cancel()
                guard service.didHookUpTasks else {
                    return
                }
                // Run a background task which will create another upload task after a delay.
                service.runAsBackgroundTask(deadline: .now() + 5) {
                    if let task = self.tasks[jobId], task.state == .running {
                        #if DEBUG
                            NSLog("%@", "[UploadService] Ignoring restart of job \(jobId) because task is running")
                        #endif
                        return
                    }
                    if var job = service.jobs[jobId] {
                        Logging.debug("Upload Service", [
                            "Id": jobId,
                            "Status": "Restarting upload job after delay"])
                        job.started = nil
                        service.configure(job: job, start: true)
                    } else {
                        Logging.debug("Upload Service", [
                            "Id": jobId,
                            "Status": "Upload job could not be found when restarting it"])
                    }
                }
                return
            }
            guard let job = service.jobs[jobId] else {
                guard !service.didHookUpTasks else {
                    Logging.danger("Upload Service", [
                        "Id": jobId,
                        "Status": "Upload job could not be found in initialized workspace"])
                    return
                }
                Logging.debug("Upload Service", [
                    "Id": jobId,
                    "Status": "Upload job could not be found when handling service response"])
                service.runAsBackgroundTask(deadline: .now() + 1) {
                    self.urlSession(session, task: task, didCompleteWithError: nil)
                }
                return
            }
            guard let response = task.response as? HTTPURLResponse else {
                Logging.warning("Upload Service", [
                    "Status": "Upload task had no response"])
                return
            }
            if task is URLSessionUploadTask {
                self.tasks.removeValue(forKey: jobId)
            }
            switch response.statusCode {
            case 200, 201:
                service.complete(jobId: jobId)
            case 308:
                guard let range = response.allHeaderFields["Range"] as? String, range.hasPrefix("bytes=0-") else {
                    Logging.danger("Upload Service", [
                        "Id": jobId,
                        "Status": "Response did not have a valid Range header"])
                    return
                }
                guard let lastByteIndex = Int64(range.dropFirst(8)) else {
                    Logging.danger("Upload Service", [
                        "Id": jobId,
                        "Status": "Could not parse Range value"])
                    return
                }
                guard let (task, _) = service.uploadTask(for: job, resumingFrom: lastByteIndex + 1) else {
                    Logging.warning("Upload Service", [
                        "Id": job.id,
                        "Status": "Could not resume upload job",
                        "StartByte": lastByteIndex + 1])
                    return
                }
                Logging.debug("Upload Service", [
                    "Id": job.id,
                    "Status": "Resuming upload",
                    "StartByte": lastByteIndex + 1])
                self.start(task: task)
            default:
                switch response.statusCode {
                case 400, 404:
                    Logging.debug("Upload Service", [
                        "Id": job.id,
                        "Status": "Job could not resume - restarting",
                        "Code": String(response.statusCode)])
                    service.restart(job: job)
                case 403:
                    Logging.warning("Upload Service", [
                        "Id": job.id,
                        "Status": "Upload token appears to have expired - resetting job",
                        "Code": String(response.statusCode)])
                    service.restart(job: job, discardToken: true)
                default:
                    Logging.warning("Upload Service", [
                        "Id": job.id,
                        "Status": "Unexpected HTTP status code - restarting",
                        "Code": String(response.statusCode)])
                    service.restart(job: job)
                }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard task is URLSessionUploadTask, let jobId = task.taskDescription else {
                return
            }
            guard let service = self.service, var job = service.jobs[jobId] else {
                Logging.warning("Upload Service", [
                    "Id": jobId,
                    "Status": "Failed to get data for job in upload progress callback"])
                return
            }
            if job.started == nil {
                // Mark the job as started once we've sent the first bytes for it.
                job.started = Date()
                service.configure(job: job)
            }
            service.setJob(id: job.id, progress: totalBytesSent)
            #if DEBUG
                NSLog("%@", "[UploadService] Uploaded \(bytesSent) bytes (\(totalBytesSent)/\(totalBytesExpectedToSend)) for job \(job.id) (\(job.bytes) total bytes)")
            #endif
        }

        func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
            guard let jobId = task.taskDescription else {
                return
            }
            Logging.debug("Upload Service", [
                "Status": "Task is waiting for connectivity",
                "JobId": jobId])
        }
    }

    private let manager = SessionManager()
    private let operationQueue = OperationQueue()
    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.UploadService.Queue")

    private var accountId: Int64?
    private var didHookUpTasks = false
    private var isReadyToReportCompletedJobs = false
    private var isRefreshPending = false
    private var pendingCompletedJobs = [CompletedUploadJob]()
    /// No longer in use.
    private var tokens = [UploadToken]()
    private var workspace: URL?

    private init() {
        self.manager.service = self
        self.operationQueue.name = "\(self.queue.label).Operations"
        self.operationQueue.underlyingQueue = self.queue
        self.queue.sync {
            let bg = URLSessionConfiguration.background(withIdentifier: "cam.reaction.ReactionCam.UploadService.Session")
            bg.shouldUseExtendedBackgroundIdleMode = true
            self.session = URLSession(configuration: bg, delegate: self.manager, delegateQueue: self.operationQueue)
            if let session = BackendClient.api.session {
                // Initialize workspace for currently logged in user.
                self.initializeWorkspace(for: session)
            }
            BackendClient.api.loggedIn.addListener(self, method: UploadService.handleLoggedIn)
            BackendClient.api.loggedOut.addListener(self, method: UploadService.handleLoggedOut)
        }
    }

    deinit {
        self.session.finishTasksAndInvalidate()
    }
    
    private func claimToken(for contentType: String) -> UploadToken? {
        // Assume we're running on service dispatch queue.
        // Tokens disabled as we no longer upload to our own backend.
        return nil
        // TODO: Store tokens separately per content type.
        defer { self.refreshTokens() }
        while let token = self.tokens.popLast() {
            guard token.isUsable(for: contentType) else { continue }
            do {
                try self.saveToDisk()
            } catch let error as NSError {
                Logging.debug("Upload Service", [
                    "Status": "Failed to save workspace",
                    "Error": self.errorWithVariables(error, job: nil)])
                return nil
            }
            return token
        }
        Logging.warning("Upload Service", [
            "Status": "Tried to claim upload token but had none"])
        return nil
    }

    private func cleanUpJobData(for job: UploadJob) {
        let fs = FileManager.default
        let url = self.url(forDataOf: job)
        do {
            try fs.removeItem(at: url)
            Logging.debug("Upload Service", [
                "Id": job.id,
                "Status": "Deleted job data file",
                "Path": url.path])
        } catch let error as NSError {
            Logging.warning("Upload Service", [
                "Id": job.id,
                "Status": "Failed to delete job data file",
                "Path": url.path,
                "Error": self.errorWithVariables(error, job: job)])
        }
        let resumeURL = self.url(forResumeDataOf: job)
        if fs.fileExists(atPath: resumeURL.path) {
            do {
                try fs.removeItem(at: resumeURL)
                Logging.debug("Upload Service", [
                    "Id": job.id,
                    "Status": "Deleted job resume file",
                    "Path": resumeURL.path])
            } catch let error as NSError {
                Logging.warning("Upload Service", [
                    "Id": job.id,
                    "Status": "Failed to delete job resume file",
                    "Path": url.path,
                    "Error": self.errorWithVariables(error, job: job)])
            }
        }
    }

    private func cleanUpJobInfo(for job: UploadJob) {
        let url = self.url(forInfoOf: job)
        do {
            try FileManager.default.removeItem(at: url)
            Logging.debug("Upload Service", [
                "Id": job.id,
                "Status": "Deleted job metadata file",
                "Path": url.path])
        } catch let error as NSError {
            Logging.warning("Upload Service", [
                "Id": job.id,
                "Status": "Failed to delete job metadata",
                "Path": url.path,
                "Error": self.errorWithVariables(error, job: job)])
        }
    }

    private func complete(jobId: String) {
        // Assume we're running on service dispatch queue.
        guard var job = self.jobs[jobId] else {
            Logging.danger("Upload Service", [
                "Id": jobId,
                "Status": "Upload job completed but service wasn't tracking it"])
            return
        }
        guard let token = job.token else {
            Logging.danger("Upload Service", [
                "Id": job.id,
                "Status": "Failed to complete job due to missing token"])
            return
        }
        // Update the job to track completion.
        let completed: Date
        if let alreadyCompletedDate = job.completed {
            // The job has already been completed before and we're just retrying.
            completed = alreadyCompletedDate
        } else {
            completed = Date()
            job.completed = completed
            self.jobs[jobId] = job
            self.tryWrite(job: job)
            // Delete the data/resume files now that the job has been completed.
            self.cleanUpJobData(for: job)
            Logging.debug("Upload Service", [
                "Id": jobId,
                "Status": "Completed upload"])
        }
        // Notify interested parties of the successful upload.
        self.report(completedJob: job.asCompletedJob(token: token, completed: completed))
    }

    private func fail(jobId: String) {
        // Assume we're running on service dispatch queue.
        guard let job = self.jobs.removeValue(forKey: jobId) else {
            Logging.warning("Upload Service", [
                "Id": jobId,
                "Status": "Upload job failed but service wasn't tracking it"])
            return
        }
        self.cleanUpJobData(for: job)
        self.cleanUpJobInfo(for: job)
        Logging.debug("Upload Service", [
            "Id": jobId,
            "Status": "Aborted upload"])
    }

    private func configure(job: UploadJob, start: Bool = false) {
        // Assume we're running on service dispatch queue.
        var job = job
        if let storedJob = self.jobs[job.id], let storedToken = storedJob.token, storedToken.isValid {
            if let token = job.token, token.id != storedToken.id {
                Logging.danger("Upload Service", [
                    "Status": "Found job with two upload tokens",
                    "Token1": token.id,
                    "Token2": storedToken.id])
            }
            job.token = storedToken
        }
        if job.isCompleted {
            if job.token == nil {
                Logging.warning("Upload Service", [
                    "Id": job.id,
                    "Status": "Configured completed job without a token"])
            }
        } else if let token = job.token, !token.isValid {
            job.restarts = 0
            job.token = self.claimToken(for: job.contentType)
            Logging.warning("Upload Service", [
                "Id": job.id,
                "Status": "Reset upload token (token expired)"])
        } else if job.restarts >= 2 {
            job.restarts = 0
            job.token = self.claimToken(for: job.contentType)
            Logging.warning("Upload Service", [
                "Id": job.id,
                "Status": "Reset upload token (too many restarts)"])
        } else if job.token == nil {
            job.restarts = 0
            job.token = self.claimToken(for: job.contentType)
        }
        do {
            try self.write(job: job)
        } catch {
            Logging.danger("Upload Service", [
                "Id": job.id,
                "Status": "Failed to save job metadata file",
                "Error": self.errorWithVariables(error, job: job)])
        }
        self.jobs[job.id] = job
        if start && !job.isCompleted {
            self.manager.start(job: job)
        }
    }

    private func errorWithVariables(_ error: Error, job: UploadJob?) -> String {
        var text = error.localizedDescription
        if let job = job {
            text = text.replacingOccurrences(of: job.id, with: "<JOB_ID>")
            if let token = job.token {
                text = text.replacingOccurrences(of: token.id, with: "<TOKEN_ID>")
            }
        }
        if let session = BackendClient.api.session {
            text = text.replacingOccurrences(of: String(session.id), with: "<ACCOUNT_ID>")
        }
        return text
    }

    private func errorWithVariables(_ error: Error, jobId: String) -> String {
        var text = error.localizedDescription
        text = text.replacingOccurrences(of: jobId, with: "<JOB_ID>")
        if let session = BackendClient.api.session {
            text = text.replacingOccurrences(of: String(session.id), with: "<ACCOUNT_ID>")
        }
        return text
    }

    private func handleLoggedIn(session: Session) {
        self.queue.async {
            self.initializeWorkspace(for: session)
        }
    }

    private func handleLoggedOut() {
        self.queue.async {
            self.unload()
        }
    }

    private func hookUpTasks() {
        guard !self.didHookUpTasks else {
            return
        }
        // Recover jobs from the URL session.
        self.session.getTasksWithCompletionHandler() { (_, uploads, _) in
            uploads.forEach {
                guard let jobId = $0.taskDescription else {
                    Logging.warning("Upload Service", [
                        "Status": "Found in-progress background task without a job id"])
                    return
                }
                guard $0.state != .completed else {
                    return
                }
                Logging.debug("Upload Service", [
                    "Id": jobId,
                    "Status": "Hooking up background upload"])
                self.manager.start(task: $0)
            }
            self.didHookUpTasks = true
            self.jobs.values.forEach {
                self.manager.start(job: $0)
            }
            Logging.debug("Upload Service", [
                "Status": "Initialized workspace",
                "Path": self.workspace?.path ?? "N/A",
                "ActiveJobs": self.jobs.count,
                "ActiveTasks": self.manager.tasks.count,
                "UploadTokens": self.tokens.count])
        }
    }

    private func initializeWorkspace(for accountId: Int64) throws {
        // Assume we're running on service dispatch queue.
        // TODO: Only reset state if account id changed.
        if self.accountId != nil {
            self.unload()
        }
        let workspace = try self.url(forWorkspaceOf: accountId)
        let fs = FileManager.default
        try fs.createDirectory(at: workspace, withIntermediateDirectories: true)
        self.accountId = accountId
        self.workspace = workspace
        let infoURL = self.url(forWorkspaceInfoIn: workspace)
        if fs.fileExists(atPath: infoURL.path) {
            // Load workspace data such as available tokens.
            let data = try Data(contentsOf: infoURL)
            let object = try JSONSerialization.jsonObject(with: data)
            guard
                let dict = object as? [String: Any],
                let tokens = dict["tokens"] as? [[String: Any]]
                else
            {
                Logging.danger("Upload Service", [
                    "Status": "Failed to parse workspace file"])
                return
            }
            self.tokens.insert(contentsOf: tokens.compactMap(UploadToken.init), at: 0)
            if self.tokens.count < tokens.count {
                Logging.warning("Upload Service", [
                    "Status": "Ended up with fewer upload tokens than expected"])
            }
        }
        do {
            // TODO: Remove this migration.
            self.x_performMigrationFromOldVersionsInWorkspace(workspace)
            // Discover jobs in the workspace directory.
            let files = try fs.contentsOfDirectory(atPath: workspace.path)
            Logging.debug("Upload Service", [
                "Status": "Scanned workspace directory",
                "FileCount": files.count,
                "Files": files])
            for file in files {
                guard file.hasSuffix(".\(EXTENSION_JOB)") else { continue }
                guard let job = UploadJob(url: workspace.appendingPathComponent(file)) else {
                    Logging.danger("Upload Service", [
                        "File": file,
                        "Status": "Failed to parse upload job file"])
                    continue
                }
                self.configure(job: job, start: self.didHookUpTasks)
            }
        } catch {
            Logging.danger("Upload Service", [
                "Path": workspace.path,
                "Status": "Failed to list workspace directory"])
        }
        self.hookUpTasks()
    }

    private func initializeWorkspace(for session: Session) {
        // Assume we're running on service dispatch queue.
        do {
            try self.initializeWorkspace(for: session.id)
        } catch let error as NSError {
            Logging.danger("Upload Service", [
                "Status": "Failed to initialize workspace",
                "Error": self.errorWithVariables(error, job: nil)])
            return
        }
        self.refreshTokens()
    }

    private func refreshTokens() {
        // Assume we're running on service dispatch queue.
        // No more upload tokens.
        return
        guard let session = BackendClient.api.session, session.id == self.accountId else {
            Logging.danger("Upload Service", [
                "AccountId": self.accountId ?? -1,
                "SessionId": BackendClient.api.session?.id ?? -1,
                "Status": "Failed to refresh tokens due to session mismatch"])
            return
        }
        guard !self.isRefreshPending, self.tokens.filter({ $0.isFresh }).count < 10 else {
            return
        }
        self.isRefreshPending = true
        // TODO: Support multiple Content-Type.
        Intent.allocateUploadTokens(contentType: "video/mp4").performWithoutDispatch(BackendClient.upload) { result in
            self.queue.async {
                self.isRefreshPending = false
                if let error = result.error {
                    Logging.danger("Upload Service", [
                        "Status": "Failed to get new upload tokens",
                        "Error": self.errorWithVariables(error, job: nil)])
                    return
                }
                guard let data = result.data, let tokenList = data["data"] as? [[String: Any]] else {
                    Logging.danger("Upload Service", [
                        "Status": "Failed to parse new upload tokens data"])
                    return
                }
                guard let s = BackendClient.api.session, s.id == self.accountId else {
                    Logging.danger("Upload Service", [
                        "Status": "Session changed while request was in flight"])
                    return
                }
                self.tokens.insert(contentsOf: tokenList.compactMap(UploadToken.init), at: 0)
                do {
                    try self.saveToDisk()
                    Logging.debug("Upload Service", [
                        "TokenCount": self.tokens.count,
                        "Status": "Refreshed upload tokens"])
                    self.queue.async {
                        self.jobs.values.forEach {
                            guard $0.token == nil else {
                                return
                            }
                            self.configure(job: $0, start: true)
                        }
                    }
                } catch let error as NSError {
                    Logging.danger("Upload Service", [
                        "Status": "Failed to save workspace",
                        "Error": self.errorWithVariables(error, job: nil)])
                }
            }
        }
    }

    private func report(completedJob: CompletedUploadJob) {
        // Assume we're running on service dispatch queue.
        guard self.isReadyToReportCompletedJobs else {
            self.pendingCompletedJobs.append(completedJob)
            return
        }
        self.uploadCompleted.emit(completedJob)
    }

    private func restart(job: UploadJob, discardToken: Bool = false) {
        // Assume we're running on service dispatch queue.
        var job = job
        if discardToken && !job.isCompleted {
            job.restarts = 0
            job.token = nil
        } else {
            job.restarts += 1
        }
        job.started = nil
        self.configure(job: job, start: true)
    }

    private func resumeInfoTask(for job: UploadJob) -> URLSessionDataTask? {
        guard let token = job.token, token.isValid, token.isResumeSupported else {
            return nil
        }
        var request = URLRequest(url: token.url)
        request.httpMethod = "PUT"
        request.addValue("0", forHTTPHeaderField: "Content-Length")
        request.addValue("bytes */\(job.bytes)", forHTTPHeaderField: "Content-Range")
        let task = self.session.dataTask(with: request)
        task.taskDescription = job.id
        return task
    }

    private func runAsBackgroundTask(deadline: DispatchTime, block: @escaping () -> ()) {
        var taskId = UIBackgroundTaskInvalid
        taskId = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            if taskId != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = UIBackgroundTaskInvalid
            }
        })
        self.queue.asyncAfter(deadline: deadline) {
            block()
            if taskId != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
    }

    private func saveToDisk() throws {
        // Assume we're running on service dispatch queue.
        guard let workspace = self.workspace else {
            return
        }
        let url = self.url(forWorkspaceInfoIn: workspace)
        let object: [String: Any] = [
            "timestamp": NSNumber(value: Date().timeIntervalSince1970),
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "UNKNOWN",
            "tokens": self.tokens.filter({ $0.isUsable }).map({ $0.toDict() }),
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url, options: [.atomic])
        #if DEBUG
            NSLog("%@", "[UploadService] Saved \(self.tokens.count) upload tokens to disk")
        #endif
    }

    private func setJob(id: String, progress: Int64) {
        guard var job = self.jobs[id] else {
            return
        }
        job.progress = progress
        self.jobs[id] = job
        self.uploadProgress.emit(job)
    }

    private func tryWrite(job: UploadJob) {
        // Assume we're running on service dispatch queue.
        do {
            try self.write(job: job)
        } catch {
            Logging.danger("Upload Service", [
                "Id": job.id,
                "Status": "Failed to update upload job file",
                "Error": self.errorWithVariables(error, job: job)])
        }
    }

    private func unload() {
        // Assume we're running on service dispatch queue.
        guard let oldAccountId = self.accountId else {
            return
        }
        Logging.warning("Upload Service", [
            "Status": "Unloading previous workspace",
            "AccountId": String(oldAccountId),
            "Path": self.workspace?.path ?? "N/A"])
        // TODO: Pause pending uploads.
        self.accountId = nil
        self.jobs.removeAll()
        self.tokens.removeAll()
        self.workspace = nil
    }

    private func uploadTask(for job: UploadJob, resumingFrom: Int64? = nil) -> (URLSessionUploadTask, UploadToken)? {
        guard let token = job.token, token.isValid else {
            return nil
        }
        let fileURL = self.url(forDataOf: job)
        guard let fileSize = fileURL.fileSize else {
            Logging.danger("Upload Service", [
                "Id": job.id,
                "Status": "Upload file went missing"])
            self.fail(jobId: job.id)
            return nil
        }
        var request = URLRequest(url: token.url)
        request.httpMethod = "PUT"
        let remainingBytes = job.bytes - (resumingFrom ?? 0)
        request.addValue(String(remainingBytes), forHTTPHeaderField: "Content-Length")
        request.addValue(job.contentType, forHTTPHeaderField: "Content-Type")
        let task: URLSessionUploadTask
        if let startIndex = resumingFrom {
            if remainingBytes != fileSize {
                // Create a resume file that only contains the non-uploaded data.
                guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
                    Logging.danger("Upload Service", [
                        "Id": job.id,
                        "Status": "Failed to read file to upload"])
                    return nil
                }
                let resumeURL = self.url(forResumeDataOf: job)
                let trimmedData = data.subdata(in: (data.count - Int(remainingBytes))..<data.count)
                do {
                    try trimmedData.write(to: resumeURL, options: [.atomic])
                } catch let error as NSError {
                    Logging.danger("Upload Service", [
                        "Id": job.id,
                        "Status": "Failed to write partial upload file",
                        "Error": self.errorWithVariables(error, job: job)])
                    return nil
                }
                task = self.session.uploadTask(with: request, fromFile: resumeURL)
            } else {
                task = self.session.uploadTask(with: request, fromFile: fileURL)
            }
            let endIndex = job.bytes - 1
            request.addValue("bytes \(startIndex)-\(endIndex)/\(job.bytes)", forHTTPHeaderField: "Content-Range")
            self.setJob(id: job.id, progress: startIndex - 1)
        } else {
            task = self.session.uploadTask(with: request, fromFile: fileURL)
            self.setJob(id: job.id, progress: 0)
        }
        task.taskDescription = job.id
        return (task, token)
    }

    private func url(for filename: String) -> URL {
        guard let workspace = self.workspace else {
            Logging.danger("Upload Service", [
                "Status": "Failed to generate URL because workspace is not set",
                "Filename": filename])
            if BackendClient.api.session == nil {
                Logging.danger("Upload Service", [
                    "Status": "Failed to fallback to workspace URL because session is nil",
                    "Filename": filename])
            }
            let fallback = try! self.url(forWorkspaceOf: BackendClient.api.session?.id ?? 0)
            return fallback.appendingPathComponent(filename)
        }
        return workspace.appendingPathComponent(filename)
    }

    private func url(forDataOf job: UploadJob) -> URL {
        return self.url(for: "\(job.id).\(EXTENSION_DATA)")
    }

    private func url(forInfoOf job: UploadJob) -> URL {
        return self.url(for: "\(job.id).\(EXTENSION_JOB)")
    }

    private func url(forInfoOf token: UploadToken) -> URL {
        return self.url(for: "\(token.id).\(EXTENSION_JSON)")
    }

    private func url(forResumeDataOf job: UploadJob) -> URL {
        return self.url(for: "\(job.id).\(EXTENSION_RESUME_DATA)")
    }

    private func url(forWorkspaceInfoIn workspace: URL) -> URL {
        return workspace.appendingPathComponent("workspace.\(EXTENSION_JSON)")
    }

    private func url(forWorkspaceOf accountId: Int64) throws -> URL {
        var url = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        url.appendPathComponent("UploadService")
        url.appendPathComponent("\(accountId)")
        return url
    }

    private func write(job: UploadJob) throws {
        // Assume we're running on service dispatch queue.
        let data = try JSONSerialization.data(withJSONObject: job.toDict(), options: [.prettyPrinted])
        let url = self.url(forInfoOf: job)
        let fs = FileManager.default
        if fs.fileExists(atPath: url.path) {
            Logging.debug("Upload Service", ["Status": "Updating job metadata file",
                                             "Bytes": data.count, "Path": url.path])
        } else {
            Logging.debug("Upload Service", ["Status": "Creating job metadata file",
                                             "Bytes": data.count, "Path": url.path])
        }
        try data.write(to: url, options: [.atomic])
    }

    private func x_performMigrationFromOldVersionsInWorkspace(_ workspace: URL) {
        // In old versions we would incorrectly put files outside the <account id> directory.
        let naked = workspace.deletingLastPathComponent()
        // Move them into the actual workspace.
        let fs = FileManager.default
        let files: [String]
        do {
            files = try fs.contentsOfDirectory(atPath: naked.path)
        } catch {
            Logging.danger("Upload Service", [
                "Status": "Failed to list workspace parent for migration",
                "Path": naked.path,
                "Error": error.localizedDescription])
            return
        }
        for file in files {
            let url = naked.appendingPathComponent(file)
            var isDir: ObjCBool = false
            guard fs.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            let newURL = workspace.appendingPathComponent(file)
            guard !fs.fileExists(atPath: newURL.path) else {
                Logging.warning("Upload Service", [
                    "Status": "SKIPPING migration of incorrectly located file (already exists)",
                    "OldPath": url.path,
                    "NewPath": newURL.path])
                return
            }
            Logging.warning("Upload Service", [
                "Status": "Migrating incorrectly located file",
                "OldPath": url.path,
                "NewPath": newURL.path])
            do {
                try fs.moveItem(at: url, to: newURL)
            } catch {
                Logging.danger("Upload Service", [
                    "Status": "Failed to migrate file",
                    "Path": url.path,
                    "Error": error.localizedDescription])
            }
        }
    }
}
