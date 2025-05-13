//
//  Event.swift
//  CHECK IN
//
//  Created by Deven Young on 5/10/25.
//
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

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
        return [
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
    
    private let db = Firestore.firestore()
    
    init() {
        // Check authentication state on initialization
        if Auth.auth().currentUser != nil {
            loadEvents()
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
        try await db.collection("events").document(event.id).delete()
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
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Check if user is invited
        guard event.invitedUsers.contains(currentUserId) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You are not invited to this event"])
        }
        
        // Check if user has already accepted
        guard !event.acceptedUsers.contains(currentUserId) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You have already accepted this invitation"])
        }
        
        // Add user to acceptedUsers array
        var updatedAcceptedUsers = event.acceptedUsers
        updatedAcceptedUsers.append(currentUserId)
        
        try await db.collection("events").document(event.id).updateData([
            "acceptedUsers": updatedAcceptedUsers
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
}

