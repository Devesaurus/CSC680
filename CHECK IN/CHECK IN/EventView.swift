import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EventList: View {
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
                        let upcomingEvents = viewModel.events
                            .filter { event in
                                guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
                                return event.date >= now && 
                                       (event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId))
                            }
                            .sorted { $0.date < $1.date }
                        let pastEvents = viewModel.events
                            .filter { event in
                                guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
                                return event.date < now && 
                                       (event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId))
                            }
                            .sorted { $0.date > $1.date }
                        
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
    @State private var showingRemoveAlert = false
    @State private var isRemoving = false
    
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
                
                // Remove button (show for all events the user is part of)
                if isUserPartOfEvent {
                    Button(action: {
                        showingRemoveAlert = true
                    }) {
                        Image(systemName: "person.fill.xmark")
                            .foregroundColor(.red)
                            .font(.system(size: 18))
                    }
                    .disabled(isRemoving)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .alert("Remove Event", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeFromEvent()
            }
        } message: {
            Text("Are you sure you want to remove this event from your list?")
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
    
    private var isUserPartOfEvent: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId)
    }
    
    private func removeFromEvent() {
        isRemoving = true
        
        Task {
            do {
                try await viewModel.deleteEvent(event)
                await MainActor.run {
                    isRemoving = false
                }
            } catch {
                await MainActor.run {
                    isRemoving = false
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ReminderSheetView: View {
    let event: Event
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = EventViewModel()
    @State private var selectedReminderTime: Date
    @State private var isSettingReminder = false
    @State private var errorMessage: String?
    var onReminderSet: () -> Void
    
    init(event: Event, onReminderSet: @escaping () -> Void) {
        self.event = event
        self.onReminderSet = onReminderSet
        // Set initial reminder time to 1 hour before event
        _selectedReminderTime = State(initialValue: Calendar.current.date(byAdding: .hour, value: -1, to: event.date) ?? event.date)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Set Reminder")
                    .font(.title)
                    .padding(.top)
                
                DatePicker(
                    "Reminder Time",
                    selection: $selectedReminderTime,
                    in: Date()...event.date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Button(action: {
                    Task {
                        isSettingReminder = true
                        errorMessage = nil
                        
                        do {
                            try await viewModel.setReminder(for: event, at: selectedReminderTime)
                            await MainActor.run {
                                onReminderSet() // Call the callback to refresh parent view
                                dismiss() // Dismiss the sheet after setting reminder
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        
                        isSettingReminder = false
                    }
                }) {
                    if isSettingReminder {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Set Reminder")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSettingReminder)
                .padding()
                
                Spacer()
            }
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
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
    @State private var showingRemoveAlert = false
    @State private var isRemoving = false
    @State private var isAccepting = false
    @State private var hasAccepted = false
    @State private var showingReminderSheet = false
    @State private var isSettingReminder = false
    @State private var currentEvent: Event
    @State private var currentReminderTime: Date?
    
    init(event: Event, viewModel: EventViewModel, isPresented: Binding<Bool>) {
        self.event = event
        self.viewModel = viewModel
        self._isPresented = isPresented
        self._currentEvent = State(initialValue: event)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Event Header
                    VStack(spacing: 16) {
                        Text(currentEvent.name)
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
                    if !currentEvent.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(currentEvent.description)
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
                        DetailRow(icon: "person.fill", title: "Created By", value: viewModel.getCreatorName(for: currentEvent))
                        DetailRow(icon: "clock.fill", title: "Created", value: formattedCreatedDate)
                        DetailRow(icon: "bell.fill", title: "Remind me at", value: currentReminderTime.map(formattedReminderTime) ?? "Never")
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
                    } else if isUserPartOfEvent {
                        VStack(spacing: 16) {
                            // Reminder Button
                            Button(action: {
                                if currentReminderTime != nil {
                                    removeReminder()
                                } else {
                                    showingReminderSheet = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: currentReminderTime != nil ? "bell.slash.fill" : "bell.fill")
                                    Text(currentReminderTime != nil ? "Remove Reminder" : "Set Reminder")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                            }
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .disabled(isSettingReminder)
                            
                            // Remove from Events Button
                            Button(action: {
                                showingRemoveAlert = true
                            }) {
                                if isRemoving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Text("Remove from My Events")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .disabled(isRemoving)
                            
                            // Invite Button (only show if user is creator)
                            if currentEvent.createdBy == Auth.auth().currentUser?.uid {
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
                            }
                        }
                        .padding(.top, 32)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.clearSelection()
                        isPresented = false
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingInviteSheet) {
                InviteUsersView(event: currentEvent, viewModel: viewModel, isPresented: $showingInviteSheet)
            }
            .sheet(isPresented: $showingReminderSheet) {
                ReminderSheetView(event: currentEvent) {
                    // Force a refresh by reloading the reminder time
                    loadReminderTime()
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Remove Event", isPresented: $showingRemoveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeFromEvent()
                }
            } message: {
                Text("Are you sure you want to remove this event from your list?")
            }
            .onAppear {
                loadReminderTime()
            }
            .onChange(of: currentEvent.id) { _, _ in
                loadReminderTime()
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
        return formatter.string(from: currentEvent.date)
    }
    
    private var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: currentEvent.createdAt)
    }
    
    private var shouldShowAcceptButton: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return currentEvent.invitedUsers.contains(currentUserId) && !currentEvent.acceptedUsers.contains(currentUserId) && !hasAccepted
    }
    
    private var isUserPartOfEvent: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return currentEvent.createdBy == currentUserId || currentEvent.acceptedUsers.contains(currentUserId)
    }
    
    private func acceptInvitation() {
        isAccepting = true
        Task {
            do {
                try await viewModel.acceptInvitation(currentEvent)
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
    
    private func removeFromEvent() {
        isRemoving = true
        Task {
            do {
                try await viewModel.deleteEvent(currentEvent)
                await MainActor.run {
                    isRemoving = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isRemoving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func formattedReminderTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func loadReminderTime() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let reminderRef = db.collection("userReminders").document("\(currentUserId)_\(currentEvent.id)")
        
        reminderRef.getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let reminderTime = (data["reminderTime"] as? Timestamp)?.dateValue() {
                DispatchQueue.main.async {
                    self.currentReminderTime = reminderTime
                }
            } else {
                DispatchQueue.main.async {
                    self.currentReminderTime = nil
                }
            }
        }
    }
    
    private func removeReminder() {
        isSettingReminder = true
        print("Removing reminder for event: \(currentEvent.name)")
        
        Task {
            do {
                try await viewModel.removeReminder(for: currentEvent)
                await MainActor.run {
                    print("Successfully removed reminder")
                    isSettingReminder = false
                    currentReminderTime = nil
                }
            } catch {
                print("Error removing reminder: \(error.localizedDescription)")
                await MainActor.run {
                    isSettingReminder = false
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
