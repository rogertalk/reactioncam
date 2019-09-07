import Speech

class SpeechRecognizer {
    let request: SFSpeechAudioBufferRecognitionRequest
    let task: SFSpeechRecognitionTask

    init?(locale: Locale? = nil) {
        let maybeRecognizer: SFSpeechRecognizer?
        if let locale = locale {
            maybeRecognizer = SFSpeechRecognizer(locale: locale)
        } else {
            maybeRecognizer = SFSpeechRecognizer()
        }
        guard let recognizer = maybeRecognizer, recognizer.isAvailable else {
            return nil
        }
        self.request = SFSpeechAudioBufferRecognitionRequest()
        self.request.contextualStrings = ["ReactionCam", "reaction.cam"]
        self.request.shouldReportPartialResults = false
        self.request.taskHint = .dictation
        self.task = recognizer.recognitionTask(with: self.request, delegate: self.delegate)
    }

    func cancel() {
        self.task.cancel()
        self.delegate.cancel()
    }

    func finish() -> Promise<SFSpeechRecognitionResult> {
        self.task.finish()
        self.delegate.deadline(time: DispatchTime.now() + .seconds(5))
        return self.delegate.result
    }

    // MARK: - Private

    private let delegate = Delegate()
}

fileprivate class Delegate: NSObject, SFSpeechRecognitionTaskDelegate {
    let result: Promise<SFSpeechRecognitionResult>

    override init() {
        (self.result, self.resolve, self.reject) = Promise.exposed()
    }

    func cancel() {
        self.reject(NSError(domain: "cam.reaction.ReactionCam", code: -1))
    }

    func deadline(time: DispatchTime) {
        DispatchQueue.main.asyncAfter(deadline: time) {
            self.reject(NSError(domain: "cam.reaction.ReactionCam", code: -1))
        }
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        self.resolve(recognitionResult)
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        if !successfully, let error = task.error {
            self.reject(error)
        }
    }

    private let resolve: (SFSpeechRecognitionResult) -> ()
    private let reject: (Error) -> ()
}
