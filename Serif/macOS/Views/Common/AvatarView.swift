import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AvatarView: View {
    let initials: String
    let color: String
    var size: CGFloat = 36
    var avatarURL: String? = nil
    var senderDomain: String? = nil

    @State private var image: PlatformImage? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if let image {
                platformImage(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: color))
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .task(id: avatarURL) {
            image = nil

            // 1. Try primary URL (People API photo / Gravatar)
            if let url = avatarURL, let img = await AvatarCache.shared.image(for: url) {
                image = img
                return
            }

            // 2. Fallback: BIMI logo for org/brand domains
            if let domain = senderDomain,
               let bimiURL = await BIMIService.shared.logoURL(for: domain),
               let img = await AvatarCache.shared.image(for: bimiURL) {
                image = img
            }
        }
    }

    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }
}
