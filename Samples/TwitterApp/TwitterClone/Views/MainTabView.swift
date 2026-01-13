import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var feedViewModel = FeedViewModel()
    @StateObject private var tweetViewModel = TweetViewModel()

    @State private var selectedTab = 0
    @State private var showingCompose = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                FeedView()
                    .environmentObject(feedViewModel)
                    .environmentObject(tweetViewModel)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)

                SearchView()
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .tag(1)

                NotificationsView()
                    .tabItem {
                        Image(systemName: "bell.fill")
                        Text("Notifications")
                    }
                    .tag(2)

                ProfileView(userId: authViewModel.currentUser?.id ?? "")
                    .environmentObject(tweetViewModel)
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(3)
            }

            // Floating compose button
            Button(action: {
                showingCompose = true
            }) {
                Image(systemName: "plus")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 80)
        }
        .sheet(isPresented: $showingCompose) {
            ComposeView()
                .environmentObject(tweetViewModel)
                .environmentObject(feedViewModel)
        }
        .task {
            await feedViewModel.loadFeed()
            if let userId = authViewModel.currentUser?.id {
                await tweetViewModel.loadUserLikes(userId: userId)
                await tweetViewModel.loadUserBookmarks(userId: userId)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
