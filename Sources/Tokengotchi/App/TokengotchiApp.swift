import AppKit
import SwiftUI

// MARK: - App Entry Point
@main
struct TokengotchiApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
