import SwiftUI

struct NotificationsView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tabs
                Picker("Notifications", selection: $selectedTab) {
                    Text("All").tag(0)
                    Text("Mentions").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Content
                if selectedTab == 0 {
                    AllNotificationsView()
                } else {
                    MentionsView()
                }
            }
            .navigationTitle("Notifications")
        }
    }
}

struct AllNotificationsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Placeholder notifications
                ForEach(0..<5, id: \.self) { index in
                    NotificationRowView(type: NotificationType.allCases[index % NotificationType.allCases.count])
                    Divider()
                }
            }
        }
    }
}

struct MentionsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "at")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("No mentions yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When someone mentions you, it'll show up here.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

enum NotificationType: CaseIterable {
    case like
    case retweet
    case follow
    case reply
    case mention

    var icon: String {
        switch self {
        case .like: return "heart.fill"
        case .retweet: return "arrow.2.squarepath"
        case .follow: return "person.fill"
        case .reply: return "bubble.left.fill"
        case .mention: return "at"
        }
    }

    var color: Color {
        switch self {
        case .like: return .red
        case .retweet: return .green
        case .follow: return .blue
        case .reply: return .blue
        case .mention: return .purple
        }
    }

    var message: String {
        switch self {
        case .like: return "liked your Tweet"
        case .retweet: return "retweeted your Tweet"
        case .follow: return "followed you"
        case .reply: return "replied to your Tweet"
        case .mention: return "mentioned you"
        }
    }
}

struct NotificationRowView: View {
    let type: NotificationType

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(type.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 8) {
                // User avatar placeholder
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)

                Text("**User** \(type.message)")

                if type == .like || type == .retweet || type == .reply {
                    Text("This is a sample tweet content that was interacted with.")
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    NotificationsView()
}
