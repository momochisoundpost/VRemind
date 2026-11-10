import Foundation
import SwiftUI

public struct CaitPediaView: View {
    public let entries: [LoreEntry]

    @State private var query: String = ""
    @State private var selectedCategory: String? = nil

    public init(entries: [LoreEntry]) {
        self.entries = entries
    }

    public static func categories(in entries: [LoreEntry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            if seen.insert(entry.category).inserted {
                result.append(entry.category)
            }
        }
        return result
    }

    public static func filter(entries: [LoreEntry], query: String, category: String?) -> [LoreEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        return entries.filter { entry in
            if let category, entry.category != category {
                return false
            }
            guard !trimmed.isEmpty else {
                return true
            }
            if entry.title.range(of: trimmed, options: options) != nil {
                return true
            }
            if entry.summary.range(of: trimmed, options: options) != nil {
                return true
            }
            return entry.tags.contains { tag in
                tag.range(of: trimmed, options: options) != nil
            }
        }
    }

    public var body: some View {
        let allCategories = Self.categories(in: entries)
        let filtered = Self.filter(entries: entries, query: query, category: selectedCategory)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search lore, eras, or tags…", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )

                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(String?.none)
                    ForEach(allCategories, id: \.self) { category in
                        Text(category).tag(String?.some(category))
                    }
                }
                .frame(width: 210)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No lore entries match your search.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { entry in
                            LoreCard(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
    }
}
