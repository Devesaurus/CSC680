import FirebaseAuth
import Foundation
import SwiftUI

// Keeps track of whether a user is logged in
class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String = ""
    @Published var profileVM: ProfileViewModel?

    init() {
        self.user = Auth.auth().currentUser
    }
    
    func signUp(email: String, password: String) {
        print("Debug: Attempting to sign up with email: \(email)")
        // First, sign out any existing user
        try? Auth.auth().signOut()
        self.user = nil
        profileVM?.clearState()
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                print("Debug: Sign up error: \(error.localizedDescription)")
                print("Debug: Error code: \(error._code)")
                self?.errorMessage = error.localizedDescription
            } else {
                print("Debug: Sign up successful for user: \(result?.user.uid ?? "unknown")")
                self?.user = result?.user
            }
        }
    }

    func signIn(email: String, password: String) {
        print("Debug: Attempting to sign in with email: \(email)")
        // First, sign out any existing user
        try? Auth.auth().signOut()
        self.user = nil
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                print("Debug: Sign in error: \(error.localizedDescription)")
                self?.errorMessage = error.localizedDescription
            } else {
                print("Debug: Sign in successful for user: \(result?.user.uid ?? "unknown")")
                self?.user = result?.user
                // Load profile after successful sign in
                self?.profileVM?.loadProfile()
            }
        }
    }

    func signOut() {
        print("Debug: Signing out user")
        try? Auth.auth().signOut()
        self.user = nil
        profileVM?.clearState()
    }
}

