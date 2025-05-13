//
//  LoginView.swift
//  CHECK IN
//
//  Created by Deven Young on 5/10/25.
//
import SwiftUI

struct LoginView: View {
    // State variables for form fields and view state
    @EnvironmentObject var authVM: AuthViewModel
    @State private var email = "" // Email
    @State private var password = "" // Password
    @State private var isSignup = false
    
    // Login view
    var body: some View {
        VStack(spacing: 20) {
            // Title that changes based on current mode (Login/Sign Up)
            Text(isSignup ? "Sign Up" : "Login")
                .font(.largeTitle)
                .bold()
            
            TextField("Email", text: $email)
                .autocapitalization(.none)
                .textContentType(.emailAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            SecureField("Password", text: $password)
                .textContentType(isSignup ? .newPassword : .password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            // Error message display (if any)
            if !authVM.errorMessage.isEmpty {
                Text(authVM.errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            // Either sign in or sign up
            Button(action: {
                if isSignup {
                    authVM.signUp(email: email, password: password)
                } else {
                    authVM.signIn(email: email, password: password)
                }
            }) {
                // Displays differ based on whether they are creating an account or logging in
                Text(isSignup ? "Create Account" : "Log In")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
            Button(action: {
                isSignup.toggle()
            }) {
                Text(isSignup ? "Already have an account? Log in" : "Don't have an account? Sign up")
                    .font(.footnote)
            }
        }
        .padding()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}

