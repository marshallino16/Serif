import Foundation

// MARK: - Models

enum TrackerKind: String {
    case pixel
    case knownTracker
    case cssTracker
    case trackingLink
}

struct TrackerInfo: Identifiable {
    let id = UUID()
    let kind: TrackerKind
    let source: String
    let serviceName: String?
}

struct TrackerResult {
    let sanitizedHTML: String
    let originalHTML: String
    let trackers: [TrackerInfo]

    var trackerCount: Int { trackers.count }
    var hasTrackers: Bool { !trackers.isEmpty }
}

// MARK: - Service

final class TrackerBlockerService {
    static let shared = TrackerBlockerService()
    private init() {}

    // MARK: - Public API

    func sanitize(html: String) -> TrackerResult {
        var output = html
        var trackers: [TrackerInfo] = []

        scanAndStripImages(&output, &trackers)
        scanAndStripCSS(&output, &trackers)
        rewriteTrackingLinks(&output, &trackers)

        return TrackerResult(sanitizedHTML: output, originalHTML: html, trackers: trackers)
    }

    // MARK: - Pass 1: IMG tags

    private func scanAndStripImages(_ html: inout String, _ trackers: inout [TrackerInfo]) {
        guard let regex = try? NSRegularExpression(pattern: "<img\\b[^>]*>", options: .caseInsensitive) else { return }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        // Process in reverse to preserve indices
        for match in matches.reversed() {
            let tag = nsHTML.substring(with: match.range)
            guard let src = extractAttribute("src", from: tag) else { continue }

            // Skip legitimate images
            if isAllowlisted(src) { continue }

            guard let url = URL(string: src), let host = url.host?.lowercased() else {
                // Check for spy pixel without valid URL
                if isSpyPixel(tag: tag) {
                    trackers.append(TrackerInfo(kind: .pixel, source: "hidden pixel", serviceName: nil))
                    html = (html as NSString).replacingCharacters(in: match.range, with: "")
                }
                continue
            }

            let (isDomain, serviceName) = isTrackerDomain(host)
            let isPathTracker = Self.trackerPathPatterns.contains { src.lowercased().contains($0) }
            let isPixel = isSpyPixel(tag: tag)

            if isDomain || isPathTracker {
                trackers.append(TrackerInfo(kind: .knownTracker, source: host, serviceName: serviceName))
                html = (html as NSString).replacingCharacters(in: match.range, with: "")
            } else if isPixel {
                trackers.append(TrackerInfo(kind: .pixel, source: host, serviceName: nil))
                html = (html as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
    }

    // MARK: - Pass 2: CSS background-image

    private func scanAndStripCSS(_ html: inout String, _ trackers: inout [TrackerInfo]) {
        guard let regex = try? NSRegularExpression(
            pattern: "background(?:-image)?\\s*:[^;]*url\\(\\s*['\"]?([^'\")\\s]+)['\"]?\\s*\\)",
            options: .caseInsensitive
        ) else { return }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let urlStr = nsHTML.substring(with: match.range(at: 1))
            guard let url = URL(string: urlStr), let host = url.host?.lowercased() else { continue }

            let (isDomain, serviceName) = isTrackerDomain(host)
            let isPathTracker = Self.trackerPathPatterns.contains { urlStr.lowercased().contains($0) }

            if isDomain || isPathTracker {
                trackers.append(TrackerInfo(kind: .cssTracker, source: host, serviceName: serviceName))
                let fullMatch = nsHTML.substring(with: match.range)
                let replaced = fullMatch.replacingOccurrences(
                    of: "url\\(\\s*['\"]?[^'\")\\s]+['\"]?\\s*\\)",
                    with: "url(about:blank)",
                    options: .regularExpression
                )
                html = (html as NSString).replacingCharacters(in: match.range, with: replaced)
            }
        }
    }

    // MARK: - Pass 3: Tracking link redirects

    private func rewriteTrackingLinks(_ html: inout String, _ trackers: inout [TrackerInfo]) {
        guard let regex = try? NSRegularExpression(
            pattern: "<a\\b[^>]*\\bhref\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
            options: .caseInsensitive
        ) else { return }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let href = nsHTML.substring(with: match.range(at: 1))
            guard let url = URL(string: href), let host = url.host?.lowercased() else { continue }

            let (isDomain, serviceName) = isTrackerDomain(host)
            guard isDomain else { continue }

            // Try to extract the real destination URL from query params
            if let destination = extractRedirectDestination(from: href) {
                trackers.append(TrackerInfo(kind: .trackingLink, source: host, serviceName: serviceName))
                let hrefRange = match.range(at: 1)
                html = (html as NSString).replacingCharacters(in: hrefRange, with: destination)
            } else {
                // Can't extract destination — just record it
                trackers.append(TrackerInfo(kind: .trackingLink, source: host, serviceName: serviceName))
            }
        }
    }

    // MARK: - Helpers

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsTag = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsTag.substring(with: match.range(at: 1))
    }

    private func isSpyPixel(tag: String) -> Bool {
        // Check attribute dimensions
        if let w = extractDimension("width", from: tag), let h = extractDimension("height", from: tag) {
            if w <= 1 && h <= 1 { return true }
        }
        // Check inline style
        let lower = tag.lowercased()
        let styleWidthSmall = lower.range(of: "width\\s*:\\s*[01]px", options: .regularExpression) != nil
        let styleHeightSmall = lower.range(of: "height\\s*:\\s*[01]px", options: .regularExpression) != nil
        if styleWidthSmall && styleHeightSmall { return true }
        return false
    }

    private func extractDimension(_ name: String, from tag: String) -> Int? {
        let pattern = "\\b\(name)\\s*=\\s*[\"']?(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsTag = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)),
              match.numberOfRanges > 1 else { return nil }
        return Int(nsTag.substring(with: match.range(at: 1)))
    }

    private func isTrackerDomain(_ host: String) -> (isTracker: Bool, serviceName: String?) {
        for (domain, name) in Self.trackerDomainMap {
            if host == domain || host.hasSuffix("." + domain) {
                return (true, name)
            }
        }
        return (false, nil)
    }

    private func isAllowlisted(_ src: String) -> Bool {
        let lower = src.lowercased()
        return Self.allowlistPatterns.contains { lower.contains($0) }
    }

    private func extractRedirectDestination(from href: String) -> String? {
        guard let comps = URLComponents(string: href) else { return nil }
        let paramNames = ["url", "redirect", "r", "u", "link", "target", "destination"]
        for param in paramNames {
            if let value = comps.queryItems?.first(where: { $0.name.lowercased() == param })?.value,
               !value.isEmpty, value.hasPrefix("http") {
                return value.removingPercentEncoding ?? value
            }
        }
        return nil
    }

    // MARK: - Known tracker domains → service name

    private static let trackerDomainMap: [String: String?] = [
        // Email marketing platforms
        "track.hubspot.com": "HubSpot",
        "t.hubspotemail.net": "HubSpot",
        "t.hubspotfree.net": "HubSpot",
        "open.hubspot.com": "HubSpot",
        "t.sidekickopen.com": "HubSpot",
        "t.signaux.com": "HubSpot",
        "sendgrid.net": "SendGrid",
        "ct.sendgrid.net": "SendGrid",
        "o.sendgrid.net": "SendGrid",
        "list-manage.com": "Mailchimp",
        "mandrillapp.com": "Mailchimp",
        "mailchimp.com": "Mailchimp",
        "p.mailgun.net": "Mailgun",
        "email.mailgun.net": "Mailgun",
        "links.m.mailchimp.com": "Mailchimp",
        "open.convertkit-mail.com": "ConvertKit",
        "open.convertkit-mail2.com": "ConvertKit",
        "trk.klaviyo.com": "Klaviyo",
        "ctrk.klclick1.com": "Klaviyo",
        "ctrk.klclick2.com": "Klaviyo",
        "cmail19.com": "Campaign Monitor",
        "cmail20.com": "Campaign Monitor",
        "createsend1.com": "Campaign Monitor",
        "t.email.salesforce.com": "Salesforce",
        "click.em.salesforce.com": "Salesforce",

        // Sales / CRM tools
        "t.yesware.com": "Yesware",
        "track.mixmax.com": "Mixmax",
        "t.outreach.io": "Outreach",
        "track.salesloft.com": "SalesLoft",
        "r.superhuman.com": "Superhuman",
        "web.frontapp.com": "Front",
        "t.intercom-mail.com": "Intercom",
        "t.drift.com": "Drift",
        "links.iterable.com": "Iterable",

        // Tracking-specific services
        "mailtrack.io": "Mailtrack",
        "readnotify.com": "ReadNotify",
        "getnotify.com": "GetNotify",
        "bananatag.com": "Bananatag",
        "sendibt3.com": "SendInBlue",
        "pointofmail.com": "PointOfMail",
        "mailfoogae.appspot.com": "Streak",
        "mailstat.us": "Boomerang",

        // Large platforms
        "awstrack.me": "Amazon SES",
        "amazonappservices.com": "Amazon",
        "ad.doubleclick.net": "Google",
        "google-analytics.com": "Google",
        "facebook.com": "Meta",
        "linkedin.com": "LinkedIn",
        "t.co": "Twitter",

        // Transactional
        "postmarkapp.com": "Postmark",
        "tracking.tldrnewsletter.com": "TLDR",
        "t.mailtrap.io": "Mailtrap",
        "emltrk.com": nil,
        "beacon.krxd.net": "Krux",
    ]

    // MARK: - Path patterns

    private static let trackerPathPatterns: [String] = [
        "/track/open",
        "/trk/",
        "/o/e/",
        "/e/o/",
        "/wf/open",
        "/imp?",
        "/beacon",
        "/pixel",
        "/t.gif",
        "/open.gif",
        "/track.png",
        "/1x1.",
        "/e2t/o/",
        "/ss/o/",
        "/gp/r.html",
        "/open.html?x=",
    ]

    // MARK: - Allowlist (skip these — not trackers)

    private static let allowlistPatterns: [String] = [
        "cid:",
        "spacer",
        "logo",
        "transparent.gif",
        "attachments.office.net",
        "avatar",
        "emoji",
        "badge",
        "icon",
        "banner",
        "header",
        "footer",
        "signature",
    ]
}
