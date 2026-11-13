import SwiftUI

public struct AddChannelBarView: View {
    @ObservedObject public var viewModel: MenuBarStatusViewModel

    public init(viewModel: MenuBarStatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(StreamPlatform.allCases, id: \.self) { platform in
                        Button(action: {
                            viewModel.selectedPlatform = platform
                        }) {
                            Text(platform.displayName)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.platformColor(for: viewModel.selectedPlatform))
                            .frame(width: 8, height: 8)
                        Text(viewModel.selectedPlatform.displayName)
                            .font(.system(size: 12))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField(
                    viewModel.selectedPlatform == .youtube ? "Add YouTube @handle..." : "Add Twitch username...",
                    text: $viewModel.newHandleInput
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.addChannel()
                }

                Button(action: {
                    viewModel.addChannel()
                }) {
                    Text("Add")
                }
                .disabled(viewModel.newHandleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = viewModel.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
