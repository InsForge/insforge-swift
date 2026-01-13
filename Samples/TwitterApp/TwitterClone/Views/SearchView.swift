import SwiftUI
import InsForge

struct SearchView: View {
    @State private var searchText = ""
    @State private var searchResults: [Profile] = []
    @State private var isSearching = false

    private var client: InsForgeClient { insforge }

    var body: some View {
        NavigationStack {
            VStack {
                if searchText.isEmpty {
                    // Trending section (placeholder)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Trends for you")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(trendingTopics, id: \.self) { topic in
                                TrendingRowView(topic: topic)
                                Divider()
                            }
                        }
                    }
                    .padding(.top)

                    Spacer()
                } else if isSearching {
                    ProgressView()
                        .padding(.top, 40)
                    Spacer()
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No results for \"\(searchText)\"")
                            .font(.headline)
                        Text("Try searching for people by username")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                    Spacer()
                } else {
                    List(searchResults) { profile in
                        NavigationLink(destination: ProfileView(userId: profile.userId)) {
                            HStack(spacing: 12) {
                                if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.displayName ?? profile.username)
                                        .fontWeight(.semibold)
                                    Text("@\(profile.username)")
                                        .foregroundColor(.secondary)

                                    if let bio = profile.bio, !bio.isEmpty {
                                        Text(bio)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search users")
            .onChange(of: searchText) { _, newValue in
                Task {
                    await search(query: newValue)
                }
            }
        }
    }

    private func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .ilike("username", pattern: "%\(query)%")
                .limit(20)
                .execute()

            searchResults = profiles
        } catch {
            print("Search failed: \(error)")
        }
    }

    private var trendingTopics: [String] {
        [
            "#SwiftUI",
            "#iOSDev",
            "#WWDC2024",
            "#Apple",
            "#Programming"
        ]
    }
}

struct TrendingRowView: View {
    let topic: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trending")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(topic)
                .fontWeight(.semibold)

            Text("\(Int.random(in: 1000...50000)) Tweets")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#Preview {
    SearchView()
}
