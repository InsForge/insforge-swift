import Foundation
import SwiftUI
import InsForge
import InsForgeStorage

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var userTweets: [TweetWithAuthor] = []
    @Published var isLoading = false
    @Published var isFollowing = false
    @Published var errorMessage: String?

    private var client: InsForgeClient { insforge }

    func loadProfile(userId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("user_id", value: userId)
                .execute()

            if let profile = profiles.first {
                self.profile = profile
            }
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
    }

    func loadProfileByUsername(username: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let profiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("username", value: username)
                .execute()

            if let profile = profiles.first {
                self.profile = profile
            }
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
    }

    func checkFollowStatus(followerId: String, followingId: String) async {
        do {
            let follows: [Follow] = try await client.database
                .from("follows")
                .select()
                .eq("follower_id", value: followerId)
                .eq("following_id", value: followingId)
                .execute()

            isFollowing = !follows.isEmpty
        } catch {
            print("Failed to check follow status: \(error)")
        }
    }

    func toggleFollow(followerId: String, followingId: String) async {
        do {
            if isFollowing {
                // Unfollow
                try await client.database
                    .from("follows")
                    .eq("follower_id", value: followerId)
                    .eq("following_id", value: followingId)
                    .delete()

                isFollowing = false
                await updateFollowCounts(followerId: followerId, followingId: followingId, increment: false)
            } else {
                // Follow
                let followInsert = FollowInsert(followerId: followerId, followingId: followingId)
                let _: FollowInsert = try await client.database
                    .from("follows")
                    .insert(followInsert)

                isFollowing = true
                await updateFollowCounts(followerId: followerId, followingId: followingId, increment: true)
            }

            // Reload profile to get updated counts
            if let userId = profile?.userId {
                await loadProfile(userId: userId)
            }
        } catch {
            errorMessage = "Failed to toggle follow: \(error.localizedDescription)"
        }
    }

    private func updateFollowCounts(followerId: String, followingId: String, increment: Bool) async {
        struct FollowingCountUpdate: Codable {
            let followingCount: Int

            enum CodingKeys: String, CodingKey {
                case followingCount = "following_count"
            }
        }

        struct FollowersCountUpdate: Codable {
            let followersCount: Int

            enum CodingKeys: String, CodingKey {
                case followersCount = "followers_count"
            }
        }

        do {
            // Update follower's following count
            let followerProfiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("user_id", value: followerId)
                .execute()

            if let followerProfile = followerProfiles.first {
                let currentCount = followerProfile.followingCount ?? 0
                let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)

                let _: [FollowingCountUpdate] = try await client.database
                    .from("profiles")
                    .eq("user_id", value: followerId)
                    .update(FollowingCountUpdate(followingCount: newCount))
            }

            // Update following's followers count
            let followingProfiles: [Profile] = try await client.database
                .from("profiles")
                .select()
                .eq("user_id", value: followingId)
                .execute()

            if let followingProfile = followingProfiles.first {
                let currentCount = followingProfile.followersCount ?? 0
                let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)

                let _: [FollowersCountUpdate] = try await client.database
                    .from("profiles")
                    .eq("user_id", value: followingId)
                    .update(FollowersCountUpdate(followersCount: newCount))
            }
        } catch {
            print("Failed to update follow counts: \(error)")
        }
    }

    func getFollowers(userId: String) async -> [Profile] {
        do {
            let follows: [Follow] = try await client.database
                .from("follows")
                .select()
                .eq("following_id", value: userId)
                .execute()

            var followers: [Profile] = []
            for follow in follows {
                let profiles: [Profile] = try await client.database
                    .from("profiles")
                    .select()
                    .eq("user_id", value: follow.followerId)
                    .execute()

                if let profile = profiles.first {
                    followers.append(profile)
                }
            }

            return followers
        } catch {
            print("Failed to get followers: \(error)")
            return []
        }
    }

    func getFollowing(userId: String) async -> [Profile] {
        do {
            let follows: [Follow] = try await client.database
                .from("follows")
                .select()
                .eq("follower_id", value: userId)
                .execute()

            var following: [Profile] = []
            for follow in follows {
                let profiles: [Profile] = try await client.database
                    .from("profiles")
                    .select()
                    .eq("user_id", value: follow.followingId)
                    .execute()

                if let profile = profiles.first {
                    following.append(profile)
                }
            }

            return following
        } catch {
            print("Failed to get following: \(error)")
            return []
        }
    }

    func uploadAvatar(imageData: Data, userId: String) async -> String? {
        do {
            let fileName = "\(userId)/avatar.jpg"
            let file = try await client.storage
                .from("avatars")
                .upload(
                    path: fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )

            struct AvatarUpdate: Codable {
                let avatarUrl: String

                enum CodingKeys: String, CodingKey {
                    case avatarUrl = "avatar_url"
                }
            }

            let _: [AvatarUpdate] = try await client.database
                .from("profiles")
                .eq("user_id", value: userId)
                .update(AvatarUpdate(avatarUrl: file.url))

            await loadProfile(userId: userId)
            return file.url
        } catch {
            errorMessage = "Failed to upload avatar: \(error.localizedDescription)"
            return nil
        }
    }

    func uploadHeader(imageData: Data, userId: String) async -> String? {
        do {
            let fileName = "\(userId)/header.jpg"
            let file = try await client.storage
                .from("headers")
                .upload(
                    path: fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )

            struct HeaderUpdate: Codable {
                let headerUrl: String

                enum CodingKeys: String, CodingKey {
                    case headerUrl = "header_url"
                }
            }

            let _: [HeaderUpdate] = try await client.database
                .from("profiles")
                .eq("user_id", value: userId)
                .update(HeaderUpdate(headerUrl: file.url))

            await loadProfile(userId: userId)
            return file.url
        } catch {
            errorMessage = "Failed to upload header: \(error.localizedDescription)"
            return nil
        }
    }
}
