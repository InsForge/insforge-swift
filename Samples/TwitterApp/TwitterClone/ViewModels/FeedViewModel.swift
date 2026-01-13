import Foundation
import SwiftUI
import InsForge

@MainActor
class FeedViewModel: ObservableObject {
    @Published var tweets: [TweetWithAuthor] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var client: InsForgeClient { insforge }
    private var profileCache: [String: Profile] = [:]

    func loadFeed() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Load tweets ordered by creation date
            let fetchedTweets: [Tweet] = try await client.database
                .from("tweets")
                .select()
                .is("parent_id", value: nil)  // Only top-level tweets
                .order("created_at", ascending: false)
                .limit(50)
                .execute()

            // Load profiles for each tweet
            var tweetsWithAuthors: [TweetWithAuthor] = []
            for tweet in fetchedTweets {
                if let author = await getProfile(userId: tweet.userId) {
                    tweetsWithAuthors.append(TweetWithAuthor(tweet: tweet, author: author))
                }
            }

            self.tweets = tweetsWithAuthors
        } catch {
            errorMessage = "Failed to load feed: \(error.localizedDescription)"
        }
    }

    func loadUserTweets(userId: String) async -> [TweetWithAuthor] {
        do {
            let fetchedTweets: [Tweet] = try await client.database
                .from("tweets")
                .select()
                .eq("user_id", value: userId)
                .is("parent_id", value: nil)
                .order("created_at", ascending: false)
                .execute()

            var tweetsWithAuthors: [TweetWithAuthor] = []
            for tweet in fetchedTweets {
                if let author = await getProfile(userId: tweet.userId) {
                    tweetsWithAuthors.append(TweetWithAuthor(tweet: tweet, author: author))
                }
            }

            return tweetsWithAuthors
        } catch {
            print("Failed to load user tweets: \(error)")
            return []
        }
    }

    func loadUserReplies(userId: String) async -> [TweetWithAuthor] {
        do {
            // Load all tweets by user, then filter for replies (those with parent_id)
            let allTweets: [Tweet] = try await client.database
                .from("tweets")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()

            // Filter for replies (tweets that have a parent_id)
            let fetchedTweets = allTweets.filter { $0.parentId != nil }

            var tweetsWithAuthors: [TweetWithAuthor] = []
            for tweet in fetchedTweets {
                if let author = await getProfile(userId: tweet.userId) {
                    tweetsWithAuthors.append(TweetWithAuthor(tweet: tweet, author: author))
                }
            }

            return tweetsWithAuthors
        } catch {
            print("Failed to load user replies: \(error)")
            return []
        }
    }

    func loadUserLikedTweets(userId: String) async -> [TweetWithAuthor] {
        do {
            // First get the user's likes
            let likes: [Like] = try await client.database
                .from("likes")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()

            let tweetIds = likes.compactMap { $0.tweetId }
            guard !tweetIds.isEmpty else { return [] }

            // Then fetch those tweets
            let fetchedTweets: [Tweet] = try await client.database
                .from("tweets")
                .select()
                .in("id", values: tweetIds)
                .execute()

            // Maintain the order from likes (most recent likes first)
            var tweetsWithAuthors: [TweetWithAuthor] = []
            for tweetId in tweetIds {
                if let tweet = fetchedTweets.first(where: { $0.id == tweetId }),
                   let author = await getProfile(userId: tweet.userId) {
                    tweetsWithAuthors.append(TweetWithAuthor(tweet: tweet, author: author))
                }
            }

            return tweetsWithAuthors
        } catch {
            print("Failed to load user liked tweets: \(error)")
            return []
        }
    }

    func loadReplies(parentId: String) async -> [TweetWithAuthor] {
        do {
            let fetchedTweets: [Tweet] = try await client.database
                .from("tweets")
                .select()
                .eq("parent_id", value: parentId)
                .order("created_at", ascending: true)
                .execute()

            var tweetsWithAuthors: [TweetWithAuthor] = []
            for tweet in fetchedTweets {
                if let author = await getProfile(userId: tweet.userId) {
                    tweetsWithAuthors.append(TweetWithAuthor(tweet: tweet, author: author))
                }
            }

            return tweetsWithAuthors
        } catch {
            print("Failed to load replies: \(error)")
            return []
        }
    }

    private func getProfile(userId: String) async -> Profile? {
        // Check cache first
        if let cached = profileCache[userId] {
            return cached
        }

        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("user_id", value: userId)
                .execute()

            if let profile = profiles.first {
                profileCache[userId] = profile
                return profile
            }
        } catch {
            print("Failed to load profile: \(error)")
        }

        return nil
    }

    func refreshFeed() async {
        profileCache.removeAll()
        await loadFeed()
    }

    /// Update a single tweet in the feed (e.g., after like/unlike)
    func updateTweet(tweetId: String) async {
        do {
            let fetchedTweets: [Tweet] = try await client.database
                .from("tweets")
                .select()
                .eq("id", value: tweetId)
                .execute()

            if let updatedTweet = fetchedTweets.first,
               let index = tweets.firstIndex(where: { $0.tweet.id == tweetId }) {
                let author = tweets[index].author
                tweets[index] = TweetWithAuthor(tweet: updatedTweet, author: author)
            }
        } catch {
            print("Failed to update tweet: \(error)")
        }
    }
}
