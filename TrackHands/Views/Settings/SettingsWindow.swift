import SwiftUI
import AVFoundation

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()

        let settingsView = SettingsView()
            .environmentObject(CameraManager.shared)
        window.contentView = NSHostingView(rootView: settingsView)

        self.init(window: window)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @State private var showingTooltip = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HStack {
                        Text("Check every")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .rounded))

                        TextField("", value: $cameraManager.checkInterval, format: .number.precision(.fractionLength(1)))
                            .frame(width: 24)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .padding(6)
                            .background(Color(.windowBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("seconds")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .rounded))
                    }
                    
                    Spacer()

                    Button {
                        showingTooltip.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .popover(isPresented: $showingTooltip, arrowEdge: .bottom) {
                        Text("If your fingers are not being recognized, close the app and open it again. If that doesn't work, contact us at help@trackhands.com")
                            .font(.system(.caption, design: .rounded))
                            .padding(12)
                            .frame(width: 250)
                    }
                }

                VStack(alignment: .leading) {
                    Picker(
                        selection: $cameraManager.cameraResolution,
                        label: Text("Resolution").foregroundColor(.secondary).font(.system(.body, design: .rounded))
                    ) {
                        Text("Low").tag(AVCaptureSession.Preset.low)
                        Text("Medium").tag(AVCaptureSession.Preset.medium)
                        Text("High").tag(AVCaptureSession.Preset.high)
                    }
                    .pickerStyle(.segmented)
                
                }
            }
            .padding()
        }
        .frame(width: 300)
    }
}
