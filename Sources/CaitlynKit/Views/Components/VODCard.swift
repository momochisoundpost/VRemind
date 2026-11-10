import SwiftUI

public struct VODCard: View {
    public let replay: ReplayVOD

    public init(replay: ReplayVOD) {
        self.replay = replay
    }

    public var body: some View {
        Button {
            LinkOpener.open(replay.watchURL)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: replay.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        default:
                            Rectangle()
                                .fill(Theme.accent.opacity(0.15))
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .overlay(
                                    Image(systemName: "play.tv.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(Theme.accent)
                                )
                        }
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipped()
                    .cornerRadius(8)

                    Text(replay.duration)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .padding(6)
                }

                Text(replay.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(replay.date.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text(replay.duration)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
