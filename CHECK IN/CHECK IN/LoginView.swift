//
//  LoginView.swift
//  CHECK IN
//
//  Created by Deven Young on 5/10/25.
//
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignup = false

    var body: some View {
        VStack(spacing: 20) {
            Text(isSignup ? "Sign Up" : "Login")
                .font(.largeTitle)
                .bold()

            TextField("Email", text: $email)
                .autocapitalization(.none)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            if !authVM.errorMessage.isEmpty {
                Text(authVM.errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Button(action: {
                if isSignup {
                    authVM.signUp(email: email, password: password)
                } else {
                    authVM.signIn(email: email, password: password)
                }
            }) {
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
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
