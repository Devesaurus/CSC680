//
//  Page_One.swift
//  CHECK IN
//
//  Created by Deven Young on 5/8/25.
//
import SwiftUI
import FirebaseAuth

struct PageOneView: View {
    @ObservedObject var viewModel: EventViewModel
    @State private var selectedEvent: Event?
    @State private var showingEventDetail = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 50)
                    } else if viewModel.events.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No Events")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("Create an event to get started")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 50)
                    } else {
                        let now = Date()
                        let upcomingEvents = viewModel.events.filter { $0.date >= now }.sorted { $0.date < $1.date }
                        let pastEvents = viewModel.events.filter { $0.date < now }.sorted { $0.date > $1.date }
                        
                        VStack(spacing: 24) {
                            // Upcoming Events Section
                            if !upcomingEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Upcoming Events")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    ForEach(upcomingEvents) { event in
                                        EventCard(event: event, viewModel: viewModel)
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
                            
                            // Past Events Section
                            if !pastEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Past Events")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    ForEach(pastEvents) { event in
                                        EventCard(event: event, viewModel: viewModel)
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
                        }
                    }
                }
            }
            .navigationTitle("Events")
            .background(Color(.systemGroupedBackground))
            .onAppear {
                viewModel.loadEvents()
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
        .sheet(isPresented: $showingEventDetail, onDismiss: {
            DispatchQueue.main.async {
                selectedEvent = nil
                viewModel.clearSelection()
            }
        }) {
            if let event = selectedEvent {
                EventDetailView(event: event, viewModel: viewModel, isPresented: $showingEventDetail)
            }
        }
    }
}

struct EventCard: View {
    let event: Event
    let viewModel: EventViewModel
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                
                Spacer()
                
                // Delete button (only show for events created by current user)
                if event.createdBy == Auth.auth().currentUser?.uid {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.system(size: 18))
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .alert("Delete Event", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteEvent()
            }
        } message: {
            Text("Are you sure you want to delete this event? This action cannot be undone.")
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
    
    private func deleteEvent() {
        isDeleting = true
        
        Task {
            do {
                try await viewModel.deleteEvent(event)
                await MainActor.run {
                    isDeleting = false
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct EventDetailView: View {
    let event: Event
    @ObservedObject var viewModel: EventViewModel
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var showingInviteSheet = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var isAccepting = false
    @State private var hasAccepted = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Event Header
                    VStack(spacing: 16) {
                        Text(event.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text(formattedDate)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top)
                    
                    // Event Description
                    if !event.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(event.description)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    
                    // Event Details
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(icon: "person.fill", title: "Created By", value: viewModel.getCreatorName(for: event))
                        DetailRow(icon: "clock.fill", title: "Created", value: formattedCreatedDate)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    
                    // Accept Invitation Button
                    if shouldShowAcceptButton {
                        Button(action: acceptInvitation) {
                            if isAccepting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Accept Invitation")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.top)
                        .disabled(isAccepting)
                    } else if hasAccepted {
                        Text("You have accepted this invitation.")
                            .foregroundColor(.green)
                            .font(.subheadline)
                            .padding(.top)
                    }
                    
                    // Invite Button
                    Button(action: { showingInviteSheet = true }) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Invite People")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if event.createdBy == Auth.auth().currentUser?.uid {
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .disabled(isDeleting)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.clearSelection()
                        isPresented = false
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingInviteSheet) {
                InviteUsersView(event: event, viewModel: viewModel, isPresented: $showingInviteSheet)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Delete Event", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                Text("Are you sure you want to delete this event? This action cannot be undone.")
            }
            .onDisappear {
                if !isPresented {
                    DispatchQueue.main.async {
                        viewModel.clearSelection()
                    }
                }
            }
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
    
    private var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.createdAt)
    }
    
    private var shouldShowAcceptButton: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return event.invitedUsers.contains(currentUserId) && !event.acceptedUsers.contains(currentUserId) && !hasAccepted
    }
    
    private func acceptInvitation() {
        isAccepting = true
        Task {
            do {
                try await viewModel.acceptInvitation(event)
                await MainActor.run {
                    isAccepting = false
                    hasAccepted = true
                }
            } catch {
                await MainActor.run {
                    isAccepting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func deleteEvent() {
        isDeleting = true
        Task {
            do {
                try await viewModel.deleteEvent(event)
                await MainActor.run {
                    isDeleting = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct InviteUsersView: View {
    @State var event: Event
    @ObservedObject var viewModel: EventViewModel
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isInviting = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search users...", text: $searchText)
                        .onChange(of: searchText) { oldValue, newValue in
                            viewModel.searchUsers(query: newValue)
                        }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                if viewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No users found")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.searchResults.filter { $0.id != Auth.auth().currentUser?.uid }) { user in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.fullName)
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            if event.invitedUsers.contains(user.id) {
                                Text("Invited")
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                            } else {
                                Button(action: {
                                    inviteUser(user)
                                }) {
                                    if isInviting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    } else {
                                        Text("Invite")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .disabled(isInviting)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Invite Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func inviteUser(_ user: AppUser) {
        isInviting = true
        
        Task {
            do {
                try await viewModel.inviteUser(user, to: event)
                await MainActor.run {
                    // Optimistically update the local event's invitedUsers
                    event.invitedUsers.append(user.id)
                    isInviting = false
                    // Do not close the sheet automatically
                }
            } catch {
                await MainActor.run {
                    isInviting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
        }
    }
}
