import SwiftUI
import PhotosUI

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var tweetViewModel: TweetViewModel
    @EnvironmentObject var feedViewModel: FeedViewModel

    let replyTo: TweetWithAuthor?

    @State private var content = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?

    init(replyTo: TweetWithAuthor? = nil) {
        self.replyTo = replyTo
    }

    private var isReply: Bool { replyTo != nil }
    private var maxCharacters = 280

    var remainingCharacters: Int {
        maxCharacters - content.count
    }

    var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.count <= maxCharacters
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Reply context
                if let replyTo = replyTo {
                    HStack(spacing: 8) {
                        Text("Replying to")
                            .foregroundColor(.secondary)
                        Text("@\(replyTo.author.username)")
                            .foregroundColor(.blue)
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()
                }

                ScrollView {
                    HStack(alignment: .top, spacing: 12) {
                        // Avatar
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
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            // Text input
                            TextField(isReply ? "Tweet your reply" : "What's happening?", text: $content, axis: .vertical)
                                .font(.body)
                                .lineLimit(10...20)

                            // Selected image preview
                            if let imageData = selectedImageData,
                               let uiImage = UIImage(data: imageData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxHeight: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))

                                    Button(action: {
                                        selectedImageData = nil
                                        selectedItem = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    .padding(8)
                                }
                            }
                        }
                    }
                    .padding()
                }

                Divider()

                // Bottom toolbar
                HStack {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                selectedImageData = data
                            }
                        }
                    }

                    Button(action: {}) {
                        Image(systemName: "gif")
                            .font(.title3)
                    }
                    .foregroundColor(.blue)
                    .disabled(true)

                    Button(action: {}) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title3)
                    }
                    .foregroundColor(.blue)
                    .disabled(true)

                    Button(action: {}) {
                        Image(systemName: "location")
                            .font(.title3)
                    }
                    .foregroundColor(.blue)
                    .disabled(true)

                    Spacer()

                    // Character count
                    Text("\(remainingCharacters)")
                        .font(.subheadline)
                        .foregroundColor(remainingCharacters < 0 ? .red : (remainingCharacters < 20 ? .orange : .secondary))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .navigationTitle(isReply ? "Reply" : "New Tweet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: postTweet) {
                        if tweetViewModel.isPosting {
                            ProgressView()
                        } else {
                            Text(isReply ? "Reply" : "Tweet")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!isValid || tweetViewModel.isPosting)
                }
            }
        }
    }

    private func postTweet() {
        guard let userId = authViewModel.currentUser?.id else { return }

        Task {
            let success = await tweetViewModel.createTweet(
                content: content,
                imageData: selectedImageData,
                userId: userId,
                parentId: replyTo?.tweet.id
            )

            if success {
                await feedViewModel.refreshFeed()
                dismiss()
            }
        }
    }
}

#Preview {
    ComposeView()
        .environmentObject(AuthViewModel())
        .environmentObject(TweetViewModel())
        .environmentObject(FeedViewModel())
}
