import SwiftUI
import PhotosUI

struct ProfileView: View {
    let userId: String

    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var tweetViewModel: TweetViewModel
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var feedViewModel = FeedViewModel()

    @State private var selectedTab = 0
    @State private var displayedTweets: [TweetWithAuthor] = []
    @State private var showingEditProfile = false
    @State private var isLoadingContent = true

    var isCurrentUser: Bool {
        authViewModel.currentUser?.id == userId
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                ZStack(alignment: .bottomLeading) {
                    // Header image
                    if let headerUrl = profileViewModel.profile?.headerUrl,
                       let url = URL(string: headerUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Rectangle()
                                .fill(Color.blue.opacity(0.3))
                        }
                        .frame(height: 150)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(height: 150)
                    }

                    // Avatar
                    if let avatarUrl = profileViewModel.profile?.avatarUrl,
                       let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 4))
                        .offset(x: 16, y: 40)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 4))
                            .offset(x: 16, y: 40)
                    }
                }

                // Profile info
                VStack(alignment: .leading, spacing: 12) {
                    // Action buttons
                    HStack {
                        Spacer()

                        if isCurrentUser {
                            Button("Edit profile") {
                                showingEditProfile = true
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(profileViewModel.isFollowing ? "Following" : "Follow") {
                                guard let currentUserId = authViewModel.currentUser?.id else { return }
                                Task {
                                    await profileViewModel.toggleFollow(
                                        followerId: currentUserId,
                                        followingId: userId
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(profileViewModel.isFollowing ? .gray : .blue)
                        }
                    }
                    .padding(.top, 50)

                    // Name and username
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileViewModel.profile?.displayName ?? "Loading...")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("@\(profileViewModel.profile?.username ?? "")")
                            .foregroundColor(.secondary)
                    }

                    // Bio
                    if let bio = profileViewModel.profile?.bio, !bio.isEmpty {
                        Text(bio)
                    }

                    // Location and website
                    HStack(spacing: 16) {
                        if let location = profileViewModel.profile?.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "location")
                                Text(location)
                            }
                            .foregroundColor(.secondary)
                        }

                        if let website = profileViewModel.profile?.website, !website.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text(website)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .font(.subheadline)

                    // Join date
                    if let createdAt = profileViewModel.profile?.createdAt {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text("Joined \(formatJoinDate(createdAt))")
                        }
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    }

                    // Follow counts
                    HStack(spacing: 20) {
                        NavigationLink(destination: FollowListView(userId: userId, showFollowers: false)) {
                            HStack(spacing: 4) {
                                Text("\(profileViewModel.profile?.followingCount ?? 0)")
                                    .fontWeight(.semibold)
                                Text("Following")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: FollowListView(userId: userId, showFollowers: true)) {
                            HStack(spacing: 4) {
                                Text("\(profileViewModel.profile?.followersCount ?? 0)")
                                    .fontWeight(.semibold)
                                Text("Followers")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.subheadline)
                }
                .padding()

                // Tabs
                Picker("Content", selection: $selectedTab) {
                    Text("Tweets").tag(0)
                    Text("Replies").tag(1)
                    Text("Likes").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Divider()
                    .padding(.top, 8)

                // Content
                if isLoadingContent {
                    ProgressView()
                        .padding(.top, 40)
                } else if displayedTweets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: emptyStateIcon)
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text(emptyStateMessage)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedTweets) { tweet in
                            TweetRowView(
                                tweetWithAuthor: tweet,
                                currentUserId: authViewModel.currentUser?.id ?? ""
                            )
                            .environmentObject(tweetViewModel)

                            Divider()
                        }
                    }
                }

                // Sign Out button (only for current user)
                if isCurrentUser {
                    Button(role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .padding(.horizontal)
                    .padding(.top, 30)
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCurrentUser {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            Task {
                                await authViewModel.signOut()
                            }
                        }) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environmentObject(profileViewModel)
        }
        .task {
            await loadProfileData()
        }
        .task(id: selectedTab) {
            await loadTabContent()
        }
        .refreshable {
            await loadProfileData()
            await loadTabContent()
        }
    }

    private func loadProfileData() async {
        await profileViewModel.loadProfile(userId: userId)

        if let currentUserId = authViewModel.currentUser?.id, !isCurrentUser {
            await profileViewModel.checkFollowStatus(followerId: currentUserId, followingId: userId)
        }
    }

    private func loadTabContent() async {
        isLoadingContent = true

        switch selectedTab {
        case 0: // Tweets
            displayedTweets = await feedViewModel.loadUserTweets(userId: userId)
        case 1: // Replies
            displayedTweets = await feedViewModel.loadUserReplies(userId: userId)
        case 2: // Likes
            displayedTweets = await feedViewModel.loadUserLikedTweets(userId: userId)
        default:
            displayedTweets = []
        }

        isLoadingContent = false
    }

    private var emptyStateIcon: String {
        switch selectedTab {
        case 0: return "text.bubble"
        case 1: return "arrowshape.turn.up.left"
        case 2: return "heart"
        default: return "text.bubble"
        }
    }

    private var emptyStateMessage: String {
        switch selectedTab {
        case 0: return "No tweets yet"
        case 1: return "No replies yet"
        case 2: return "No likes yet"
        default: return "No content"
        }
    }

    private func formatJoinDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var profileViewModel: ProfileViewModel

    @State private var displayName = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var website = ""
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedHeaderItem: PhotosPickerItem?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        HStack {
                            Text("Avatar")
                            Spacer()
                            if let avatarUrl = profileViewModel.profile?.avatarUrl,
                               let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .onChange(of: selectedAvatarItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let userId = authViewModel.currentUser?.id {
                                _ = await profileViewModel.uploadAvatar(imageData: data, userId: userId)
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedHeaderItem, matching: .images) {
                        HStack {
                            Text("Header")
                            Spacer()
                            Image(systemName: "photo")
                                .foregroundColor(.blue)
                        }
                    }
                    .onChange(of: selectedHeaderItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let userId = authViewModel.currentUser?.id {
                                _ = await profileViewModel.uploadHeader(imageData: data, userId: userId)
                            }
                        }
                    }
                }

                Section {
                    TextField("Display Name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Location", text: $location)
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .onAppear {
                displayName = profileViewModel.profile?.displayName ?? ""
                bio = profileViewModel.profile?.bio ?? ""
                location = profileViewModel.profile?.location ?? ""
                website = profileViewModel.profile?.website ?? ""
            }
        }
    }

    private func saveProfile() {
        isSaving = true

        Task {
            let update = ProfileUpdate(
                displayName: displayName.isEmpty ? nil : displayName,
                bio: bio.isEmpty ? nil : bio,
                avatarUrl: nil,
                headerUrl: nil,
                location: location.isEmpty ? nil : location,
                website: website.isEmpty ? nil : website
            )

            await authViewModel.updateProfile(update)
            isSaving = false
            dismiss()
        }
    }
}

struct FollowListView: View {
    let userId: String
    let showFollowers: Bool

    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var profiles: [Profile] = []
    @State private var isLoading = true

    var body: some View {
        List(profiles) { profile in
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
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(showFollowers ? "Followers" : "Following")
        .overlay {
            if isLoading {
                ProgressView()
            } else if profiles.isEmpty {
                VStack {
                    Image(systemName: showFollowers ? "person.2" : "person.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text(showFollowers ? "No followers yet" : "Not following anyone")
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            if showFollowers {
                profiles = await profileViewModel.getFollowers(userId: userId)
            } else {
                profiles = await profileViewModel.getFollowing(userId: userId)
            }
            isLoading = false
        }
    }
}


#Preview {
    NavigationStack {
        ProfileView(userId: "test-user-id")
            .environmentObject(AuthViewModel())
            .environmentObject(TweetViewModel())
    }
}
