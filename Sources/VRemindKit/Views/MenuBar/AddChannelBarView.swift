import SwiftUI

public struct AddChannelBarView: View {
    @ObservedObject public var viewModel: MenuBarStatusViewModel

    public init(viewModel: MenuBarStatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Add YouTube @handle...", text: $viewModel.newHandleInput)
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
