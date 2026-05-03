import SwiftUI

struct OpenClawChatView: View {
    @ObservedObject var controller: OpenClawLocalController
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if controller.chatMessages.isEmpty {
                            Text("No messages yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        } else {
                            ForEach(controller.chatMessages) { message in
                                chatBubble(for: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 260, maxHeight: 360)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: controller.chatMessages.count) { _, _ in
                    guard let lastID = controller.chatMessages.last?.id else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .frame(minHeight: 92, maxHeight: 120)
                        .padding(6)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Ask OpenClaw something...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        send()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isSendingChat || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        controller.resetChat()
                    } label: {
                        Label("New Chat", systemImage: "arrow.counterclockwise")
                            .frame(minWidth: 100)
                    }
                }
            }

            HStack {
                Text(controller.chatStatusText)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Session: \(controller.chatSessionLabel)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenClaw Chat")
                    .font(.headline)
                Text("Talk to the bot locally inside Gracula.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.isSendingChat || controller.isPreparingLocalModel {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func chatBubble(for message: OpenClawChatMessage) -> some View {
        let isUser = message.role == .user
        HStack {
            if isUser {
                Spacer(minLength: 56)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label(for: message.role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.timestampFormatter.string(from: message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: 520, alignment: .leading)
            .background(backgroundColor(for: message.role), in: RoundedRectangle(cornerRadius: 10))

            if !isUser {
                Spacer(minLength: 56)
            }
        }
    }

    private func label(for role: OpenClawChatMessage.Role) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "You"
        case .assistant:
            return "OpenClaw"
        case .error:
            return "Error"
        }
    }

    private func backgroundColor(for role: OpenClawChatMessage.Role) -> Color {
        switch role {
        case .system:
            return .secondary.opacity(0.12)
        case .user:
            return .accentColor.opacity(0.14)
        case .assistant:
            return .green.opacity(0.12)
        case .error:
            return .red.opacity(0.12)
        }
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }
        draft = ""
        Task {
            await controller.sendChatMessage(message)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
