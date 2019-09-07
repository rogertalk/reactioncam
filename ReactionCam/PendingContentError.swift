import Foundation

enum PendingContentError: Error {
    case assetsMustBeMerged
    case internalStateError
    case uploadCancelled
}

extension PendingContentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .assetsMustBeMerged:
            return "Assets must be merged before attempting to start upload"
        case .internalStateError:
            return "An internal state error occurred"
        case .uploadCancelled:
            return "The upload was cancelled"
        }
    }
}
