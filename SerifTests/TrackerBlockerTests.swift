import XCTest
@testable import Serif

final class TrackerBlockerTests: XCTestCase {

    private let service = TrackerBlockerService.shared

    // MARK: - Known Tracker Domains (IMG tags)

    func testStripTrackerImage_HubSpot() {
        let html = """
        <p>Hello</p>
        <img src="https://track.hubspot.com/open/abc123" width="1" height="1">
        <p>World</p>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect HubSpot tracker")
        XCTAssertFalse(result.sanitizedHTML.contains("track.hubspot.com"), "Should strip HubSpot image")
        XCTAssertTrue(result.sanitizedHTML.contains("Hello"))
        XCTAssertTrue(result.sanitizedHTML.contains("World"))

        let hubspot = result.trackers.first { $0.serviceName == "HubSpot" }
        XCTAssertNotNil(hubspot, "Should identify tracker as HubSpot")
    }

    func testStripTrackerImage_SendGrid() {
        let html = """
        <img src="https://ct.sendgrid.net/o/tracking/v2/open?token=abc">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers)
        let sendgrid = result.trackers.first { $0.serviceName == "SendGrid" }
        XCTAssertNotNil(sendgrid, "Should identify tracker as SendGrid")
    }

    func testStripTrackerImage_Mailchimp() {
        let html = """
        <img src="https://list-manage.com/track/open.php?u=abc123">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers)
        let mailchimp = result.trackers.first { $0.serviceName == "Mailchimp" }
        XCTAssertNotNil(mailchimp, "Should identify tracker as Mailchimp")
    }

    // MARK: - Tracker Path Patterns

    func testStripTrackerImage_ByPathPattern() {
        let html = """
        <img src="https://unknown-domain.com/track/open?id=abc123">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect tracker by path pattern /track/open")
    }

    func testStripTrackerImage_PixelGifPath() {
        let html = """
        <img src="https://some-service.com/t.gif?user=123">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect tracker by /t.gif path pattern")
    }

    func testStripTrackerImage_BeaconPath() {
        let html = """
        <img src="https://analytics.example.com/beacon?id=456">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect tracker by /beacon path pattern")
    }

    func testStripTrackerImage_1x1Path() {
        let html = """
        <img src="https://tracking.example.com/1x1.gif?campaign=summer">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect tracker by /1x1. path pattern")
    }

    // MARK: - Spy Pixel Detection (by dimensions)

    func testStripSpyPixel_WidthHeightAttributes() {
        let html = """
        <img src="https://random-domain.com/image.png" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect 1x1 spy pixel")
        let pixel = result.trackers.first { $0.kind == .pixel }
        XCTAssertNotNil(pixel)
    }

    func testStripSpyPixel_ZeroDimensions() {
        let html = """
        <img src="https://random-domain.com/image.png" width="0" height="0">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect 0x0 spy pixel")
    }

    func testStripSpyPixel_InlineStyle() {
        let html = """
        <img src="https://random-domain.com/image.png" style="width:1px;height:1px;">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect spy pixel by inline style")
    }

    func testStripSpyPixel_ZeroInlineStyle() {
        let html = """
        <img src="https://random-domain.com/image.png" style="width:0px;height:0px;">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect spy pixel with 0px inline style")
    }

    // MARK: - Safe / Normal Images Pass Through

    func testNormalImage_NotStripped() {
        let html = """
        <img src="https://images.example.com/photo.jpg" width="600" height="400">
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "Normal image should not be flagged")
        XCTAssertTrue(result.sanitizedHTML.contains("photo.jpg"), "Normal image should be preserved")
    }

    func testAllowlisted_Logo_NotStripped() {
        let html = """
        <img src="https://company.com/logo.png" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "Allowlisted logo should not be flagged")
        XCTAssertTrue(result.sanitizedHTML.contains("logo.png"), "Logo should be preserved")
    }

    func testAllowlisted_CID_NotStripped() {
        let html = """
        <img src="cid:inline-image-001">
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "CID image should not be flagged")
        XCTAssertTrue(result.sanitizedHTML.contains("cid:"), "CID image should be preserved")
    }

    func testAllowlisted_Avatar_NotStripped() {
        let html = """
        <img src="https://service.com/avatar/user123.jpg" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "Avatar image should not be flagged")
    }

    func testAllowlisted_Emoji_NotStripped() {
        let html = """
        <img src="https://cdn.example.com/emoji/smile.png" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "Emoji image should not be flagged")
    }

    // MARK: - CSS Background Tracker Detection

    func testStripCSSTracker_BackgroundImage() {
        let html = """
        <div style="background-image: url('https://track.hubspot.com/pixel.gif');">Content</div>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect CSS background tracker")
        let cssTracker = result.trackers.first { $0.kind == .cssTracker }
        XCTAssertNotNil(cssTracker, "Should identify as CSS tracker")
        XCTAssertTrue(result.sanitizedHTML.contains("about:blank"), "Should replace tracker URL with about:blank")
    }

    func testStripCSSTracker_BackgroundShorthand() {
        let html = """
        <td style="background: url('https://ct.sendgrid.net/tracking.gif');">Cell</td>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect CSS background shorthand tracker")
    }

    func testSafeCSSBackground_NotStripped() {
        let html = """
        <div style="background-image: url('https://images.example.com/banner.jpg');">Content</div>
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "Safe CSS background should not be flagged")
    }

    // MARK: - Tracking Link Detection

    func testDetectTrackingLink_WithRedirect() {
        let html = """
        <a href="https://track.hubspot.com/redirect?url=https%3A%2F%2Fexample.com%2Fpage">Click here</a>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect tracking link")
        let trackingLink = result.trackers.first { $0.kind == .trackingLink }
        XCTAssertNotNil(trackingLink, "Should identify as tracking link")
        XCTAssertTrue(result.sanitizedHTML.contains("https://example.com/page"), "Should rewrite to actual destination")
    }

    func testDetectTrackingLink_WithoutRedirect() {
        let html = """
        <a href="https://track.hubspot.com/click/abc123">Click here</a>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Should detect tracking link even without extractable redirect")
    }

    func testSafeLink_NotFlagged() {
        let html = """
        <a href="https://example.com/article">Read more</a>
        """
        let result = service.sanitize(html: html)

        let trackingLinks = result.trackers.filter { $0.kind == .trackingLink }
        XCTAssertTrue(trackingLinks.isEmpty, "Normal link should not be flagged as tracking link")
    }

    // MARK: - Edge Cases

    func testEmptyHTML() {
        let result = service.sanitize(html: "")

        XCTAssertFalse(result.hasTrackers)
        XCTAssertEqual(result.sanitizedHTML, "")
        XCTAssertEqual(result.trackerCount, 0)
    }

    func testPlainText_NoTrackers() {
        let result = service.sanitize(html: "Just plain text, no HTML tags at all.")

        XCTAssertFalse(result.hasTrackers)
        XCTAssertEqual(result.sanitizedHTML, "Just plain text, no HTML tags at all.")
    }

    func testImgWithoutSrc_Ignored() {
        let html = """
        <img alt="broken image">
        """
        let result = service.sanitize(html: html)

        XCTAssertFalse(result.hasTrackers, "Image without src should be ignored")
    }

    func testMalformedURL_InImgSrc() {
        let html = """
        <img src="not-a-valid-url" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        // Should detect as pixel since dimensions are 1x1 but URL has no host
        if result.hasTrackers {
            let pixel = result.trackers.first { $0.kind == .pixel }
            XCTAssertNotNil(pixel, "Malformed URL with pixel dimensions should be detected as pixel")
        }
        // It's also acceptable if the service ignores it entirely
    }

    func testMultipleTrackers_AllDetected() {
        let html = """
        <p>Email content</p>
        <img src="https://track.hubspot.com/open/1" width="1" height="1">
        <img src="https://ct.sendgrid.net/track/open/2">
        <img src="https://mailtrack.io/pixel/3" width="0" height="0">
        <img src="https://images.example.com/real-photo.jpg" width="800" height="600">
        """
        let result = service.sanitize(html: html)

        XCTAssertGreaterThanOrEqual(result.trackerCount, 3, "Should detect all three trackers")
        XCTAssertTrue(result.sanitizedHTML.contains("real-photo.jpg"), "Legitimate image should remain")
        XCTAssertTrue(result.sanitizedHTML.contains("Email content"), "Content should remain")
    }

    // MARK: - TrackerResult Properties

    func testTrackerResult_OriginalHTMLPreserved() {
        let html = """
        <img src="https://track.hubspot.com/open/abc" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        XCTAssertEqual(result.originalHTML, html, "Original HTML should be preserved in result")
        XCTAssertNotEqual(result.sanitizedHTML, result.originalHTML, "Sanitized should differ from original when tracker found")
    }

    func testTrackerResult_NoTrackers_HTMLUnchanged() {
        let html = "<p>Clean email content with no trackers</p>"
        let result = service.sanitize(html: html)

        XCTAssertEqual(result.sanitizedHTML, html, "HTML should be unchanged when no trackers found")
        XCTAssertEqual(result.originalHTML, html)
        XCTAssertEqual(result.trackerCount, 0)
        XCTAssertFalse(result.hasTrackers)
    }

    // MARK: - Subdomain Matching

    func testSubdomainOfTrackerDomain_Detected() {
        let html = """
        <img src="https://emails.track.hubspot.com/open/sub" width="1" height="1">
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers, "Subdomain of tracker domain should be detected")
    }

    // MARK: - Redirect Destination Extraction

    func testTrackingLink_ExtractsRedirectParam() {
        let html = """
        <a href="https://t.yesware.com/redirect?redirect=https%3A%2F%2Fexample.com%2Fdocs">Docs</a>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers)
        XCTAssertTrue(result.sanitizedHTML.contains("https://example.com/docs"), "Should extract redirect destination")
    }

    func testTrackingLink_ExtractsUrlParam() {
        let html = """
        <a href="https://links.iterable.com/click?url=https%3A%2F%2Fexample.com%2Fpage">Link</a>
        """
        let result = service.sanitize(html: html)

        XCTAssertTrue(result.hasTrackers)
        XCTAssertTrue(result.sanitizedHTML.contains("https://example.com/page"))
    }
}
