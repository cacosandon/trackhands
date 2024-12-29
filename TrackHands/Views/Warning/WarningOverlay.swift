import SwiftUI
import AppKit
import AVFoundation

class WarningOverlay: NSWindow {
    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        
        self.contentView = NSHostingView(
            rootView: WarningOverlayView()
                .environmentObject(CameraManager.shared)
                .edgesIgnoringSafeArea(.all)
        )
    }
}

struct WarningOverlayView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
            
            VStack(spacing: 20) {
                warningText
                bitingImageView
            }
        }
    }
    
    private var warningText: some View {
        VStack(spacing: 8) {
            Text("Stop biting!")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .shadow(radius: 10)
            
            Text("Please don't bite your fingers. Look at yourself.")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.white)
                .shadow(radius: 10)
        }
    }
    
    @ViewBuilder
    private var bitingImageView: some View {
        if let bitingImage = cameraManager.lastBitingImage {
            Image(nsImage: bitingImage)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: 320, height: 240)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(radius: 10)
        }
    }
}
