import SwiftUI

struct TweetRowView: View {
    let tweetWithAuthor: TweetWithAuthor
    let currentUserId: String

    @EnvironmentObject var tweetViewModel: TweetViewModel
    @State private var showingReply = false
    @State private var showingDetail = false

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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
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

                VStack(alignment: .leading, spacing: 4) {
                    // Header
                    HStack(spacing: 4) {
                        Text(author.displayName ?? author.username)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text("@\(author.username)")
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Text("·")
                            .foregroundColor(.secondary)

                        Text(relativeTime(from: tweet.createdAt))
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    // Content
                    Text(tweet.content)
                        .fixedSize(horizontal: false, vertical: true)

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
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                    }

                    // Actions
                    HStack(spacing: 0) {
                        // Reply
                        Button(action: { showingReply = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                Text("\(tweet.repliesCount ?? 0)")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Retweet
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.2.squarepath")
                                Text("\(tweet.retweetsCount ?? 0)")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Like
                        Button(action: {
                            guard let tweetId = tweet.id else { return }
                            Task {
                                await tweetViewModel.toggleLike(tweetId: tweetId, userId: currentUserId)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                Text("\(tweet.likesCount ?? 0)")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(isLiked ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Bookmark
                        Button(action: {
                            guard let tweetId = tweet.id else { return }
                            Task {
                                await tweetViewModel.toggleBookmark(tweetId: tweetId, userId: currentUserId)
                            }
                        }) {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        }
                        .foregroundColor(isBookmarked ? .blue : .secondary)

                        // Share
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingReply) {
            ComposeView(replyTo: tweetWithAuthor)
        }
        .navigationDestination(isPresented: $showingDetail) {
            TweetDetailView(tweetWithAuthor: tweetWithAuthor, currentUserId: currentUserId)
        }
    }

    private func relativeTime(from date: Date?) -> String {
        guard let date = date else { return "" }

        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)

        if let days = components.day, days > 0 {
            if days >= 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
            return "\(days)d"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m"
        } else {
            return "now"
        }
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
        content: "Hello, this is my first tweet! #SwiftUI",
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
        TweetRowView(
            tweetWithAuthor: TweetWithAuthor(tweet: tweet, author: profile),
            currentUserId: "user1"
        )
        .environmentObject(TweetViewModel())
    }
}
