import SwiftUI

public struct AddChannelCard: View {
    public let currentCount: Int
    public let onAdd: (String, String) -> Bool
    public let onExpansionChanged: (() -> Void)?

    @State private var isExpanded = false
    @State private var handle = ""
    @State private var name = ""
    @State private var errorMessage: String?

    public init(
        currentCount: Int,
        onAdd: @escaping (String, String) -> Bool,
        onExpansionChanged: (() -> Void)? = nil
    ) {
        self.currentCount = currentCount
        self.onAdd = onAdd
        self.onExpansionChanged = onExpansionChanged
    }

    public static func buttonLabel(currentCount: Int, maxSlots: Int = WatchlistService.maxSlots) -> String {
        "+ Add VTuber (\(currentCount)/\(maxSlots))"
    }

    public var body: some View {
        if isExpanded {
            expandedForm
        } else {
            collapsedButton
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
            errorMessage = nil
            onExpansionChanged?()
        } label: {
            Text(Self.buttonLabel(currentCount: currentCount))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Theme.accent.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var expandedForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add VTuber to Watchlist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            TextField("@handle (e.g. @kobokanaeru)", text: $handle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("Display Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.live)
            }

            HStack(spacing: 8) {
                Spacer()

                Button {
                    resetForm()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    submit()
                } label: {
                    Text("Add")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func submit() {
        guard WatchedChannel.normalizeHandle(handle) != nil else {
            errorMessage = "Please enter a valid @handle."
            onExpansionChanged?()
            return
        }
        if onAdd(name, handle) {
            resetForm()
        } else {
            errorMessage = "Channel is already in your watchlist."
            onExpansionChanged?()
        }
    }

    private func resetForm() {
        handle = ""
        name = ""
        errorMessage = nil
        isExpanded = false
        onExpansionChanged?()
    }
}
