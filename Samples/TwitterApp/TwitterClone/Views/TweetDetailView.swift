import SwiftUI

struct TweetDetailView: View {
    let tweetWithAuthor: TweetWithAuthor
    let currentUserId: String

    @EnvironmentObject var tweetViewModel: TweetViewModel
    @StateObject private var feedViewModel = FeedViewModel()

    @State private var replies: [TweetWithAuthor] = []
    @State private var isLoading = true
    @State private var showingReply = false

    var tweet: Tweet { tweetWithAuthor.tweet }
    var author: Profile { tweetWithAuthor.author }

    var isLiked: Bool {
        guard let tweetId = tweet.id else { return false }
        return tweetViewModel.likedTweetIds.contains(tweetId)
    }

    var isBookmarked: Bool {
        guard let tweetId = tweet.id else { return false }
        return tweetViewModel.bookmarkedTweetIds.contains(tweetId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Main tweet
                VStack(alignment: .leading, spacing: 12) {
                    // Author info
                    HStack(spacing: 12) {
                        NavigationLink(destination: ProfileView(userId: author.userId)) {
                            if let avatarUrl = author.avatarUrl, let url = URL(string: avatarUrl) {
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
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(author.displayName ?? author.username)
                                .fontWeight(.semibold)
                            Text("@\(author.username)")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Menu {
                            Button(action: {}) {
                                Label("Share Tweet", systemImage: "square.and.arrow.up")
                            }
                            if author.userId == currentUserId {
                                Button(role: .destructive, action: {}) {
                                    Label("Delete Tweet", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(.secondary)
                        }
                    }

                    // Content
                    Text(tweet.content)
                        .font(.title3)

                    // Image
                    if let imageUrl = tweet.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView())
                        }
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Timestamp
                    if let createdAt = tweet.createdAt {
                        Text(formatDate(createdAt))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }

                    Divider()

                    // Stats
                    HStack(spacing: 20) {
                        HStack(spacing: 4) {
                            Text("\(tweet.retweetsCount ?? 0)")
                                .fontWeight(.semibold)
                            Text("Retweets")
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 4) {
                            Text("\(tweet.likesCount ?? 0)")
                                .fontWeight(.semibold)
                            Text("Likes")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)

                    Divider()

                    // Actions
                    HStack {
                        Spacer()

                        Button(action: { showingReply = true }) {
                            Image(systemName: "bubble.left")
                                .font(.title2)
                        }
                        .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {}) {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.title2)
                        }
                        .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            guard let tweetId = tweet.id else { return }
                            Task {
                                await tweetViewModel.toggleLike(tweetId: tweetId, userId: currentUserId)
                            }
                        }) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.title2)
                        }
                        .foregroundColor(isLiked ? .red : .secondary)

                        Spacer()

                        Button(action: {
                            guard let tweetId = tweet.id else { return }
                            Task {
                                await tweetViewModel.toggleBookmark(tweetId: tweetId, userId: currentUserId)
                            }
                        }) {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.title2)
                        }
                        .foregroundColor(isBookmarked ? .blue : .secondary)

                        Spacer()

                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                        }
                        .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .padding()

                Divider()

                // Replies
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if replies.isEmpty {
                    VStack(spacing: 8) {
                        Text("No replies yet")
                            .font(.headline)
                        Text("Be the first to reply!")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(replies) { reply in
                        TweetRowView(
                            tweetWithAuthor: reply,
                            currentUserId: currentUserId
                        )
                        .environmentObject(tweetViewModel)

                        Divider()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReply) {
            ComposeView(replyTo: tweetWithAuthor)
                .environmentObject(tweetViewModel)
                .environmentObject(feedViewModel)
        }
        .task {
            await loadReplies()
        }
    }

    private func loadReplies() async {
        guard let tweetId = tweet.id else {
            isLoading = false
            return
        }

        replies = await feedViewModel.loadReplies(parentId: tweetId)
        isLoading = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a · MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    let profile = Profile(
        id: "1",
        userId: "user1",
        username: "johndoe",
        displayName: "John Doe",
        bio: nil,
        avatarUrl: nil,
        headerUrl: nil,
        location: nil,
        website: nil,
        followersCount: 100,
        followingCount: 50,
        tweetsCount: 10,
        createdAt: Date(),
        updatedAt: Date()
    )

    let tweet = Tweet(
        id: "1",
        userId: "user1",
        content: "Hello, this is my first tweet!",
        imageUrl: nil,
        likesCount: 5,
        retweetsCount: 2,
        repliesCount: 1,
        parentId: nil,
        isRetweet: false,
        originalTweetId: nil,
        createdAt: Date(),
        updatedAt: Date()
    )

    return NavigationStack {
        TweetDetailView(
            tweetWithAuthor: TweetWithAuthor(tweet: tweet, author: profile),
            currentUserId: "user1"
        )
        .environmentObject(TweetViewModel())
    }
}
