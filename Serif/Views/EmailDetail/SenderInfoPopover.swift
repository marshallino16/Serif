import SwiftUI

struct SenderInfoPopover: View {
    let message: GmailMessage
    let email: Email
    @Environment(\.theme) private var theme

    private var fromDisplay: String {
        let name = email.sender.name
        let addr = email.sender.email
        if name.isEmpty || name == addr { return addr }
        return "\(name) <\(addr)>"
    }

    private var sentByDomain: String? {
        message.fromDomain
    }

    private var dateFormatted: String {
        message.date?.formattedMedium ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Message info section
            VStack(spacing: 0) {
                infoRow(label: "From:", value: fromDisplay, suspicious: message.isSuspiciousSender)
                if let domain = sentByDomain {
                    infoRow(label: "sent by:", value: domain)
                }
                infoRow(label: "to:", value: message.to)
                if !message.cc.isEmpty {
                    infoRow(label: "cc:", value: message.cc)
                }
                infoRow(label: "Date:", value: dateFormatted)
                infoRow(label: "Subject:", value: message.subject, multiline: true)
            }

            // Security section
            if message.mailedBy != nil || message.signedBy != nil || message.encryptionInfo != nil {
                Divider()
                    .background(theme.divider)
                    .padding(.vertical, 6)

                VStack(spacing: 0) {
                    if let mailed = message.mailedBy {
                        infoRow(label: "Mailed by:", value: mailed, suspicious: message.isSuspiciousSender)
                    }
                    if let signed = message.signedBy {
                        infoRow(label: "Signed by:", value: signed)
                    }
                    if let encryption = message.encryptionInfo {
                        securityRow(label: "Security:", value: encryption)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 320, maxWidth: 440)
    }

    private func infoRow(label: String, value: String, suspicious: Bool = false, multiline: Bool = false) -> some View {
        HStack(alignment: multiline ? .top : .center, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(theme.textSecondary)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 8)

            Text(value)
                .font(.system(size: 11, weight: suspicious ? .semibold : .regular))
                .foregroundColor(suspicious ? .red : theme.textPrimary)
                .lineLimit(multiline ? 3 : 1)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func securityRow(label: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(theme.textSecondary)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 8)

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
                Text(value)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textPrimary)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }
}
