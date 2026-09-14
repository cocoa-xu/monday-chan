import AppKit
import FlowingDayControls
import SwiftUI

enum MondayStatusBarAction: Equatable {
    case preferences
    case quickControls

    static func resolve(eventType: NSEvent.EventType?) -> Self {
        switch eventType {
        case .rightMouseDown, .rightMouseUp:
            .quickControls
        default:
            .preferences
        }
    }
}

struct MondayStatusPopover: View {
    let playbackTitle: String?
    let playbackSymbol: String
    let quitTitle: String
    let togglePlayback: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let playbackTitle {
                Button(action: togglePlayback) {
                    actionLabel(playbackTitle, symbol: playbackSymbol)
                }
                .buttonStyle(FlowingSoftButtonStyle())
            }
            Button(action: quit) {
                actionLabel(quitTitle, symbol: "power")
            }
            .buttonStyle(FlowingSoftButtonStyle())
        }
        .padding(8)
        .background(FlowingPalette.canvas)
        .flowingAccent(MondayTheme.accent)
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
        }
        .frame(width: 30, height: 34)
    }
}
