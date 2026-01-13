import Foundation
import SwiftUI
import InsForge
import InsForgeStorage
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class TweetViewModel: ObservableObject {
    @Published var isPosting = false
    @Published var errorMessage: String?
    @Published var likedTweetIds: Set<String> = []
    @Published var bookmarkedTweetIds: Set<String> = []

    /// Callback to notify when a specific tweet needs to be refreshed
    var onTweetUpdated: ((String) async -> Void)?

    private var client: InsForgeClient { insforge }

    func createTweet(content: String, imageData: Data?, userId: String, parentId: String? = nil) async -> Bool {
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            var imageUrl: String?

            // Upload image if provided
            if let data = imageData {
                let fileName = "\(userId)/\(UUID().uuidString).jpg"
                let file = try await client.storage
                    .from("tweets")
                    .upload(
                        path: fileName,
                        data: data,
                        options: FileOptions(contentType: "image/jpeg")
                    )
                imageUrl = file.url
            }

            // Create tweet
            var tweetInsert = TweetInsert(
                userId: userId,
                content: content
            )
            tweetInsert.imageUrl = imageUrl
            tweetInsert.parentId = parentId

            let _: TweetInsert = try await client.database
                .from("tweets")
                .insert(tweetInsert)

            // Update user's tweet count
            try await updateTweetCount(userId: userId, increment: true)

            // If this is a reply, update parent's reply count
            if let parentId = parentId {
                try await updateReplyCount(tweetId: parentId, increment: true)
            }

            return true
        } catch {
            errorMessage = "Failed to create tweet: \(error.localizedDescription)"
            return false
        }
    }

    func deleteTweet(tweetId: String, userId: String) async -> Bool {
        do {
            try await client.database
                .from("tweets")
                .eq("id", value: tweetId)
                .delete()

            try await updateTweetCount(userId: userId, increment: false)
            return true
        } catch {
            errorMessage = "Failed to delete tweet: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Like Operations

    func loadUserLikes(userId: String) async {
        do {
            let likes: [Like] = try await client.database
                .from("likes")
                .select()
                .eq("user_id", value: userId)
                .execute()

            likedTweetIds = Set(likes.compactMap { $0.tweetId })
        } catch {
            print("Failed to load likes: \(error)")
        }
    }

    func toggleLike(tweetId: String, userId: String) async {
        let isCurrentlyLiked = likedTweetIds.contains(tweetId)

        do {
            if isCurrentlyLiked {
                // Unlike
                try await client.database
                    .from("likes")
                    .eq("user_id", value: userId)
                    .eq("tweet_id", value: tweetId)
                    .delete()

                likedTweetIds.remove(tweetId)
                try await updateLikeCount(tweetId: tweetId, increment: false)
            } else {
                // Like
                let likeInsert = LikeInsert(userId: userId, tweetId: tweetId)
                let _: LikeInsert = try await client.database
                    .from("likes")
                    .insert(likeInsert)

                likedTweetIds.insert(tweetId)
                try await updateLikeCount(tweetId: tweetId, increment: true)
            }

            // Refresh the specific tweet to get updated counts from server
            await onTweetUpdated?(tweetId)
        } catch {
            print("Failed to toggle like: \(error)")
        }
    }

    // MARK: - Bookmark Operations

    func loadUserBookmarks(userId: String) async {
        do {
            let bookmarks: [Bookmark] = try await client.database
                .from("bookmarks")
                .select()
                .eq("user_id", value: userId)
                .execute()

            bookmarkedTweetIds = Set(bookmarks.compactMap { $0.tweetId })
        } catch {
            print("Failed to load bookmarks: \(error)")
        }
    }

    func toggleBookmark(tweetId: String, userId: String) async {
        let isCurrentlyBookmarked = bookmarkedTweetIds.contains(tweetId)

        do {
            if isCurrentlyBookmarked {
                // Remove bookmark
                try await client.database
                    .from("bookmarks")
                    .eq("user_id", value: userId)
                    .eq("tweet_id", value: tweetId)
                    .delete()

                bookmarkedTweetIds.remove(tweetId)
            } else {
                // Add bookmark
                let bookmarkInsert = BookmarkInsert(userId: userId, tweetId: tweetId)
                let _: BookmarkInsert = try await client.database
                    .from("bookmarks")
                    .insert(bookmarkInsert)

                bookmarkedTweetIds.insert(tweetId)
            }
        } catch {
            print("Failed to toggle bookmark: \(error)")
        }
    }

    // MARK: - Helper Methods

    private func updateTweetCount(userId: String, increment: Bool) async throws {
        struct TweetsCountUpdate: Codable {
            let tweetsCount: Int

            enum CodingKeys: String, CodingKey {
                case tweetsCount = "tweets_count"
            }
        }

        let profiles: [Profile] = try await client.database
            .from("profiles")
            .select()
            .eq("user_id", value: userId)
            .execute()

        if let profile = profiles.first {
            let currentCount = profile.tweetsCount ?? 0
            let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)

            let _: [TweetsCountUpdate] = try await client.database
                .from("profiles")
                .eq("user_id", value: userId)
                .update(TweetsCountUpdate(tweetsCount: newCount))
        }
    }

    private func updateLikeCount(tweetId: String, increment: Bool) async throws {
        struct LikesCountUpdate: Codable {
            let likesCount: Int

            enum CodingKeys: String, CodingKey {
                case likesCount = "likes_count"
            }
        }

        let tweets: [Tweet] = try await client.database
            .from("tweets")
            .select()
            .eq("id", value: tweetId)
            .execute()

        if let tweet = tweets.first {
            let currentCount = tweet.likesCount ?? 0
            let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)

            let _: [LikesCountUpdate] = try await client.database
                .from("tweets")
                .eq("id", value: tweetId)
                .update(LikesCountUpdate(likesCount: newCount))
        }
    }

    private func updateReplyCount(tweetId: String, increment: Bool) async throws {
        struct RepliesCountUpdate: Codable {
            let repliesCount: Int

            enum CodingKeys: String, CodingKey {
                case repliesCount = "replies_count"
            }
        }

        let tweets: [Tweet] = try await client.database
            .from("tweets")
            .select()
            .eq("id", value: tweetId)
            .execute()

        if let tweet = tweets.first {
            let currentCount = tweet.repliesCount ?? 0
            let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)

            let _: [RepliesCountUpdate] = try await client.database
                .from("tweets")
                .eq("id", value: tweetId)
                .update(RepliesCountUpdate(repliesCount: newCount))
        }
    }
}
