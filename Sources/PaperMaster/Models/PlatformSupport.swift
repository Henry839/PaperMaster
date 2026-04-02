import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#endif

#if canImport(UIKit)
extension UIColor {
    convenience init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    convenience init(calibratedWhite white: CGFloat, alpha: CGFloat) {
        self.init(white: white, alpha: alpha)
    }
}
#endif

struct PlatformCapabilities: Sendable {
    let supportsIntegratedTerminal: Bool
    let supportsRemotePaperStorage: Bool
    let supportsSeparateReaderWindow: Bool

    static let current = PlatformCapabilities(
        supportsIntegratedTerminal: {
            #if os(macOS)
            true
            #else
            false
            #endif
        }(),
        supportsRemotePaperStorage: {
            #if os(macOS)
            true
            #else
            false
            #endif
        }(),
        supportsSeparateReaderWindow: {
            #if os(macOS)
            true
            #else
            false
            #endif
        }()
    )
}

extension Color {
    init(platformColor: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: platformColor)
        #elseif canImport(UIKit)
        self.init(uiColor: platformColor)
        #endif
    }
}
