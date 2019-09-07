import Foundation

enum MessageServiceError: Error {
    case invalidChatCommand
    case invalidData
    case invalidType
    case missingSession
    case threadIdMismatch
    case unknownThread
}
