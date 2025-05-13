//
//  ContentView.swift
//  CHECK IN
//
//  Created by Deven Young on 4/29/25.
//
import SwiftUI
import FirebaseAuth
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var eventVM = EventViewModel()
    @StateObject private var profileVM = ProfileViewModel()
    @State private var selectedTab = 0
    @State private var showingCreateEvent = false
    @State private var showingEventDetail = false
    @State private var selectedEvent: Event?

    var body: some View {
        if authVM.user != nil {
            if profileVM.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            } else if let profile = profileVM.profile,
                      !profile.firstName.isEmpty &&
                      !profile.lastName.isEmpty &&
                      !profile.username.isEmpty &&
                      !profile.email.isEmpty {
                // Main app view
                ZStack {
                    TabView(selection: $selectedTab) {
                        HomeView(profileVM: profileVM, eventVM: eventVM)
                            .tabItem {
                                Image(systemName: "house.fill")
                                    .foregroundColor(selectedTab == 0 ? .black : .gray)
                                Text("Home")
                            }
                            .tag(0)

                        PageOneView(viewModel: eventVM)
                            .tabItem {
                                Image(systemName: "calendar")
                                Text("Events")
                            }
                            .tag(1)
                            
                        FriendsView()
                            .tabItem {
                                Image(systemName: "person.2.fill")
                                Text("Friends")
                            }
                            .tag(2)
                            
                        ProfileView(viewModel: profileVM)
                            .tabItem {
                                Image(systemName: "person.circle.fill")
                                Text("Profile")
                            }
                            .tag(3)
                    }
                    
                    // Create Event Button
                    VStack {
                        Spacer()
                        Button(action: {
                            showingCreateEvent = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.blue)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                        .offset(y: -30)
                    }
                    
                    // Create Event Popup
                    if showingCreateEvent {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                showingCreateEvent = false
                            }
                        
                        CreateEventView(viewModel: eventVM, isPresented: $showingCreateEvent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                            .padding()
                            .transition(.move(edge: .bottom))
                            .animation(.spring(), value: showingCreateEvent)
                            .onDisappear {
                                showingCreateEvent = false
                            }
                    }
                }
                .onAppear {
                    eventVM.loadEvents()
                    authVM.profileVM = profileVM
                    requestNotificationPermission()
                }
                .sheet(isPresented: $showingEventDetail, onDismiss: {
                    DispatchQueue.main.async {
                        selectedEvent = nil
                        eventVM.clearSelection()
                    }
                }) {
                    if let event = selectedEvent {
                        EventDetailView(event: event, viewModel: eventVM, isPresented: $showingEventDetail)
                    }
                }
            } else {
                // Profile completion view
                ProfileCompletionView(profileVM: profileVM)
            }
        } else {
            LoginView()
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }
        }
    }
}

struct HomeView: View {
    @State private var isAnimating = false
    @State private var selectedEvent: Event?
    @State private var showingEventDetail = false
    @ObservedObject var profileVM: ProfileViewModel
    @ObservedObject var eventVM: EventViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Welcome Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(welcomeMessage)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(formattedDate)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    // Upcoming Events Section
                    let upcomingEvents = eventVM.events
                        .filter { event in
                            guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
                            return event.date > Date() && 
                                   (event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId))
                        }
                        .sorted { $0.date < $1.date }
                        .prefix(2) // Limit to first 2 events
                    
                    if !upcomingEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Upcoming Events")
                                .font(.headline)
                                .padding(.horizontal)
                            ForEach(Array(upcomingEvents)) { event in
                                EventCard(event: event, viewModel: eventVM)
                                    .onTapGesture {
                                        selectedEvent = nil
                                        DispatchQueue.main.async {
                                            selectedEvent = event
                                            showingEventDetail = true
                                        }
                                    }
                            }
                        }
                        .padding(.vertical)
                    }
                    
                    // Event Invitations Section
                    let pendingInvitations = eventVM.events
                        .filter { event in
                            guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
                            return event.invitedUsers.contains(currentUserId) && 
                                   !event.acceptedUsers.contains(currentUserId)
                        }
                        .sorted { $0.date < $1.date }
                        .prefix(2) // Limit to first 2 invitations
                    
                    if !pendingInvitations.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Event Invitations")
                                .font(.headline)
                                .padding(.horizontal)
                            ForEach(Array(pendingInvitations)) { event in
                                EventInvitationCard(event: event, viewModel: eventVM)
                            }
                        }
                        .padding(.vertical)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .onAppear {
                eventVM.loadEvents()
            }
            .sheet(isPresented: $showingEventDetail, onDismiss: {
                DispatchQueue.main.async {
                    selectedEvent = nil
                    eventVM.clearSelection()
                }
            }) {
                if let event = selectedEvent {
                    EventDetailView(event: event, viewModel: eventVM, isPresented: $showingEventDetail)
                }
            }
        }
    }
    
    private var welcomeMessage: String {
        if let firstName = profileVM.profile?.firstName, !firstName.isEmpty {
            return "Welcome, \(firstName)"
        }
        return "Welcome"
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: Date())
    }
}

struct UpcomingEventCard: View {
    let event: Event
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Event Name
            Text(event.name)
                .font(.headline)
            
            // Event Date
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Event Description
            if !event.description.isEmpty {
                Text(event.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
}

struct EventInvitationCard: View {
    let event: Event
    @ObservedObject var viewModel: EventViewModel
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var shouldRemove = false
    
    var body: some View {
        if !shouldRemove {
            VStack(alignment: .leading, spacing: 12) {
                // Event Name
                Text(event.name)
                    .font(.headline)
                
                // Event Date
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Event Description
                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: acceptInvitation) {
                        if isAccepting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Accept")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isAccepting || isDeclining)
                    
                    Button(action: declineInvitation) {
                        if isDeclining {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Decline")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isAccepting || isDeclining)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
    
    private func acceptInvitation() {
        isAccepting = true
        Task {
            do {
                try await viewModel.acceptInvitation(event)
                await MainActor.run {
                    isAccepting = false
                    shouldRemove = true
                }
            } catch {
                await MainActor.run {
                    isAccepting = false
                    // Handle error if needed
                }
            }
        }
    }
    
    private func declineInvitation() {
        isDeclining = true
        Task {
            do {
                try await viewModel.declineInvitation(event)
                await MainActor.run {
                    isDeclining = false
                    shouldRemove = true
                }
            } catch {
                await MainActor.run {
                    isDeclining = false
                    // Handle error if needed
                }
            }
        }
    }
}

struct PageTwoView: View {
    var body: some View {
        Text("This is Page 2")
            .font(.title)
            .navigationTitle("Page 2")
    }
}

struct CheckInView: View {
    var body: some View {
        VStack {
            Text("CHECK IN")
                .font(.largeTitle)
            HStack {
                Button("YES") {
                    print("YES")
                }
                .frame(width: 130, height: 130)
                .font(.headline)
                .border(Color.blue, width: 2)

                Button("NO") {
                    print("NO")
                }
                .frame(width: 130, height: 130)
                .font(.headline)
                .border(Color.blue, width: 2)
            }
        }
        .padding()
    }
}

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EventViewModel
    @State private var eventName: String = ""
    @State private var eventDate: Date = Date()
    @State private var eventDescription: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isCreating = false
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 20)
                    
                    // Event Name
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Event Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("*")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                        TextField("Enter event name", text: $eventName)
                            .textFieldStyle(CustomTextFieldStyle())
                            .frame(height: 44)
                            .frame(width: 280)
                    }
                    
                    // Event Date
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Event Date")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("*")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                        HStack(spacing: 0) {
                            DatePicker("", selection: $eventDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .frame(width: 140)
                            
                            DatePicker("", selection: $eventDate, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .frame(width: 140)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(height: 44)
                        .frame(width: 280)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    // Event Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter event description", text: $eventDescription, axis: .vertical)
                            .textFieldStyle(CustomTextFieldStyle())
                            .frame(minHeight: 44)
                            .frame(width: 280)
                            .lineLimit(3...6)
                    }
                    
                    // Create Button
                    Button(action: createEvent) {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Create Event")
                                .font(.headline)
                        }
                    }
                    .frame(width: 280)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                    .disabled(isCreating)
                    .padding(.top, 16)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isCreating)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createEvent() {
        let trimmedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            errorMessage = "Event name is required"
            showingError = true
            return
        }
        
        if eventDate < Date() {
            errorMessage = "Event date must be in the future"
            showingError = true
            return
        }
        
        isCreating = true
        
        Task {
            do {
                try await viewModel.createEvent(
                    name: trimmedName,
                    date: eventDate,
                    description: trimmedDescription
                )
                await MainActor.run {
                    isCreating = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct ProfileCompletionView: View {
    @ObservedObject var profileVM: ProfileViewModel
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Welcome Message
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Complete Your Profile")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Please provide your information to continue")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Profile Form
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("First Name", text: $firstName)
                                .textFieldStyle(CustomTextFieldStyle())
                                .frame(height: 44)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Last Name", text: $lastName)
                                .textFieldStyle(CustomTextFieldStyle())
                                .frame(height: 44)
                        }
                        
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
                    
                    // Save Button
                    Button(action: saveProfile) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Continue")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .disabled(isSaving || !isFormValid)
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: profileVM.errorMessage) { _, newValue in
                if let error = newValue {
                    errorMessage = error
                    showingError = true
                    isSaving = false
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
    
    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveProfile() {
        guard isFormValid else { return }
        
        isSaving = true
        
        profileVM.updateProfile(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: nil
        )
    }
}

#Preview {
    ContentView().environmentObject(AuthViewModel())
}
