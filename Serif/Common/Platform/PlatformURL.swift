import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PlatformURL {
    @MainActor
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
