import SwiftUI

struct ConfirmationView: View {
    let title: String
    let summary: String
    let requiredPhrase: String?
    @Binding var confirmationText: String
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(summary)
                .foregroundStyle(.secondary)

            if let requiredPhrase {
                TextField(requiredPhrase, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button("Approve", action: onApprove)
                Button("Reject", role: .destructive, action: onReject)
            }
        }
        .padding(12)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}

