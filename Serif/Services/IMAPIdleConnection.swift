import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.serif", category: "IMAPIdle")

/// Maintains a single IMAP IDLE connection for one Gmail account.
/// Runs on a dedicated DispatchQueue — not isolated to any actor.
final class IMAPIdleConnection: @unchecked Sendable {

    enum State: Sendable {
        case disconnected, connecting, greeting, authenticating, selecting, idling, doneWaiting
    }

    var onNewMail: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?

    private let accountID: String
    private let email: String
    private let tokenProvider: @Sendable () async -> String?
    private let queue: DispatchQueue

    private var connection: NWConnection?
    private var state: State = .disconnected
    private var buffer = Data()
    private var tagCounter = 0
    private var lastTag = ""
    private var idleTag = ""
    private var newMailPending = false
    private var reIdleTimer: DispatchSourceTimer?

    init(accountID: String, email: String, tokenProvider: @escaping @Sendable () async -> String?) {
        self.accountID = accountID
        self.email = email
        self.tokenProvider = tokenProvider
        self.queue = DispatchQueue(label: "com.serif.imap-idle.\(accountID)")
    }

    // MARK: - Lifecycle

    func connect() {
        queue.async { [self] in
            guard state == .disconnected else { return }
            log.info("[\(self.accountID)] Connecting to imap.gmail.com:993")
            state = .connecting

            let tlsOptions = NWProtocolTLS.Options()
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 30
            let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)

            let conn = NWConnection(host: "imap.gmail.com", port: 993, using: params)
            connection = conn

            conn.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .ready:
                    log.info("[\(self.accountID)] TLS connection established")
                    self.state = .greeting
                    self.receiveLoop()
                case .failed(let error):
                    log.error("[\(self.accountID)] Connection failed: \(error.localizedDescription)")
                    self.handleDisconnect()
                case .cancelled:
                    self.handleDisconnect()
                default:
                    break
                }
            }

            conn.start(queue: queue)
        }
    }

    func disconnect() {
        queue.async { [self] in
            reIdleTimer?.cancel()
            reIdleTimer = nil
            connection?.cancel()
            connection = nil
            state = .disconnected
            buffer = Data()
            tagCounter = 0
        }
    }

    // MARK: - Receive

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
                self.processLines()
            }
            if isComplete || error != nil {
                self.handleDisconnect()
                return
            }
            self.receiveLoop()
        }
    }

    private func processLines() {
        while let range = buffer.range(of: Data("\r\n".utf8)) {
            let lineData = buffer[buffer.startIndex..<range.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                handleLine(line)
            }
        }
    }

    // MARK: - State Machine

    private func handleLine(_ line: String) {
        switch state {
        case .greeting:
            if line.hasPrefix("* OK") {
                log.info("[\(self.accountID)] Greeting received, authenticating")
                authenticate()
            } else if line.hasPrefix("* BYE") {
                log.warning("[\(self.accountID)] Server sent BYE during greeting")
                handleDisconnect()
            }

        case .authenticating:
            if line.hasPrefix("\(lastTag) OK") {
                log.info("[\(self.accountID)] Authenticated, selecting INBOX")
                selectInbox()
            } else if line.hasPrefix("\(lastTag) NO") || line.hasPrefix("\(lastTag) BAD") {
                log.error("[\(self.accountID)] Auth failed: \(line)")
                handleDisconnect()
            } else if line.hasPrefix("+") {
                // XOAUTH2 error challenge — send empty response to get final NO
                send("")
            }

        case .selecting:
            if line.hasPrefix("\(lastTag) OK") {
                log.info("[\(self.accountID)] INBOX selected, entering IDLE")
                startIdle()
            } else if line.hasPrefix("\(lastTag) NO") || line.hasPrefix("\(lastTag) BAD") {
                log.error("[\(self.accountID)] SELECT failed: \(line)")
                handleDisconnect()
            }

        case .idling:
            let parts = line.split(separator: " ")
            if parts.count == 3, parts[0] == "*", parts[2] == "EXISTS" {
                log.info("[\(self.accountID)] New mail detected (EXISTS)")
                sendDone(newMail: true)
            } else if line.hasPrefix("* BYE") {
                log.warning("[\(self.accountID)] Server sent BYE during IDLE")
                handleDisconnect()
            }
            // Ignore + continuation (IDLE confirmed) and other untagged responses

        case .doneWaiting:
            if line.hasPrefix("\(idleTag) OK") {
                if newMailPending {
                    log.info("[\(self.accountID)] IDLE completed with new mail, notifying")
                    onNewMail?()
                }
                startIdle()
            } else if line.hasPrefix("\(idleTag) NO") || line.hasPrefix("\(idleTag) BAD") {
                log.error("[\(self.accountID)] IDLE failed: \(line)")
                handleDisconnect()
            }

        case .disconnected, .connecting:
            break
        }
    }

    // MARK: - IMAP Commands

    private func nextTag() -> String {
        tagCounter += 1
        lastTag = "A\(String(format: "%03d", tagCounter))"
        return lastTag
    }

    private func authenticate() {
        state = .authenticating
        let tag = nextTag()

        Task { [weak self] in
            guard let self else { return }
            guard let accessToken = await self.tokenProvider() else {
                self.queue.async { self.handleDisconnect() }
                return
            }
            let authString = "user=\(self.email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
            let base64 = Data(authString.utf8).base64EncodedString()
            self.queue.async {
                guard self.state == .authenticating else { return }
                self.send("\(tag) AUTHENTICATE XOAUTH2 \(base64)")
            }
        }
    }

    private func selectInbox() {
        state = .selecting
        let tag = nextTag()
        send("\(tag) SELECT INBOX")
    }

    private func startIdle() {
        state = .idling
        newMailPending = false
        let tag = nextTag()
        idleTag = tag
        send("\(tag) IDLE")
        startReIdleTimer()
    }

    private func sendDone(newMail: Bool) {
        state = .doneWaiting
        newMailPending = newMail
        reIdleTimer?.cancel()
        reIdleTimer = nil
        send("DONE")
    }

    // MARK: - Re-IDLE Timer (29 min — Gmail drops at 30)

    private func startReIdleTimer() {
        reIdleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(29 * 60))
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .idling else { return }
            self.sendDone(newMail: false)
        }
        timer.resume()
        reIdleTimer = timer
    }

    // MARK: - Send / Disconnect

    private func send(_ string: String) {
        guard let data = (string + "\r\n").data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func handleDisconnect() {
        guard state != .disconnected else { return }
        log.info("[\(self.accountID)] Disconnected")
        reIdleTimer?.cancel()
        reIdleTimer = nil
        connection?.cancel()
        connection = nil
        state = .disconnected
        buffer = Data()
        tagCounter = 0
        onDisconnect?()
    }
}
