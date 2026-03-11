import Foundation

// MARK: - UserDefaults Keys

enum UserDefaultsKey {
    static let undoDuration = "undoDuration"
    static let refreshInterval = "refreshInterval"
    static let selectedThemeId = "selectedThemeId"
    static let themeOverrides = "themeOverrides"
    static let attachmentScanMonths = "attachmentScanMonths"

    static func signatureForNew(_ accountID: String) -> String {
        "signatureForNew.\(accountID)"
    }
    static func signatureForReply(_ accountID: String) -> String {
        "signatureForReply.\(accountID)"
    }
    static func attachmentExclusionRules(_ accountID: String) -> String {
        "attachmentExclusionRules.\(accountID)"
    }
}

// MARK: - Gmail System Labels

enum GmailSystemLabel {
    static let inbox = "INBOX"
    static let starred = "STARRED"
    static let unread = "UNREAD"
    static let sent = "SENT"
    static let draft = "DRAFT"
    static let spam = "SPAM"
    static let trash = "TRASH"
    static let important = "IMPORTANT"

    static let category_personal = "CATEGORY_PERSONAL"
    static let category_social = "CATEGORY_SOCIAL"
    static let category_promotions = "CATEGORY_PROMOTIONS"
    static let category_updates = "CATEGORY_UPDATES"
    static let category_forums = "CATEGORY_FORUMS"
}
