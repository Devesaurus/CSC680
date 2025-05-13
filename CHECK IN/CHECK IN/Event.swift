//
//  Event.swift
//  CHECK IN
//
//  Created by Deven Young on 5/10/25.
//
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

struct Event: Identifiable, Equatable {
    var id: String
    var name: String
    var date: Date
    var description: String
    var createdBy: String
    var createdAt: Date
    var creatorName: String?
    var invitedUsers: [String] // Array of user IDs who are invited
    var acceptedUsers: [String] // Array of user IDs who have accepted the invitation
    
    var dictionary: [String: Any] {
        [
            "name": name,
            "date": Timestamp(date: date),
            "description": description,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "invitedUsers": invitedUsers,
            "acceptedUsers": acceptedUsers
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
        
        return Event(
            id: id,
            name: name,
            date: date,
            description: description,
            createdBy: createdBy,
            createdAt: createdAt,
            creatorName: nil,
            invitedUsers: invitedUsers,
            acceptedUsers: acceptedUsers
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
               lhs.acceptedUsers == rhs.acceptedUsers
    }
}

struct AppUser: Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

class EventViewModel: ObservableObject {
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
        // Check authentication state on initialization
        if Auth.auth().currentUser != nil {
            loadEvents()
            loadUserReminders()
        }
    }
    
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
            acceptedUsers: [] // Initialize with empty array of accepted users
        )
        
        try await db.collection("events").document(event.id).setData(event.dictionary)
    }
    
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
        
        // Set up the events listener directly
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
                    
                    // Filter events where user is creator, has accepted invitation, or is invited
                    self.events = documents.compactMap { document in
                        guard let event = Event.fromDictionary(document.data(), id: document.documentID) else {
                            return nil
                        }
                        
                        // Include event if user is creator, has accepted invitation, or is invited
                        return (event.createdBy == currentUserId || 
                                event.acceptedUsers.contains(currentUserId) || 
                                event.invitedUsers.contains(currentUserId)) ? event : nil
                    }
                    
                    // Load creator names for all events
                    self.loadCreatorNames()
                }
            }
    }
    
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
    
    func getCreatorName(for event: Event) -> String {
        return creatorNames[event.createdBy] ?? "Loading..."
    }
    
    func deleteEvent(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let db = Firestore.firestore()
        let eventRef = db.collection("events").document(event.id)
        
        // If user is the creator, remove them from both arrays
        if event.createdBy == currentUserId {
            try await eventRef.updateData([
                "createdBy": FieldValue.delete(),
                "acceptedUsers": FieldValue.arrayRemove([currentUserId])
            ])
        } else {
            // If user is not the creator, just remove them from acceptedUsers
            try await eventRef.updateData([
                "acceptedUsers": FieldValue.arrayRemove([currentUserId])
            ])
        }
        
        // Check if event should be deleted (no users linked)
        let updatedEvent = try await eventRef.getDocument()
        if let data = updatedEvent.data() {
            let acceptedUsers = data["acceptedUsers"] as? [String] ?? []
            let invitedUsers = data["invitedUsers"] as? [String] ?? []
            let createdBy = data["createdBy"] as? String
            
            // If no users are linked to the event, delete it
            if acceptedUsers.isEmpty && invitedUsers.isEmpty && createdBy == nil {
                try await eventRef.delete()
            }
        }
    }
    
    func updateEvent(_ event: Event) async throws {
        try await db.collection("events").document(event.id).updateData(event.dictionary)
    }
    
    func inviteUser(_ user: AppUser, to event: Event) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Check if user is already invited
        if event.invitedUsers.contains(user.id) {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User is already invited"])
        }
        
        // Check if user is inviting themselves
        if user.id == currentUser.uid {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot invite yourself to an event"])
        }
        
        // Update the event with the new invited user
        var updatedInvitedUsers = event.invitedUsers
        updatedInvitedUsers.append(user.id)
        
        try await db.collection("events").document(event.id).updateData([
            "invitedUsers": updatedInvitedUsers
        ])
        
        // Create a notification for the invited user
        try await db.collection("notifications").addDocument(data: [
            "type": "event_invite",
            "eventId": event.id,
            "eventName": event.name,
            "fromUserId": currentUser.uid,
            "toUserId": user.id,
            "createdAt": Timestamp(date: Date())
        ])
    }
    
    func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
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
    
    func acceptInvitation(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let db = Firestore.firestore()
        let eventRef = db.collection("events").document(event.id)
        
        try await eventRef.updateData([
            "acceptedUsers": FieldValue.arrayUnion([currentUserId])
        ])
    }
    
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
    
    func declineInvitation(_ event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Check if user is invited
        guard event.invitedUsers.contains(currentUserId) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You are not invited to this event"])
        }
        
        // Remove user from invitedUsers array
        var updatedInvitedUsers = event.invitedUsers
        updatedInvitedUsers.removeAll { $0 == currentUserId }
        
        try await db.collection("events").document(event.id).updateData([
            "invitedUsers": updatedInvitedUsers
        ])
    }
    
    // Add a method to clear the selected event and any related state
    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedEvent = nil
            self.searchResults = []
            self.showingInviteSheet = false
        }
    }
    
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
    
    func setReminder(for event: Event, at reminderTime: Date) async throws {
        print("EventViewModel: Starting setReminder for event: \(event.name)")
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("EventViewModel: User not authenticated")
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Only allow setting reminders for events you're part of
        guard event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId) else {
            print("EventViewModel: User not part of event")
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "You can only set reminders for events you're part of"])
        }
        
        // Ensure reminder time is before event time
        guard reminderTime < event.date else {
            print("EventViewModel: Reminder time after event time")
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reminder time must be before the event time"])
        }
        
        print("EventViewModel: Creating reminder document for event: \(event.id)")
        // Create or update the reminder document first
        let reminderRef = db.collection("userReminders").document("\(currentUserId)_\(event.id)")
        do {
            try await reminderRef.setData([
                "userId": currentUserId,
                "eventId": event.id,
                "reminderTime": Timestamp(date: reminderTime),
                "updatedAt": Timestamp(date: Date())
            ])
            print("EventViewModel: Successfully created reminder document")
            
            // Update the local userReminders dictionary immediately
            await MainActor.run {
                print("EventViewModel: Updating local reminders dictionary")
                self.userReminders[event.id] = reminderTime
                print("EventViewModel: Local reminders dictionary updated")
            }
        } catch {
            print("EventViewModel: Error creating reminder document: \(error.localizedDescription)")
            throw error
        }
        
        print("EventViewModel: Starting notification permission check")
        // Handle notification permissions asynchronously
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
    
    func removeReminder(for event: Event) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Only allow removing reminders for events you're part of
        guard event.createdBy == currentUserId || event.acceptedUsers.contains(currentUserId) else {
            throw NSError(domain: "EventError", code: 1, userInfo: [NSLocalizedDescriptionKey: "You can only remove reminders for events you're part of"])
        }
        
        // Delete the reminder document
        let reminderRef = db.collection("userReminders").document("\(currentUserId)_\(event.id)")
        try await reminderRef.delete()
        
        // Update the local userReminders dictionary
        let _ = await MainActor.run {
            self.userReminders.removeValue(forKey: event.id)
        }
        
        // Remove local notification
        removeLocalNotification(for: event)
    }
    
    func getReminderTime(for eventId: String) -> Date? {
        return userReminders[eventId]
    }
    
    private func removeLocalNotification(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["event-\(event.id)"])
    }
}

