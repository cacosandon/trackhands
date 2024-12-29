import SwiftUI
import AVFoundation

struct PopoverView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @State private var showingTooltip = false

    let quitApp: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    showingTooltip.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.primary)
                        .font(.system(size: 16))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingTooltip, arrowEdge: .bottom) {
                    Text("If your fingers are not being recognized, close the app and open it again. If that doesn't work, contact us at help@trackhands.com")
                        .font(.system(.caption, design: .rounded))
                        .padding(12)
                        .frame(width: 250)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: quitApp) {
                    if #available(macOS 13.0, *) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                            .fontWeight(.medium)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Quit Application")
            }
            .background(
                Color(.windowBackgroundColor)
                    .opacity(0.8)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )

            GeometryReader { geometry in
                ZStack {
                    if let previewLayer = cameraManager.previewLayer {
                        CameraPreview(previewLayer: previewLayer)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                CameraDetectionOverlay(
                                    mouthRect: cameraManager.mouthRect,
                                    handsFingersPositions: cameraManager.handsFingersPositions
                                )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    } else {
                        ProgressView("Loading camera...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }
}
