import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// Represents an event in the app
struct Event: Identifiable, Equatable {
    var id: String // Event ID for Database
    var name: String // Event name
    var date: Date // Date of the event
    var description: String // Description of the event
    var createdBy: String // Who created the event
    var createdAt: Date // When was the event created
    var creatorName: String? // Creator's name
    var invitedUsers: [String] // Array to store invited users
    var acceptedUsers: [String] // Array of users who have accepted invitations
    var checkedInUsers: [String] // Array of users who have checked in
    
    // TO send to DB
    var dictionary: [String: Any] {
        [
            "name": name,
            "date": Timestamp(date: date),
            "description": description,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "invitedUsers": invitedUsers,
            "acceptedUsers": acceptedUsers,
            "checkedInUsers": checkedInUsers
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any], id: String) -> Event? {
        guard let name = dict["name"] as? String,
              let date = (dict["date"] as? Timestamp)?.dateValue(),
              let description = dict["description"] as? String,
              let createdBy = dict["createdBy"] as? String,
              let createdAt = (dict["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        let invitedUsers = dict["invitedUsers"] as? [String] ?? []
        let acceptedUsers = dict["acceptedUsers"] as? [String] ?? []
        let checkedInUsers = dict["checkedInUsers"] as? [String] ?? []
        
        return Event(
            id: id,
            name: name,
            date: date,
            description: description,
            createdBy: createdBy,
            createdAt: createdAt,
            creatorName: nil,
            invitedUsers: invitedUsers,
            acceptedUsers: acceptedUsers,
            checkedInUsers: checkedInUsers
        )
    }
    
    static func == (lhs: Event, rhs: Event) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.date == rhs.date &&
               lhs.description == rhs.description &&
               lhs.createdBy == rhs.createdBy &&
               lhs.createdAt == rhs.createdAt &&
               lhs.creatorName == rhs.creatorName &&
               lhs.invitedUsers == rhs.invitedUsers &&
               lhs.acceptedUsers == rhs.acceptedUsers &&
               lhs.checkedInUsers == rhs.checkedInUsers
    }
}

// Represents a user in the app
struct AppUser: Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

// Manages event operations and views
class EventViewModel: ObservableObject {
    // Published properties for UI updates
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var creatorNames: [String: String] = [:]
    @Published var showingInviteSheet = false
    @Published var selectedEvent: Event?
    @Published var searchResults: [AppUser] = []
    @Published var isSearching = false
    @Published var userReminders: [String: Date] = [:] // eventId: reminderTime
    
    private let db = Firestore.firestore()
    
    init() {
        // Initialize and load data if user is authenticated
        if Auth.auth().currentUser != nil {
            loadEvents()
            loadUserReminders()
        }
    }
    
        // Create an event
        func createEvent(name: String, date: Date, description: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let event = Event(
            id: UUID().uuidString,
            name: name,
            date: date,
            description: description,
            createdBy: userId,
            createdAt: Date(),
            creatorName: nil,
            invitedUsers: [], // Initialize with empty array of invited users
            acceptedUsers: [], // Initialize with empty array of accepted users
            checkedInUsers: [] // Initialize with empty array of checked in users
        )
        
        try await db.collection("events").document(event.id).setData(event.dictionary)
    }
    
    // Loads the events for the current user
    func loadEvents() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "User not authenticated"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // Set up listener for events
        db.collection("events")
            .order(by: "date", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        print("Debug: Error loading events: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.errorMessage = "No events found"
                        return
                    }
                    
                    // Filter events for current user
                    self.events = documents.compactMap { document in
                        guard let event = Event.fromDictionary(document.data(), id: document.documentID) else {
                            return nil
                        }
                        
                        return (event.createdBy == currentUserId || 
                                event.acceptedUsers.contains(currentUserId) || 
                                event.invitedUsers.contains(currentUserId)) ? event : nil
                    }
                    
                    // Load creator names for all events
                    self.loadCreatorNames()
                }
            }
    }
        
    // Load creator names for the events
    private func loadCreatorNames() {
        let creatorIds = Set(events.map { $0.createdBy })
        
        for creatorId in creatorIds {
            if creatorNames[creatorId] == nil {
                db.collection("users").document(creatorId).getDocument { [weak self] snapshot, error in
                    if let data = snapshot?.data(),
                       let firstName = data["firstName"] as? String,
                       let lastName = data["lastName"] as? String {
                        DispatchQueue.main.async {
                            self?.creatorNames[creatorId] = "\(firstName) \(lastName)"
                        }
                    }
                }
            }
        }
    }
    
    // Gets the creator name for an event
    func getCreatorName(for event: Event) -> String {
        return creatorNames[event.createdBy] ?? "Loading..."
    }
        
    // Allows a user to leave an event, and potentially deletes the event if orphaned or if the creator leaves.
    func leaveEvent(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let eventRef = db.collection("events").document(event.id)
        
        // Step 1: Update Firestore by removing the user from accepted and invited lists.
        // This will trigger the snapshot listener in loadEvents to re-evaluate.
        try await eventRef.updateData([
            "acceptedUsers": FieldValue.arrayRemove([currentUserId]),
            "invitedUsers": FieldValue.arrayRemove([currentUserId])
        ])
        
        // Step 2: Check if the event should be deleted.
        // Re-fetch the event data AFTER the update to check its current state.
        let updatedEventSnapshot = try await eventRef.getDocument()
        
        // If the document doesn't exist after the update (e.g., already deleted by another process, or if the update itself led to its removal somehow),
        // the snapshot listener will handle it. Nothing more to do here for deletion.
        guard updatedEventSnapshot.exists, let updatedEventData = updatedEventSnapshot.data() else {
            print("Event document \(event.id) no longer exists or has no data after user removal attempt. Snapshot listener should handle UI.")
            return
        }
        
        let currentAcceptedUsers = updatedEventData["acceptedUsers"] as? [String] ?? []
        let currentInvitedUsers = updatedEventData["invitedUsers"] as? [String] ?? []
        let creatorId = updatedEventData["createdBy"] as? String
        
        // Define conditions for deleting the event:
        // 1. If the current user is the creator, their leaving implies deleting the event.
        // 2. OR If the event has no specific creator (creatorId is nil or empty) AND no one is accepted or invited, it's orphaned.
        let isCreatorLeaving = creatorId == currentUserId
        
        var shouldDeleteEvent = false
        if isCreatorLeaving {
            shouldDeleteEvent = true
        } else if (creatorId == nil || creatorId!.isEmpty) && currentAcceptedUsers.isEmpty && currentInvitedUsers.isEmpty {
            // If no designated creator, and it's now empty, it's orphaned.
            shouldDeleteEvent = true
        }
        // If there IS a creator, and the current user is NOT the creator, the event is NOT deleted just because the last attendee leaves.
        // It remains for the creator.
        
        if shouldDeleteEvent {
            print("Deleting event \(event.id) as it meets deletion criteria.")
            try await eventRef.delete()
            // The snapshot listener in loadEvents will see the deletion and remove it from self.events.
        }
        // No direct local manipulation of self.events is needed here.
        // The snapshot listener is the source of truth for the UI.
    }
    
    // Updates an event
    func updateEvent(_ event: Event) async throws {
        try await db.collection("events").document(event.id).updateData(event.dictionary)
    }
    
    // Invites a user to an event
    func inviteUser(_ user: AppUser, to event: Event) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Validate invitation
        if event.invitedUsers.contains(user.id) {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User is already invited"])
        }
        
        if user.id == currentUser.uid {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot invite yourself to an event"])
        }
        
        // Update event with new invited user
        var updatedInvitedUsers = event.invitedUsers
        updatedInvitedUsers.append(user.id)
        
        try await db.collection("events").document(event.id).updateData([
            "invitedUsers": updatedInvitedUsers
        ])
        
        // Create notification for invited user
        try await db.collection("notifications").addDocument(data: [
            "type": "event_invite",
            "eventId": event.id,
            "eventName": event.name,
            "fromUserId": currentUser.uid,
            "toUserId": user.id,
            "createdAt": Timestamp(date: Date())
        ])
    }
    
    // Searches for users to invite
    func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // Runs through the database
        db.collection("users")
            .whereField("firstName", isGreaterThanOrEqualTo: query)
            .whereField("firstName", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: 10)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isSearching = false
                    
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }
                    
                    self?.searchResults = snapshot?.documents.compactMap { document in
                        guard let firstName = document.data()["firstName"] as? String,
                              let lastName = document.data()["lastName"] as? String else {
                            return nil
                        }
                        return AppUser(id: document.documentID, firstName: firstName, lastName: lastName)
                    } ?? []
                }
            }
    }
    
    // Accepts an invitation to an event (adds it to their account)
    func acceptInvitation(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let db = Firestore.firestore()
        let eventRef = db.collection("events").document(event.id)
        
        try await eventRef.updateData([
            "acceptedUsers": FieldValue.arrayUnion([currentUserId])
        ])
        
        // Update local state
        await MainActor.run {
            if let index = self.events.firstIndex(where: { $0.id == event.id }) {
                var updatedEvent = self.events[index]
                updatedEvent.acceptedUsers.append(currentUserId)
                self.events[index] = updatedEvent
            }
        }
    }
    
    // Removes an event from a users account
    func removeFromEvent(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let db = Firestore.firestore()
        let eventRef = db.collection("events").document(event.id)
        
        try await eventRef.updateData([
            "acceptedUsers": FieldValue.arrayRemove([currentUserId])
        ])
    }
    
    // Removes an event from a users invited list
    func declineInvitation(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Validate invitation
        guard event.invitedUsers.contains(currentUserId) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You are not invited to this event"])
        }
        
        // Remove user from invitedUsers array
        var updatedInvitedUsers = event.invitedUsers
        updatedInvitedUsers.removeAll { $0 == currentUserId }
        
        try await db.collection("events").document(event.id).updateData([
            "invitedUsers": updatedInvitedUsers
        ])
        
        // Update local state
        await MainActor.run {
            if let index = self.events.firstIndex(where: { $0.id == event.id }) {
                var updatedEvent = self.events[index]
                updatedEvent.invitedUsers.removeAll { $0 == currentUserId }
                self.events[index] = updatedEvent
            }
        }
    }
    
    // Clear UI state
    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedEvent = nil
            self.searchResults = []
            self.showingInviteSheet = false
        }
    }
        
    // Loads reminders for events (user specific)
    private func loadUserReminders() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("userReminders")
            .whereField("userId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error loading reminders: \(error.localizedDescription)")
                    return
                }
                
                var newReminders: [String: Date] = [:]
                snapshot?.documents.forEach { document in
                    if let eventId = document.data()["eventId"] as? String,
                       let reminderTime = (document.data()["reminderTime"] as? Timestamp)?.dateValue() {
                        newReminders[eventId] = reminderTime
                    }
                }
                
                DispatchQueue.main.async {
                    self.userReminders = newReminders
                }
            }
    }
    
    // Allows users to set reminders for certain events
    func setReminder(for event: Event, at reminderTime: Date) async throws {
        print("EventViewModel: Starting setReminder for event: \(event.name)")
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("EventViewModel: User not authenticated")
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Validate reminder
        guard event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId) else {
            print("EventViewModel: User not part of event")
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "You can only set reminders for events you're part of"])
        }
        
        guard reminderTime < event.date else {
            print("EventViewModel: Reminder time after event time")
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reminder time must be before the event time"])
        }
        
        // Create or update reminder
        let reminderRef = db.collection("userReminders").document("\(currentUserId)_\(event.id)")
        do {
            try await reminderRef.setData([
                "userId": currentUserId,
                "eventId": event.id,
                "reminderTime": Timestamp(date: reminderTime),
                "updatedAt": Timestamp(date: Date())
            ])
            print("EventViewModel: Successfully created reminder document")
            
            // Update local state
            await MainActor.run {
                print("EventViewModel: Updating local reminders dictionary")
                self.userReminders[event.id] = reminderTime
                print("EventViewModel: Local reminders dictionary updated")
            }
        } catch {
            print("EventViewModel: Error creating reminder document: \(error.localizedDescription)")
            throw error
        }
        
        // Handle notification permissions
        Task {
            print("EventViewModel: Checking notification permissions")
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            print("EventViewModel: Current notification settings: \(settings.authorizationStatus.rawValue)")
            
            if settings.authorizationStatus != .authorized {
                print("EventViewModel: Requesting notification permission")
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    print("EventViewModel: Notification permission response: \(granted)")
                    if granted {
                        print("EventViewModel: Notification permission granted")
                        print("EventViewModel: Scheduling local notification")
                        scheduleReminder(for: event, at: reminderTime)
                    } else {
                        print("EventViewModel: Notification permission denied")
                    }
                } catch {
                    print("EventViewModel: Error requesting permission: \(error.localizedDescription)")
                }
            } else {
                print("EventViewModel: Notification permission already granted")
                print("EventViewModel: Scheduling local notification")
                scheduleReminder(for: event, at: reminderTime)
            }
        }
        
        print("EventViewModel: Successfully completed setReminder")
    }
    
    // Schedules a local notification based on a reminder
    private func scheduleReminder(for event: Event, at reminderTime: Date) {
        print("EventViewModel: Starting scheduleReminder for event: \(event.name)")
        let content = UNMutableNotificationContent()
        content.title = "Event Reminder"
        content.body = "\(event.name) is coming up soon!"
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "event-\(event.id)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("EventViewModel: Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("EventViewModel: Successfully scheduled notification")
            }
        }
    }
    
    // Removes a reminder for an event
    func removeReminder(for event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Validate reminder removal
        guard event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId) else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "You can only remove reminders for events you're part of"])
        }
        
        // Delete reminder document
        let reminderRef = db.collection("userReminders").document("\(currentUserId)_\(event.id)")
        try await reminderRef.delete()
        
        // Update local state
        let _ = await MainActor.run {
            self.userReminders.removeValue(forKey: event.id)
        }
        
        // Remove local notification
        removeLocalNotification(for: event)
    }
    
    // Gets the user reminder time for an event
    func getReminderTime(for eventId: String) -> Date? {
        return userReminders[eventId]
    }
    
    // Removes local notification for an event
    private func removeLocalNotification(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["event-\(event.id)"])
    }
    
    // Allows a user to check in to an event
    func checkInToEvent(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        let eventRef = db.collection("events").document(event.id)
        try await eventRef.updateData([
            "checkedInUsers": FieldValue.arrayUnion([currentUserId])
        ])
    }

    // Allows a user to revoke their check-in from an event
    func revokeCheckInFromEvent(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        let eventRef = db.collection("events").document(event.id)
        try await eventRef.updateData([
            "checkedInUsers": FieldValue.arrayRemove([currentUserId])
        ])
    }
}

