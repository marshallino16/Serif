import Foundation

/// Resolves and manages email signatures based on send-as aliases.
struct SignatureResolver {

    /// Resolves the plain-text signature for a given preferred alias email.
    /// Falls back to the default/primary alias, then the first alias with a signature.
    static func resolve(preferredEmail: String, aliases: [GmailSendAs]) -> String {
        let alias: GmailSendAs?
        if !preferredEmail.isEmpty {
            alias = aliases.first(where: { $0.sendAsEmail == preferredEmail })
        } else {
            alias = aliases.first(where: { $0.isPrimary == true })
                ?? aliases.first(where: { $0.isDefault == true })
                ?? aliases.first
        }
        guard let sig = alias?.signature, !sig.isEmpty else { return "" }
        let plain = sig.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? "" : plain
    }

    /// Returns the plain-text signature for a specific alias email, falling back
    /// to the settings-preferred email when the alias has no signature.
    static func signatureForAlias(
        _ aliasEmail: String,
        aliases: [GmailSendAs],
        fallbackPreferredEmail: String
    ) -> String {
        if let alias = aliases.first(where: { $0.sendAsEmail == aliasEmail }),
           let sig = alias.signature, !sig.isEmpty,
           !sig.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sig.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return resolve(preferredEmail: fallbackPreferredEmail, aliases: aliases)
    }

    /// Replaces `currentSignature` in `bodyText` with the new signature, returning
    /// the updated body and updated current signature.
    static func replaceSignature(
        in bodyText: String,
        currentSignature: String,
        newSignature: String
    ) -> (body: String, signature: String) {
        var updatedBody = bodyText
        if !currentSignature.isEmpty {
            updatedBody = bodyText.replacingOccurrences(of: currentSignature, with: newSignature)
        } else if !newSignature.isEmpty {
            updatedBody = "\n\n\(newSignature)" + bodyText
        }
        return (updatedBody, newSignature)
    }

    // MARK: - HTML variants

    /// Resolves the raw HTML signature for a given preferred alias email.
    static func resolveHTML(preferredEmail: String, aliases: [GmailSendAs]) -> String {
        let alias: GmailSendAs?
        if !preferredEmail.isEmpty {
            alias = aliases.first(where: { $0.sendAsEmail == preferredEmail })
        } else {
            alias = aliases.first(where: { $0.isPrimary == true })
                ?? aliases.first(where: { $0.isDefault == true })
                ?? aliases.first
        }
        guard let sig = alias?.signature, !sig.isEmpty,
              !sig.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "<div class=\"serif-signature\">\(sig)</div>"
    }

    /// Returns the HTML signature for a specific alias email, with fallback.
    static func signatureHTMLForAlias(
        _ aliasEmail: String,
        aliases: [GmailSendAs],
        fallbackPreferredEmail: String
    ) -> String {
        if let alias = aliases.first(where: { $0.sendAsEmail == aliasEmail }),
           let sig = alias.signature, !sig.isEmpty,
           !sig.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "<div class=\"serif-signature\">\(sig)</div>"
        }
        return resolveHTML(preferredEmail: fallbackPreferredEmail, aliases: aliases)
    }

    /// Replaces the HTML signature block in the body.
    static func replaceHTMLSignature(
        in bodyHTML: String,
        currentSignature: String,
        newSignature: String
    ) -> (body: String, signature: String) {
        var updatedBody = bodyHTML
        if !currentSignature.isEmpty {
            // Try to find and replace the serif-signature div
            if let range = bodyHTML.range(of: currentSignature) {
                updatedBody = bodyHTML.replacingCharacters(in: range, with: newSignature)
            }
        } else if !newSignature.isEmpty {
            // Prepend signature
            updatedBody = "<br><br>\(newSignature)" + bodyHTML
        }
        return (updatedBody, newSignature)
    }
}
