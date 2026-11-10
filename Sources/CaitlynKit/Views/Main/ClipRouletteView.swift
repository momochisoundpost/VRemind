import SwiftUI

public struct ClipRouletteView: View {
    public let clips: [CuratedClip]

    @State private var currentPick: CuratedClip?
    @State private var previewTitle: String?
    @State private var isSpinning = false

    public init(clips: [CuratedClip]) {
        self.clips = clips
    }

    public static func pickRandomClip<G: RandomNumberGenerator>(
        from clips: [CuratedClip],
        excluding lastId: String?,
        using generator: inout G
    ) -> CuratedClip? {
        guard !clips.isEmpty else {
            return nil
        }
        if clips.count == 1 {
            return clips[0]
        }
        let candidates: [CuratedClip]
        if let lastId {
            let filtered = clips.filter { $0.id != lastId }
            candidates = filtered.isEmpty ? clips : filtered
        } else {
            candidates = clips
        }
        return candidates.randomElement(using: &generator)
    }

    public var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "dice.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.accent)

            Text("Clip Roulette")
                .font(.system(size: 22, weight: .bold))

            if clips.isEmpty {
                Text("No clips yet")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else if let displayTitle = isSpinning ? previewTitle : currentPick?.title {
                VStack(spacing: 12) {
                    Text(displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if !isSpinning, let pick = currentPick, let url = pick.url {
                        Button {
                            LinkOpener.open(url)
                        } label: {
                            Text("Open ↗")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Theme.accent.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
                .frame(maxWidth: 440)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                )
            } else {
                Text("Spin the wheel to land on a random stream highlight.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Button {
                spin()
            } label: {
                Text(isSpinning ? "Spinning…" : "Spin")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(clips.isEmpty || isSpinning ? Color.secondary : Theme.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(clips.isEmpty || isSpinning)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func spin() {
        guard !clips.isEmpty, !isSpinning else { return }
        isSpinning = true
        var rng = SystemRandomNumberGenerator()
        let finalPick = Self.pickRandomClip(from: clips, excluding: currentPick?.id, using: &rng)

        Task { @MainActor in
            let steps = 8
            for step in 0..<steps {
                previewTitle = clips[step % clips.count].title
                try? await Task.sleep(nanoseconds: 110_000_000)
            }
            currentPick = finalPick
            previewTitle = nil
            isSpinning = false
        }
    }
}
