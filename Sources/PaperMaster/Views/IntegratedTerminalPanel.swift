import SwiftUI

#if os(macOS)
import AppKit
import SwiftTerm

struct IntegratedTerminalPanel: View {
    @Environment(AgentRuntimeService.self) private var agentRuntime
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header

            Divider()

            if let session = agentRuntime.selectedEmbeddedSession {
                TerminalContainerView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Terminal",
                    systemImage: "terminal",
                    description: Text("Create a terminal session to start a local shell inside PaperMaster.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: agentRuntime.panelHeight)
        .background(.ultraThinMaterial)
    }

    private var resizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 10)

            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 54, height: 5)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = agentRuntime.panelHeight
                    }
                    let baseHeight = dragStartHeight ?? agentRuntime.panelHeight
                    agentRuntime.setPanelHeight(baseHeight - value.translation.height)
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
        .help("Drag to resize terminal")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Terminal")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(agentRuntime.embeddedSessions) { session in
                        Button {
                            agentRuntime.selectedEmbeddedSessionID = session.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.caption)
                                Text(sessionLabel(for: session))
                                    .lineLimit(1)
                                    .font(.subheadline)

                                Button {
                                    agentRuntime.removeEmbeddedSession(session)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(agentRuntime.selectedEmbeddedSessionID == session.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)

            Button("New Terminal", systemImage: "plus") {
                _ = agentRuntime.createEmbeddedSession()
            }

            Button {
                agentRuntime.isPanelVisible = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .help("Hide Terminal")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.94))
    }

    private func sessionLabel(for session: EmbeddedTerminalSession) -> String {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false {
            return title
        }
        return session.currentDirectoryPath ?? "Terminal \(session.index)"
    }
}

private struct TerminalContainerView: NSViewRepresentable {
    let session: EmbeddedTerminalSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(
            calibratedRed: CGFloat(0x1f) / 255.0,
            green: CGFloat(0x23) / 255.0,
            blue: CGFloat(0x2b) / 255.0,
            alpha: 1.0
        ).cgColor

        let terminal = LocalProcessTerminalView(frame: container.bounds)
        terminal.autoresizingMask = [.width, .height]
        session.configure(terminal)
        container.addSubview(terminal)
        session.startIfNeeded()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let terminal = nsView.subviews.first(where: { $0 is LocalProcessTerminalView }) as? LocalProcessTerminalView else {
            return
        }
        terminal.frame = nsView.bounds
        session.configure(terminal)
        session.startIfNeeded()
    }
}
#endif
