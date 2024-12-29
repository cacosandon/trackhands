import SwiftUI

struct CameraDetectionOverlay: View {
    let mouthRect: CGRect?
    let handsFingersPositions: [[CGPoint]]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let mouthRect = mouthRect {
                    Rectangle()
                        .stroke(Color.pink, lineWidth: 2)
                        .frame(width: mouthRect.width, height: mouthRect.height)
                        .cornerRadius(4)
                        .position(x: mouthRect.midX, y: mouthRect.midY)
                        .overlay(
                            Text("Mouth")
                                .foregroundColor(.pink)
                                .font(.caption)
                                .padding(2)
                                .background(Color.white.opacity(0.7))
                                .cornerRadius(4)
                                .position(x: mouthRect.midX, y: mouthRect.minY - 20)
                        )
                }
                
                ForEach(handsFingersPositions.indices, id: \.self) { i in
                    let hand = handsFingersPositions[i]

                    ForEach(hand.indices, id: \.self) { j in
                        let handPoint = hand[j]
                        Circle()
                            .fill(Color.black)
                            .frame(width: 8, height: 8)
                            .position(handPoint)
                    }
                }
            }
        }
    }
}
