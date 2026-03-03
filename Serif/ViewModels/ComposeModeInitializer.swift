import Foundation

/// Holds the field values produced by applying a ComposeMode.
struct ComposeModeFields {
    var to: String = ""
    var cc: String = ""
    var showCc: Bool = false
    var subject: String = ""
    var bodyText: String = ""
    var currentSignature: String = ""
    var threadID: String? = nil
    var replyToMessageID: String? = nil
}

/// Populates compose field values based on a ComposeMode and signature settings.
struct ComposeModeInitializer {

    /// Applies the given compose mode and returns the resulting field values.
    static func apply(
        mode: ComposeMode,
        signatureForNew: String,
        signatureForReply: String,
        aliases: [GmailSendAs]
    ) -> ComposeModeFields {
        var fields = ComposeModeFields()

        switch mode {
        case .new:
            let sig = SignatureResolver.resolve(preferredEmail: signatureForNew, aliases: aliases)
            if !sig.isEmpty {
                fields.currentSignature = sig
                fields.bodyText = "\n\n\(sig)"
            }

        case .reply(let replyTo, let replySubject, let quotedBody, let replyToMessageID, let threadID):
            fields.to = replyTo
            fields.subject = replySubject.hasPrefix("Re:") ? replySubject : "Re: \(replySubject)"
            let sig = SignatureResolver.resolve(preferredEmail: signatureForReply, aliases: aliases)
            fields.currentSignature = sig
            fields.bodyText = sig.isEmpty ? "\n\n\(quotedBody)" : "\n\n\(sig)\n\n\(quotedBody)"
            fields.threadID = threadID
            fields.replyToMessageID = replyToMessageID

        case .replyAll(let replyTo, let replyCc, let replySubject, let quotedBody, let replyToMessageID, let threadID):
            fields.to = replyTo
            fields.cc = replyCc
            fields.showCc = !replyCc.isEmpty
            fields.subject = replySubject.hasPrefix("Re:") ? replySubject : "Re: \(replySubject)"
            let sig = SignatureResolver.resolve(preferredEmail: signatureForReply, aliases: aliases)
            fields.currentSignature = sig
            fields.bodyText = sig.isEmpty ? "\n\n\(quotedBody)" : "\n\n\(sig)\n\n\(quotedBody)"
            fields.threadID = threadID
            fields.replyToMessageID = replyToMessageID

        case .forward(let fwdSubject, let quotedBody):
            fields.to = ""
            fields.subject = fwdSubject.hasPrefix("Fwd:") ? fwdSubject : "Fwd: \(fwdSubject)"
            let sig = SignatureResolver.resolve(preferredEmail: signatureForReply, aliases: aliases)
            fields.currentSignature = sig
            fields.bodyText = sig.isEmpty ? "\n\n\(quotedBody)" : "\n\n\(sig)\n\n\(quotedBody)"
        }

        return fields
    }
}
