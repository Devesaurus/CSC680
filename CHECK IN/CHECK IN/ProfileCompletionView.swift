import SwiftUI

struct ProfileCompletionView: View {
    // ViewModel that handles profile data and operations
    @ObservedObject var profileVM: ProfileViewModel
    
    // State variables for form fields
    @State public var firstName = ""      // User's first name input
    @State public var lastName = ""       // User's last name input
    @State public var username = ""       // User's username input
    @State public var showingError = false // Controls error alert visibility
    @State public var errorMessage = ""   // Stores error message to display
    @State public var isSaving = false    // Tracks if profile is being saved
    @State public var keyboardHeight: CGFloat = 0 // Tracks keyboard height for layout
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Displays welcome message and icon
                    VStack(spacing: 16) {
                        // Large profile icon
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        // Title text
                        Text("Complete Your Profile")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        // Subtitle text
                        Text("Please provide your information to continue")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Form section
                    VStack(spacing: 20) {
                        // First name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("First Name", text: $firstName)
                                .textFieldStyle(CustomTextFieldStyle())
                                .frame(height: 44)
                        }
                        
                        // Last name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Last Name", text: $lastName)
                                .textFieldStyle(CustomTextFieldStyle())
                                .frame(height: 44)
                        }
                        
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Username", text: $username)
                                .textFieldStyle(CustomTextFieldStyle())
                                .frame(height: 44)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)
                    
                    // Button to save profile info
                    Button(action: saveProfile) {
                        if isSaving {
                            // Show loading indicator while saving
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            // Show "Continue" text when not saving
                            Text("Continue")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Color.blue : Color.gray) // Blue when valid, gray when invalid
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .disabled(isSaving || !isFormValid) // Disable button while saving or if form is invalid
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            // Error alert configuration
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            // Monitor for error messages from ViewModel
            .onChange(of: profileVM.errorMessage) { _, newValue in
                if let error = newValue {
                    errorMessage = error
                    showingError = true
                    isSaving = false
                }
            }
            .ignoresSafeArea(.keyboard) // Allow content to move with keyboard
        }
    }
    
    // Checks if form is valid
    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Saves the profile
    private func saveProfile() {
        guard isFormValid else { return }
        
        isSaving = true
        
        // Update profile through ViewModel
        profileVM.updateProfile(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: nil
        )
    }
}
