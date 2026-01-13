import SwiftUI

struct FeedView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var feedViewModel: FeedViewModel
    @EnvironmentObject var tweetViewModel: TweetViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if feedViewModel.isLoading && feedViewModel.tweets.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in
                            TweetSkeletonView()
                        }
                    } else if feedViewModel.tweets.isEmpty {
                        EmptyFeedView()
                    } else {
                        ForEach(feedViewModel.tweets) { tweetWithAuthor in
                            TweetRowView(
                                tweetWithAuthor: tweetWithAuthor,
                                currentUserId: authViewModel.currentUser?.id ?? ""
                            )
                            .environmentObject(tweetViewModel)

                            Divider()
                        }
                    }
                }
            }
            .refreshable {
                await feedViewModel.refreshFeed()
            }
            .onAppear {
                // Set up callback for updating a specific tweet after like/unlike
                tweetViewModel.onTweetUpdated = { [weak feedViewModel] tweetId in
                    await feedViewModel?.updateTweet(tweetId: tweetId)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let avatarUrl = authViewModel.currentProfile?.avatarUrl,
                       let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.bubble")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No tweets yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Be the first to share something!")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

struct TweetSkeletonView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 16)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 14)
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 14)
            }
        }
        .padding()
        .redacted(reason: .placeholder)
    }
}

#Preview {
    FeedView()
        .environmentObject(AuthViewModel())
        .environmentObject(FeedViewModel())
        .environmentObject(TweetViewModel())
}
