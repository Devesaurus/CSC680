import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import PhotosUI

struct UserProfile: Codable {
    var id: String
    var firstName: String
    var lastName: String
    var username: String
    var email: String
    var profileImageURL: String?
    var bio: String?
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedImage: PhotosPickerItem?
    @Published var profileImage: Image?
    
    private let db = Firestore.firestore()
    private var isInitialLoad = true
    
    init() {
        print("Debug: ProfileViewModel initialized")
        if Auth.auth().currentUser != nil {
            loadProfile()
        }
    }
    
    func clearState() {
        print("Debug: Clearing profile state")
        profile = nil
        isLoading = false
        errorMessage = nil
        selectedImage = nil
        profileImage = nil
        isInitialLoad = true
    }
    
    func loadProfile() {
        guard let userId = Auth.auth().currentUser?.uid,
              let email = Auth.auth().currentUser?.email else {
            print("Debug: No authenticated user found")
            return
        }
        
        print("Debug: Loading profile for user: \(userId)")
        isLoading = true
        
        // First check if the document exists
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("Debug: Error loading profile: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                if let data = snapshot?.data() {
                    print("Debug: Profile data found: \(data)")
                    let firstName = data["firstName"] as? String ?? ""
                    let lastName = data["lastName"] as? String ?? ""
                    let username = data["username"] as? String ?? ""
                    let email = data["email"] as? String ?? Auth.auth().currentUser?.email ?? ""
                    
                    print("Debug: Profile fields - firstName: '\(firstName)', lastName: '\(lastName)', username: '\(username)', email: '\(email)'")
                    
                    // Create profile with existing data
                    let newProfile = UserProfile(
                        id: userId,
                        firstName: firstName,
                        lastName: lastName,
                        username: username,
                        email: email,
                        profileImageURL: data["profileImageURL"] as? String,
                        bio: data["bio"] as? String
                    )
                    
                    // Always use the existing profile data
                    self.profile = newProfile
                } else {
                    print("Debug: No profile found, creating new profile")
                    self.createNewProfile(userId: userId, email: email)
                }
            }
        }
    }
    
    private func createNewProfile(userId: String, email: String) {
        // First check if there's any existing data
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                let existingData = snapshot?.data() ?? [:]
                
                // Only create a new profile if the document doesn't exist
                if snapshot?.exists == false {
                    let newProfile = UserProfile(
                        id: userId,
                        firstName: "",
                        lastName: "",
                        username: email.components(separatedBy: "@").first ?? "",
                        email: email,
                        profileImageURL: nil,
                        bio: nil
                    )
                    
                    let data: [String: Any] = [
                        "firstName": newProfile.firstName,
                        "lastName": newProfile.lastName,
                        "username": newProfile.username,
                        "email": newProfile.email,
                        "profileImageURL": newProfile.profileImageURL as Any,
                        "bio": newProfile.bio as Any,
                        "createdAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ]
                    
                    self?.db.collection("users").document(userId).setData(data) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = error.localizedDescription
                            } else {
                                self?.profile = newProfile
                            }
                        }
                    }
                } else {
                    // Use existing data
                    let existingProfile = UserProfile(
                        id: userId,
                        firstName: existingData["firstName"] as? String ?? "",
                        lastName: existingData["lastName"] as? String ?? "",
                        username: existingData["username"] as? String ?? email.components(separatedBy: "@").first ?? "",
                        email: existingData["email"] as? String ?? email,
                        profileImageURL: existingData["profileImageURL"] as? String,
                        bio: existingData["bio"] as? String
                    )
                    self?.profile = existingProfile
                }
            }
        }
    }
    
    func updateProfile(firstName: String, lastName: String, username: String, bio: String?) {
        guard let userId = Auth.auth().currentUser?.uid,
              let email = Auth.auth().currentUser?.email else { return }
        
        // Validate inputs
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please fill in all required fields"
            return
        }
        
        isLoading = true
        let data: [String: Any] = [
            "firstName": firstName,
            "lastName": lastName,
            "username": username,
            "email": email,
            "bio": bio ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Use setData with merge option to create or update the document
        db.collection("users").document(userId).setData(data, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    // Update the local profile immediately
                    if var currentProfile = self?.profile {
                        currentProfile.firstName = firstName
                        currentProfile.lastName = lastName
                        currentProfile.username = username
                        currentProfile.bio = bio
                        self?.profile = currentProfile
                    } else {
                        // Create a new profile object if it doesn't exist
                        self?.profile = UserProfile(
                            id: userId,
                            firstName: firstName,
                            lastName: lastName,
                            username: username,
                            email: email,
                            profileImageURL: nil,
                            bio: bio
                        )
                    }
                }
            }
        }
    }
    
    func updateProfileImage(_ image: UIImage) {
        // Implementation for uploading profile image to Firebase Storage
        // This would be implemented when we add Firebase Storage
    }
}

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isEditing = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var showingDiscardAlert = false
    @State private var hasUnsavedChanges = false
    @State private var showingLogoutAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Profile Image Section
                    VStack(spacing: 16) {
                        if let profileImage = viewModel.profileImage {
                            profileImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 2))
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        } else if let imageURL = viewModel.profile?.profileImageURL {
                            AsyncImage(url: URL(string: imageURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 2))
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 120, height: 120)
                                .foregroundColor(.gray)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                        
                        if isEditing {
                            PhotosPicker(selection: $viewModel.selectedImage,
                                       matching: .images) {
                                Text("Change Photo")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.top, 24)
                    
                    // Profile Information
                    VStack(spacing: 24) {
                        if isEditing {
                            ProfileEditView(
                                firstName: $firstName,
                                lastName: $lastName,
                                username: $username,
                                bio: $bio,
                                hasUnsavedChanges: $hasUnsavedChanges
                            )
                        } else {
                            ProfileInfoView(profile: viewModel.profile)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Logout Button
                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            if validateFields() {
                                viewModel.updateProfile(
                                    firstName: firstName,
                                    lastName: lastName,
                                    username: username,
                                    bio: bio
                                )
                                isEditing = false
                                hasUnsavedChanges = false
                            }
                        } else {
                            // Load current values into edit fields
                            firstName = viewModel.profile?.firstName ?? ""
                            lastName = viewModel.profile?.lastName ?? ""
                            username = viewModel.profile?.username ?? ""
                            bio = viewModel.profile?.bio ?? ""
                            isEditing = true
                        }
                    }
                    .font(.headline)
                }
                
                if isEditing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            if hasUnsavedChanges {
                                showingDiscardAlert = true
                            } else {
                                isEditing = false
                            }
                        }
                    }
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
            .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
                Button("Discard", role: .destructive) {
                    isEditing = false
                    hasUnsavedChanges = false
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .alert("Log Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    // Clear any unsaved changes
                    isEditing = false
                    hasUnsavedChanges = false
                    // Sign out
                    authVM.signOut()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
    }
    
    private func validateFields() -> Bool {
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedFirstName.isEmpty {
            viewModel.errorMessage = "First name is required"
            return false
        }
        if trimmedLastName.isEmpty {
            viewModel.errorMessage = "Last name is required"
            return false
        }
        if trimmedUsername.isEmpty {
            viewModel.errorMessage = "Username is required"
            return false
        }
        
        return true
    }
}

struct ProfileInfoView: View {
    let profile: UserProfile?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = profile {
                Group {
                    InfoRow(title: "First Name", value: profile.firstName)
                    InfoRow(title: "Last Name", value: profile.lastName)
                    InfoRow(title: "Username", value: profile.username)
                    InfoRow(title: "Email", value: profile.email)
                    if let bio = profile.bio, !bio.isEmpty {
                        InfoRow(title: "Bio", value: bio, isMultiline: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
    }
}

struct ProfileEditView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var username: String
    @Binding var bio: String
    @Binding var hasUnsavedChanges: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("First Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("*")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                TextField("First Name", text: $firstName)
                    .textFieldStyle(CustomTextFieldStyle())
                    .frame(height: 44)
                    .onChange(of: firstName) { _, _ in
                        hasUnsavedChanges = true
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Last Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("*")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                TextField("Last Name", text: $lastName)
                    .textFieldStyle(CustomTextFieldStyle())
                    .frame(height: 44)
                    .onChange(of: lastName) { _, _ in
                        hasUnsavedChanges = true
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Username")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("*")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                TextField("Username", text: $username)
                    .textFieldStyle(CustomTextFieldStyle())
                    .frame(height: 44)
                    .onChange(of: username) { _, _ in
                        hasUnsavedChanges = true
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Bio")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Bio", text: $bio, axis: .vertical)
                    .textFieldStyle(CustomTextFieldStyle())
                    .frame(minHeight: 44)
                    .lineLimit(3...6)
                    .onChange(of: bio) { _, _ in
                        hasUnsavedChanges = true
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var isMultiline: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: isMultiline ? nil : 44)
                .fixedSize(horizontal: false, vertical: isMultiline)
        }
    }
} 