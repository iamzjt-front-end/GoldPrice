import SwiftUI

extension Color {
    static let goldGreen = Color(red: 75 / 255, green: 166 / 255, blue: 110 / 255)

    static var appCardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor).opacity(0.96)
        #else
        return Color.white
        #endif
    }

    static var appGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor).opacity(0.97)
        #else
        return Color.white
        #endif
    }
}

#if canImport(AppKit)
import AppKit

extension NSColor {
    static let goldGreen = NSColor(red: 75 / 255, green: 166 / 255, blue: 110 / 255, alpha: 1)
}
#endif
