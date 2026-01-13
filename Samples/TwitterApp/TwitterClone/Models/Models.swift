import Foundation

// MARK: - Profile Model
struct Profile: Codable, Identifiable, Equatable {
    let id: String?
    let userId: String
    let username: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let headerUrl: String?
    let location: String?
    let website: String?
    let followersCount: Int?
    let followingCount: Int?
    let tweetsCount: Int?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case headerUrl = "header_url"
        case location
        case website
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case tweetsCount = "tweets_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ProfileInsert: Codable {
    let userId: String
    let username: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
    }
}

struct ProfileUpdate: Codable {
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var headerUrl: String?
    var location: String?
    var website: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case headerUrl = "header_url"
        case location
        case website
    }
}

// MARK: - Tweet Model
struct Tweet: Codable, Identifiable, Equatable {
    let id: String?
    let userId: String
    let content: String
    let imageUrl: String?
    let likesCount: Int?
    let retweetsCount: Int?
    let repliesCount: Int?
    let parentId: String?
    let isRetweet: Bool?
    let originalTweetId: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case content
        case imageUrl = "image_url"
        case likesCount = "likes_count"
        case retweetsCount = "retweets_count"
        case repliesCount = "replies_count"
        case parentId = "parent_id"
        case isRetweet = "is_retweet"
        case originalTweetId = "original_tweet_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TweetInsert: Codable {
    let userId: String
    let content: String
    var imageUrl: String?
    var parentId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case content
        case imageUrl = "image_url"
        case parentId = "parent_id"
    }
}

// MARK: - Like Model
struct Like: Codable, Identifiable {
    let id: String?
    let userId: String
    let tweetId: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tweetId = "tweet_id"
        case createdAt = "created_at"
    }
}

struct LikeInsert: Codable {
    let userId: String
    let tweetId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case tweetId = "tweet_id"
    }
}

// MARK: - Follow Model
struct Follow: Codable, Identifiable {
    let id: String?
    let followerId: String
    let followingId: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case followerId = "follower_id"
        case followingId = "following_id"
        case createdAt = "created_at"
    }
}

struct FollowInsert: Codable {
    let followerId: String
    let followingId: String

    enum CodingKeys: String, CodingKey {
        case followerId = "follower_id"
        case followingId = "following_id"
    }
}

// MARK: - Bookmark Model
struct Bookmark: Codable, Identifiable {
    let id: String?
    let userId: String
    let tweetId: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tweetId = "tweet_id"
        case createdAt = "created_at"
    }
}

struct BookmarkInsert: Codable {
    let userId: String
    let tweetId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case tweetId = "tweet_id"
    }
}

// MARK: - Tweet with Author (for display)
struct TweetWithAuthor: Identifiable, Equatable {
    let tweet: Tweet
    let author: Profile

    var id: String? { tweet.id }

    static func == (lhs: TweetWithAuthor, rhs: TweetWithAuthor) -> Bool {
        lhs.tweet == rhs.tweet && lhs.author == rhs.author
    }
}
