import SwiftUI

struct AuditLogPreviewView: View {
    let entries: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audit Log")
                .font(.headline)

            if entries.isEmpty {
                Text("No audit events yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries, id: \.self) { entry in
                            Text(entry)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 96)
            }
        }
    }
}

