import SwiftUI

struct ReachabilityDot: View {
    let status: ReachStatus
    var size: CGFloat = 10

    @State private var pulsate: Bool = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .opacity(status == .checking ? (pulsate ? 0.3 : 1.0) : 1.0)
            .animation(
                status == .checking
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default,
                value: pulsate
            )
            .onAppear { pulsate = status == .checking }
            .onChange(of: status) { _, newValue in
                pulsate = newValue == .checking
            }
            .help(status.help)
    }
}
