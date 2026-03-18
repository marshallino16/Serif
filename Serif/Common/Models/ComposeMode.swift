import Foundation

enum ComposeMode {
    case new
    case reply(to: String, subject: String, quotedBody: String, replyToMessageID: String, threadID: String)
    case replyAll(to: String, cc: String, subject: String, quotedBody: String, replyToMessageID: String, threadID: String)
    case forward(subject: String, quotedBody: String)
}
