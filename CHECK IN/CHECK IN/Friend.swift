import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// Represents a friend object
// Users will be able to have friends (other users)
struct Friend: Identifiable, Codable {
    var id: String
    var name: String
    var email: String
    var profileImageURL: String?
    var status: FriendStatus
    
    enum FriendStatus: String, Codable {
        case pending
        case accepted
        case rejected
    }
}

// Friend 
class FriendViewModel: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var pendingRequests: [Friend] = []
    @Published var searchResults: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sentRequests: Set<String> = [] // Track sent requests
    
    private let db = Firestore.firestore()
    
    init() {
        loadFriends()
        listenForFriendRequests()
        loadSentRequests()
    }
    
    private func loadSentRequests() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: Friend.FriendStatus.pending.rawValue)
            .getDocuments { [weak self] snapshot, error in
                if let documents = snapshot?.documents {
                    self?.sentRequests = Set(documents.compactMap { $0.data()["toUserId"] as? String })
                }
            }
    }
    
    func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: query)
            .whereField("username", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: 10)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    
                    self?.searchResults = snapshot?.documents.compactMap { document in
                        guard let email = document.data()["email"] as? String,
                              let firstName = document.data()["firstName"] as? String,
                              let lastName = document.data()["lastName"] as? String else {
                            return nil
                        }
                        
                        let name = "\(firstName) \(lastName)"
                        
                        return Friend(
                            id: document.documentID,
                            name: name,
                            email: email,
                            profileImageURL: document.data()["profileImageURL"] as? String,
                            status: .pending
                        )
                    } ?? []
                }
            }
    }
    
    func sendFriendRequest(to friend: Friend) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        if friend.id == currentUserId {
            self.errorMessage = "You cannot send a friend request to yourself"
            return
        }
        
        // Check if request already exists
        db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: currentUserId)
            .whereField("toUserId", isEqualTo: friend.id)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                // If no existing request, create new one
                if snapshot?.documents.isEmpty ?? true {
                    let request = [
                        "fromUserId": currentUserId,
                        "toUserId": friend.id,
                        "status": Friend.FriendStatus.pending.rawValue,
                        "timestamp": FieldValue.serverTimestamp()
                    ] as [String: Any]
                    
                    self?.db.collection("friendRequests").addDocument(data: request) { error in
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                        } else {
                            // Add to sent requests
                            DispatchQueue.main.async {
                                self?.sentRequests.insert(friend.id)
                            }
                        }
                    }
                } else {
                    self?.errorMessage = "Friend request already sent"
                }
            }
    }
    
    func acceptFriendRequest(_ request: Friend) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Update request status
        db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: request.id)
            .whereField("toUserId", isEqualTo: currentUserId)
            .getDocuments { [weak self] snapshot, error in
                guard let document = snapshot?.documents.first else { return }
                
                // Update request status
                self?.db.collection("friendRequests").document(document.documentID).updateData([
                    "status": Friend.FriendStatus.accepted.rawValue
                ])
                
                // Add to friends collection for both users
                let friendData = [
                    "userId": currentUserId,
                    "friendId": request.id,
                    "timestamp": FieldValue.serverTimestamp()
                ]
                
                self?.db.collection("friends").addDocument(data: friendData)
            }
    }
    
    func rejectFriendRequest(_ request: Friend) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: request.id)
            .whereField("toUserId", isEqualTo: currentUserId)
            .getDocuments { [weak self] snapshot, error in
                guard let document = snapshot?.documents.first else { return }
                
                self?.db.collection("friendRequests").document(document.documentID).updateData([
                    "status": Friend.FriendStatus.rejected.rawValue
                ])
            }
    }
    
    func loadFriends() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        db.collection("friends")
            .whereField("userId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    
                    self?.processFriendData(snapshot?.documents ?? [])
                }
            }
    }
    
    private func listenForFriendRequests() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("friendRequests")
            .whereField("toUserId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: Friend.FriendStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                self?.processFriendRequests(snapshot?.documents ?? [])
            }
    }
    
    private func processFriendData(_ documents: [QueryDocumentSnapshot]) {
        let friendIds = documents.compactMap { $0.data()["friendId"] as? String }
        
        guard !friendIds.isEmpty else {
            self.friends = []
            return
        }
        
        db.collection("users")
            .whereField(FieldPath.documentID(), in: friendIds)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.friends = documents.compactMap { document in
                    guard let email = document.data()["email"] as? String,
                          let firstName = document.data()["firstName"] as? String,
                          let lastName = document.data()["lastName"] as? String else {
                        return nil
                    }
                    
                    let name = "\(firstName) \(lastName)"
                    
                    return Friend(
                        id: document.documentID,
                        name: name,
                        email: email,
                        profileImageURL: document.data()["profileImageURL"] as? String,
                        status: .accepted
                    )
                }
            }
    }
    
    private func processFriendRequests(_ documents: [QueryDocumentSnapshot]) {
        let requestorIds = documents.compactMap { $0.data()["fromUserId"] as? String }
        
        guard !requestorIds.isEmpty else {
            self.pendingRequests = []
            return
        }
        
        db.collection("users")
            .whereField(FieldPath.documentID(), in: requestorIds)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.pendingRequests = documents.compactMap { document in
                    guard let email = document.data()["email"] as? String,
                          let firstName = document.data()["firstName"] as? String,
                          let lastName = document.data()["lastName"] as? String else {
                        return nil
                    }
                    
                    let name = "\(firstName) \(lastName)"
                    
                    return Friend(
                        id: document.documentID,
                        name: name,
                        email: email,
                        profileImageURL: document.data()["profileImageURL"] as? String,
                        status: .pending
                    )
                }
            }
    }
}

struct FriendsView: View {
    @StateObject private var viewModel = FriendViewModel()
    @State private var searchText = ""
    @State private var showingSearchResults = false
    @State private var showingAddFriend = false
    
    var body: some View {
        VStack(spacing: 0) {
            if showingSearchResults {
                // Search Results
                List(viewModel.searchResults) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.name)
                                .font(.headline)
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        if viewModel.sentRequests.contains(user.id) {
                            Text("Pending")
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        } else {
                            Button(action: {
                                viewModel.sendFriendRequest(to: user)
                            }) {
                                Text("Add Friend")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Pending Requests
                        if !viewModel.pendingRequests.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Friend Requests")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(viewModel.pendingRequests) { request in
                                    FriendRequestCard(request: request, viewModel: viewModel)
                                }
                            }
                        }
                        
                        // Friends List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Friends")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            if viewModel.friends.isEmpty {
                                Text("No friends yet")
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 32)
                            } else {
                                ForEach(viewModel.friends) { friend in
                                    FriendCard(friend: friend)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Friends")
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSearchResults = true
                    searchText = ""
                }) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18))
                }
            }
            
            if showingSearchResults {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingSearchResults = false
                        searchText = ""
                    }
                }
            }
        }
        .searchable(text: $searchText, isPresented: $showingSearchResults, prompt: "Search users...")
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                viewModel.searchUsers(query: newValue)
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

struct FriendRequestCard: View {
    let request: Friend
    let viewModel: FriendViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(request.name)
                    .font(.headline)
                Text(request.email)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.acceptFriendRequest(request)
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                
                Button(action: {
                    viewModel.rejectFriendRequest(request)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct FriendCard: View {
    let friend: Friend
    
    var body: some View {
        HStack {
            if let imageURL = friend.profileImageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.gray)
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.headline)
                Text(friend.email)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
} 


