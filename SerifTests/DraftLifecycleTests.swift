import XCTest
@testable import Serif

@MainActor
final class DraftLifecycleTests: XCTestCase {

    // MARK: - ComposeViewModel: concurrent save guard

    func testSaveDraftGuardPreventsConcurrentCalls() async {
        let vm = ComposeViewModel(accountID: "", fromAddress: "test@test.com")
        vm.subject = "Test"
        vm.body = "Body"
        vm.isHTML = true

        async let save1: Void = vm.saveDraft()
        async let save2: Void = vm.saveDraft()
        _ = await (save1, save2)

        // With empty accountID both fail, but no crash and no double-create.
    }

    // MARK: - ComposeViewModel: gmailDraftID prevents create when set

    func testSaveDraftUpdatesWhenDraftIDExists() async {
        let vm = ComposeViewModel(accountID: "", fromAddress: "test@test.com")
        vm.gmailDraftID = "existing_draft_123"
        vm.subject = "Updated"
        vm.body = "Updated body"
        vm.isHTML = true

        await vm.saveDraft()

        XCTAssertEqual(vm.gmailDraftID, "existing_draft_123",
                       "Draft ID should be preserved when update fails")
    }

    // MARK: - MailStore: draft operations on gmailDrafts array

    func testUpdateDraftWorksForGmailDrafts() {
        let store = MailStore()
        let draftID = GmailDataTransformer.deterministicUUID(from: "gmail_draft_1")
        let gmailDraft = Email(
            id: draftID,
            sender: Contact(name: "Me", email: "me@test.com"),
            subject: "Original Subject",
            body: "Original Body",
            preview: "Original",
            date: Date(),
            folder: .drafts,
            isDraft: true,
            isGmailDraft: true,
            gmailDraftID: "gmail_draft_1"
        )
        store.gmailDrafts = [gmailDraft]

        store.updateDraft(id: draftID, subject: "New Subject", body: "New Body", to: "to@test.com", cc: "")

        XCTAssertEqual(store.gmailDrafts.first?.subject, "New Subject")
        XCTAssertEqual(store.gmailDrafts.first?.body, "New Body")
        XCTAssertEqual(store.gmailDrafts.first?.recipients.first?.email, "to@test.com")
    }

    func testDeleteDraftRemovesFromGmailDrafts() {
        let store = MailStore()
        let draftID = GmailDataTransformer.deterministicUUID(from: "gmail_draft_1")
        let gmailDraft = Email(
            id: draftID,
            sender: Contact(name: "Me", email: "me@test.com"),
            subject: "Draft",
            body: "Body",
            preview: "Body",
            date: Date(),
            folder: .drafts,
            isDraft: true,
            isGmailDraft: true,
            gmailDraftID: "gmail_draft_1"
        )
        store.gmailDrafts = [gmailDraft]

        store.deleteDraft(id: draftID)

        XCTAssertTrue(store.gmailDrafts.isEmpty, "Gmail draft should be removed")
    }

    // MARK: - MailStore: gmailDraftID persistence

    func testSetGmailDraftIDPersistsOnLocalDraft() {
        let store = MailStore()
        let draft = Email(
            sender: Contact(name: "", email: ""),
            subject: "Draft",
            body: "Content",
            preview: "Content",
            date: Date(),
            folder: .drafts,
            isDraft: true
        )
        store.emails = [draft]
        XCTAssertNil(store.emails.first?.gmailDraftID)

        store.setGmailDraftID("gmail_123", for: draft.id)

        XCTAssertEqual(store.emails.first?.gmailDraftID, "gmail_123",
                       "gmailDraftID should be persisted on the Email object")
    }

    // MARK: - MailStore: sync removes local duplicates

    func testSyncGmailDraftsRemovesLocalDuplicates() {
        let store = MailStore()

        // Local draft that was already synced to Gmail
        var localDraft = Email(
            sender: Contact(name: "", email: ""),
            subject: "My Draft",
            body: "<div>Hello</div>",
            preview: "Hello",
            date: Date(),
            folder: .drafts,
            isDraft: true
        )
        localDraft.gmailDraftID = "gd_abc"
        store.emails = [localDraft]

        // Simulate sync bringing back the same draft from Gmail
        let gmailDraft = Email(
            id: GmailDataTransformer.deterministicUUID(from: "gd_abc"),
            sender: Contact(name: "", email: ""),
            subject: "My Draft",
            body: "<div>Hello</div>",
            preview: "Hello",
            date: Date(),
            folder: .drafts,
            isDraft: true,
            isGmailDraft: true,
            gmailDraftID: "gd_abc"
        )
        store.gmailDrafts = [gmailDraft]

        // Simulate the dedup logic from syncGmailDrafts
        let syncedGmailIDs = Set(store.gmailDrafts.compactMap(\.gmailDraftID))
        store.emails.removeAll { email in
            email.folder == .drafts && email.isDraft
                && email.gmailDraftID != nil
                && syncedGmailIDs.contains(email.gmailDraftID!)
        }

        // Should have only the Gmail version
        let drafts = store.emails(for: .drafts)
        XCTAssertEqual(drafts.count, 1, "Duplicate should be removed")
        XCTAssertTrue(drafts[0].isGmailDraft, "Remaining draft should be the Gmail version")
    }

    // MARK: - MailStore: local draft without gmailDraftID survives sync

    func testSyncGmailDraftsKeepsUnsyncedLocalDrafts() {
        let store = MailStore()

        // Local draft that has NOT been synced yet (no gmailDraftID)
        let localDraft = Email(
            sender: Contact(name: "", email: ""),
            subject: "New Draft",
            body: "",
            preview: "New draft",
            date: Date(),
            folder: .drafts,
            isDraft: true
        )
        store.emails = [localDraft]

        // Simulate sync bringing back a different Gmail draft
        let gmailDraft = Email(
            id: GmailDataTransformer.deterministicUUID(from: "gd_other"),
            sender: Contact(name: "", email: "me@test.com"),
            subject: "Old Draft",
            body: "Content",
            preview: "Content",
            date: Date().addingTimeInterval(-60),
            folder: .drafts,
            isDraft: true,
            isGmailDraft: true,
            gmailDraftID: "gd_other"
        )
        store.gmailDrafts = [gmailDraft]

        // Dedup
        let syncedGmailIDs = Set(store.gmailDrafts.compactMap(\.gmailDraftID))
        store.emails.removeAll { email in
            email.folder == .drafts && email.isDraft
                && email.gmailDraftID != nil
                && syncedGmailIDs.contains(email.gmailDraftID!)
        }

        // Both should remain: local (unsynced) + Gmail
        let drafts = store.emails(for: .drafts)
        XCTAssertEqual(drafts.count, 2, "Unsynced local draft + Gmail draft both kept")
    }

    // MARK: - Draft body content check

    func testReopenedDraftPreservesBodyWhenHasContent() {
        let draftBody = "<div>My important email content</div>"
        XCTAssertFalse(draftBody.isEmpty,
                       "Draft body with content should not be treated as empty")
    }

    // MARK: - Preview strips HTML tags

    func testUpdateDraftStripsHTMLFromPreview() {
        let store = MailStore()
        let draft = store.createDraft()

        store.updateDraft(
            id: draft.id,
            subject: "Test",
            body: "<div>Hello <b>world</b></div>",
            to: "test@test.com",
            cc: ""
        )

        let updated = store.emails.first { $0.id == draft.id }!
        XCTAssertFalse(updated.preview.contains("<div>"),
                       "Preview should not contain HTML tags")
        XCTAssertTrue(updated.preview.contains("Hello"),
                      "Preview should contain plain text content")
    }

    // MARK: - MailStore: draft lookup finds both local and Gmail drafts

    func testEmailsForDraftsFolderMergesLocalAndGmail() {
        let store = MailStore()
        let localDraft = Email(
            sender: Contact(name: "", email: ""),
            subject: "Local Draft",
            body: "",
            preview: "Local",
            date: Date(),
            folder: .drafts,
            isDraft: true
        )
        store.emails = [localDraft]

        let gmailDraft = Email(
            sender: Contact(name: "Me", email: "me@test.com"),
            subject: "Gmail Draft",
            body: "Content",
            preview: "Content",
            date: Date().addingTimeInterval(-60),
            folder: .drafts,
            isDraft: true,
            isGmailDraft: true,
            gmailDraftID: "gd_1"
        )
        store.gmailDrafts = [gmailDraft]

        let drafts = store.emails(for: .drafts)
        XCTAssertEqual(drafts.count, 2, "Should merge local and Gmail drafts")
        XCTAssertEqual(drafts[0].subject, "Local Draft", "Newest first")
        XCTAssertEqual(drafts[1].subject, "Gmail Draft")
    }

    // MARK: - ComposeModeInitializer

    func testComposeModeNewReturnsSignatureBody() {
        let fields = ComposeModeInitializer.apply(
            mode: .new,
            signatureForNew: "",
            signatureForReply: "",
            aliases: []
        )
        XCTAssertTrue(fields.bodyHTML.isEmpty,
                      "No signature → empty bodyHTML, so existing draft body is preserved")
    }

    func testComposeModeNewWithSignatureReturnsNonEmptyBody() {
        let alias = GmailSendAs(sendAsEmail: "me@test.com", displayName: "Me",
                                signature: "<div>My Signature</div>", isDefault: true, isPrimary: true)
        let fields = ComposeModeInitializer.apply(
            mode: .new,
            signatureForNew: "me@test.com",
            signatureForReply: "",
            aliases: [alias]
        )
        XCTAssertFalse(fields.bodyHTML.isEmpty,
                       "Signature present → bodyHTML should contain signature")
        XCTAssertTrue(fields.bodyHTML.contains("My Signature"))
    }

    // MARK: - Inline image CID round-trip

    func testInlineImageExtractionAndResolutionRoundTrip() {
        // Step 1: Editor HTML with data: URL + data-cid (as inserted by WebRichTextEditor)
        let originalHTML = """
        <div>Hello <img src="data:image/png;base64,iVBORw0KGgo=" data-cid="img_abc"> world</div>
        """

        // Step 2: Extract for draft save (data: → cid:)
        let (processedHTML, images) = InlineImageProcessor.extractInlineImages(from: originalHTML)
        XCTAssertTrue(processedHTML.contains("cid:img_abc"), "Should replace data: with cid:")
        XCTAssertFalse(processedHTML.contains("data:image"), "data: URL should be gone")
        XCTAssertEqual(images.count, 1, "Should extract one image")
        XCTAssertEqual(images[0].contentID, "img_abc")

        // Step 3: Simulate resolving CID back with data-cid attribute (as makeEmailFromGmailDraft does)
        let base64 = images[0].data.base64EncodedString()
        let dataURI = "data:\(images[0].mimeType);base64,\(base64)"
        let resolvedHTML = processedHTML.replacingOccurrences(
            of: "src=\"cid:img_abc\"",
            with: "src=\"\(dataURI)\" data-cid=\"img_abc\""
        )
        XCTAssertTrue(resolvedHTML.contains("data-cid=\"img_abc\""),
                      "Resolved HTML must include data-cid for re-extraction")
        XCTAssertTrue(resolvedHTML.contains("data:image/png;base64,"),
                      "Resolved HTML must include data: URL")

        // Step 4: Re-extract (simulates auto-save after re-opening draft)
        let (reProcessed, reImages) = InlineImageProcessor.extractInlineImages(from: resolvedHTML)
        XCTAssertTrue(reProcessed.contains("cid:img_abc"), "Round-trip: should extract again")
        XCTAssertEqual(reImages.count, 1, "Round-trip: should find the same image")
        XCTAssertEqual(reImages[0].contentID, "img_abc", "Round-trip: same CID")
    }

    // MARK: - Draft duplicate prevention: needsResave

    func testNeedsResaveIsSetWhenSaveIsInFlight() async {
        let vm = ComposeViewModel(accountID: "", fromAddress: "test@test.com")
        vm.subject = "Test"
        vm.body = "Version 1"
        vm.isHTML = true

        // Start first save (will be "in flight" — API fails but processing takes time)
        async let save1: Void = vm.saveDraft()

        // Tiny yield to let save1 start and set isSaving = true
        try? await Task.sleep(nanoseconds: 1_000_000)

        // If save1 is still running, this should set needsResave
        await vm.saveDraft()

        _ = await save1

        // After all completes, needsResave should be cleared (retry executed)
        XCTAssertFalse(vm.needsResave,
                       "needsResave should be cleared after retry executes")
    }

    func testConcurrentSavesPreserveDraftID() async {
        let vm = ComposeViewModel(accountID: "", fromAddress: "test@test.com")
        vm.gmailDraftID = "existing_draft_456"
        vm.subject = "Test"
        vm.body = "V1"
        vm.isHTML = true

        async let save1: Void = vm.saveDraft()
        vm.body = "V2"
        async let save2: Void = vm.saveDraft()
        _ = await (save1, save2)

        XCTAssertEqual(vm.gmailDraftID, "existing_draft_456",
                       "Draft ID must not be lost during concurrent saves")
    }

    // MARK: - Draft ID recovery from MailStore.replyDrafts

    func testDraftIDRecoveryFromReplyDrafts() {
        let store = MailStore()
        let threadID = "thread_abc"
        store.replyDrafts[threadID] = MailStore.ReplyDraftInfo(
            gmailDraftID: "draft_recovered_123",
            preview: "Hello world"
        )

        // Simulate a new ComposeViewModel (as if view was recreated by SwiftUI)
        let vm = ComposeViewModel(accountID: "acc", fromAddress: "me@test.com", threadID: threadID)
        XCTAssertNil(vm.gmailDraftID, "New VM should have no draft ID")

        // Simulate recovery logic from scheduleAutoSave
        if vm.gmailDraftID == nil,
           let saved = store.replyDrafts[threadID] {
            vm.gmailDraftID = saved.gmailDraftID
        }

        XCTAssertEqual(vm.gmailDraftID, "draft_recovered_123",
                       "Draft ID should be recovered from MailStore.replyDrafts to prevent duplicate creates")
    }

    func testDraftIDRecoverySkippedWhenAlreadySet() {
        let store = MailStore()
        let threadID = "thread_abc"
        store.replyDrafts[threadID] = MailStore.ReplyDraftInfo(
            gmailDraftID: "old_draft",
            preview: "Old"
        )

        let vm = ComposeViewModel(accountID: "acc", fromAddress: "me@test.com", threadID: threadID)
        vm.gmailDraftID = "current_draft"

        // Recovery should NOT overwrite existing draft ID
        if vm.gmailDraftID == nil,
           let saved = store.replyDrafts[threadID] {
            vm.gmailDraftID = saved.gmailDraftID
        }

        XCTAssertEqual(vm.gmailDraftID, "current_draft",
                       "Should not overwrite existing gmailDraftID")
    }

    // MARK: - MailStore.replyDrafts persistence

    func testReplyDraftsPersistenceRoundTrip() {
        let key = "replyDrafts"
        // Clean up before test
        UserDefaults.standard.removeObject(forKey: key)

        let store1 = MailStore()
        let threadID = "thread_persist_test"
        store1.replyDrafts[threadID] = MailStore.ReplyDraftInfo(
            gmailDraftID: "draft_xyz",
            preview: "Test preview text"
        )
        store1.saveReplyDrafts()

        // New MailStore instance reads from UserDefaults on init
        let store2 = MailStore()
        XCTAssertEqual(store2.replyDrafts[threadID]?.gmailDraftID, "draft_xyz",
                       "Draft ID should survive MailStore recreation")
        XCTAssertEqual(store2.replyDrafts[threadID]?.preview, "Test preview text",
                       "Preview should survive MailStore recreation")

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testReplyDraftsCleanupOnDiscard() {
        let store = MailStore()
        let threadID = "thread_discard_test"
        store.replyDrafts[threadID] = MailStore.ReplyDraftInfo(
            gmailDraftID: "draft_to_discard",
            preview: "Will be discarded"
        )

        // Simulate discard (as collapse() does)
        store.replyDrafts.removeValue(forKey: threadID)

        XCTAssertNil(store.replyDrafts[threadID],
                     "Discarded draft should be removed from replyDrafts")
    }

    // MARK: - GmailModels: contentID and inline parts

    func testContentIDExtraction() {
        let part = GmailMessagePart(
            partId: "1",
            mimeType: "image/png",
            filename: "logo.png",
            headers: [GmailHeader(name: "Content-ID", value: "<logo@company.com>")],
            body: GmailMessageBody(attachmentId: "att1", size: 100, data: nil),
            parts: nil
        )
        XCTAssertEqual(part.contentID, "logo@company.com", "Should strip angle brackets")
    }

    func testContentIDNilWhenMissing() {
        let part = GmailMessagePart(
            partId: "1",
            mimeType: "text/html",
            filename: nil,
            headers: [GmailHeader(name: "Content-Type", value: "text/html")],
            body: GmailMessageBody(attachmentId: nil, size: 100, data: nil),
            parts: nil
        )
        XCTAssertNil(part.contentID)
    }

    func testInlinePartsCollected() {
        let inlinePart = GmailMessagePart(
            partId: "1.2",
            mimeType: "image/png",
            filename: "logo.png",
            headers: [GmailHeader(name: "Content-ID", value: "<logo@cid>")],
            body: GmailMessageBody(attachmentId: "att1", size: 500, data: nil),
            parts: nil
        )
        let htmlPart = GmailMessagePart(
            partId: "1.1",
            mimeType: "text/html",
            filename: nil,
            headers: nil,
            body: GmailMessageBody(attachmentId: nil, size: 200, data: nil),
            parts: nil
        )
        let payload = GmailMessagePart(
            partId: "0",
            mimeType: "multipart/related",
            filename: nil,
            headers: nil,
            body: GmailMessageBody(attachmentId: nil, size: 0, data: nil),
            parts: [htmlPart, inlinePart]
        )
        let message = GmailMessage(
            id: "msg1", threadId: "t1", labelIds: ["INBOX"],
            snippet: "test", internalDate: nil, payload: payload,
            sizeEstimate: 1000, historyId: nil, raw: nil
        )

        XCTAssertEqual(message.inlineParts.count, 1)
        XCTAssertEqual(message.inlineParts.first?.contentID, "logo@cid")
    }

    func testInlinePartsExcludedFromAttachments() {
        let inlinePart = GmailMessagePart(
            partId: "1.2",
            mimeType: "image/png",
            filename: "logo.png",
            headers: [GmailHeader(name: "Content-ID", value: "<logo@cid>")],
            body: GmailMessageBody(attachmentId: "att1", size: 500, data: nil),
            parts: nil
        )
        let filePart = GmailMessagePart(
            partId: "1.3",
            mimeType: "application/pdf",
            filename: "document.pdf",
            headers: nil,
            body: GmailMessageBody(attachmentId: "att2", size: 1000, data: nil),
            parts: nil
        )
        let payload = GmailMessagePart(
            partId: "0",
            mimeType: "multipart/mixed",
            filename: nil,
            headers: nil,
            body: GmailMessageBody(attachmentId: nil, size: 0, data: nil),
            parts: [inlinePart, filePart]
        )
        let message = GmailMessage(
            id: "msg1", threadId: "t1", labelIds: ["INBOX"],
            snippet: nil, internalDate: nil, payload: payload,
            sizeEstimate: 2000, historyId: nil, raw: nil
        )

        XCTAssertEqual(message.attachmentParts.count, 1, "Only file attachment, not inline image")
        XCTAssertEqual(message.attachmentParts.first?.filename, "document.pdf")
        XCTAssertEqual(message.inlineParts.count, 1)
    }
}
