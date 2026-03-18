import SwiftUI

extension Color {
    /// Cross-platform luminance calculation using resolved color components.
    func luminance(in environment: EnvironmentValues = EnvironmentValues()) -> Double {
        let resolved = self.resolve(in: environment)
        return 0.299 * Double(resolved.red) + 0.587 * Double(resolved.green) + 0.114 * Double(resolved.blue)
    }
}
