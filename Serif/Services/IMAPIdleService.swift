import Foundation
import Combine
import AppKit
import os.log

private let log = Logger(subsystem: "com.serif", category: "IMAPIdleService")

/// Manages per-account IMAP IDLE connections for real-time inbox monitoring.
@MainActor
final class IMAPIdleService {
    static let shared = IMAPIdleService()

    /// Fires with the accountID when new mail is detected via IDLE.
    var onNewMail: ((String) -> Void)?

    private var connections: [String: IMAPIdleConnection] = [:]
    private var retryDelays: [String: TimeInterval] = [:]
    private var retryTimers: [String: Timer] = [:]
    private var monitoredAccountIDs: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private var appNapActivity: NSObjectProtocol?

    private init() {
        // Reconnect all when network is restored
        NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconnectAll()
            }
            .store(in: &cancellables)

        // Force reconnect after system wake (connections are dead after sleep)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                log.info("System woke — forcing reconnect")
                self.forceReconnectAll()
            }
            .store(in: &cancellables)

        // Clean up connections on app termination
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.stopAll() }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func startMonitoring(accounts: [GmailAccount]) {
        let newIDs = Set(accounts.map(\.id))
        log.info("startMonitoring called with \(accounts.count) account(s): \(newIDs.joined(separator: ", "))")

        // Stop removed accounts
        for id in monitoredAccountIDs.subtracting(newIDs) {
            stopMonitoring(for: id)
        }

        // Start new accounts
        for account in accounts where !connections.keys.contains(account.id) {
            startConnection(for: account)
        }

        monitoredAccountIDs = newIDs
        updateAppNapAssertion()
    }

    func stopMonitoring(for accountID: String) {
        connections[accountID]?.disconnect()
        connections[accountID] = nil
        retryDelays[accountID] = nil
        retryTimers[accountID]?.invalidate()
        retryTimers[accountID] = nil
        monitoredAccountIDs.remove(accountID)
    }

    func stopAll() {
        for id in Array(connections.keys) {
            stopMonitoring(for: id)
        }
        updateAppNapAssertion()
    }

    // MARK: - Private

    private func startConnection(for account: GmailAccount) {
        let accountID = account.id
        let email = account.email

        let conn = IMAPIdleConnection(
            accountID: accountID,
            email: email,
            tokenProvider: { [weak self] in
                await self?.getAccessToken(for: accountID)
            }
        )

        conn.onNewMail = { [weak self] in
            Task { @MainActor in
                self?.retryDelays[accountID] = nil
                self?.onNewMail?(accountID)
            }
        }

        conn.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect(accountID: accountID)
            }
        }

        connections[accountID] = conn
        conn.connect()
    }

    private func handleDisconnect(accountID: String) {
        connections[accountID] = nil
        guard monitoredAccountIDs.contains(accountID),
              NetworkMonitor.shared.isConnected else { return }

        // Exponential backoff: 5s → 10s → 20s → … → 120s max
        let delay = retryDelays[accountID] ?? 5
        retryDelays[accountID] = min(delay * 2, 120)
        log.info("[\(accountID)] Scheduling reconnect in \(Int(delay))s")

        retryTimers[accountID]?.invalidate()
        retryTimers[accountID] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.monitoredAccountIDs.contains(accountID),
                      self.connections[accountID] == nil,
                      let account = AccountStore.shared.accounts.first(where: { $0.id == accountID })
                else { return }
                self.startConnection(for: account)
            }
        }
    }

    private func reconnectAll() {
        for accountID in monitoredAccountIDs where connections[accountID] == nil {
            retryDelays[accountID] = nil
            retryTimers[accountID]?.invalidate()
            retryTimers[accountID] = nil
            if let account = AccountStore.shared.accounts.first(where: { $0.id == accountID }) {
                startConnection(for: account)
            }
        }
    }

    /// Tears down ALL connections and reconnects from scratch (used after system wake).
    private func forceReconnectAll() {
        for (id, conn) in connections {
            conn.disconnect()
            connections[id] = nil
        }
        retryDelays.removeAll()
        for (id, timer) in retryTimers { timer.invalidate(); retryTimers[id] = nil }
        reconnectAll()
    }

    // MARK: - App Nap

    private func updateAppNapAssertion() {
        if !monitoredAccountIDs.isEmpty && appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Monitoring inbox via IMAP IDLE"
            )
        } else if monitoredAccountIDs.isEmpty, let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }
    }

    // MARK: - Token

    private func getAccessToken(for accountID: String) async -> String? {
        guard var token = try? TokenStore.shared.retrieve(for: accountID) else { return nil }
        if token.isExpired {
            guard let refreshed = try? await OAuthService.shared.refreshToken(token) else { return nil }
            try? TokenStore.shared.save(refreshed, for: accountID)
            token = refreshed
        }
        return token.accessToken
    }
}
