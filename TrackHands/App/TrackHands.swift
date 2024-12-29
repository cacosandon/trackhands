import SwiftUI

@main
struct TrackHandsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        MenuBarExtra { } label: { }
    }
}
