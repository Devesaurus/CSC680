import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @State private var isAnimating = false
    @State private var selectedEvent: Event?
    @State private var showingEventDetail = false
    @ObservedObject var profileVM: ProfileViewModel
    @ObservedObject var eventVM: EventViewModel
    
    // Home page of the app
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
                            .font(.system(size: 20, weight: .medium))
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
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Upcoming Events")
                            .font(.title3)
                            .padding(.horizontal)

                        if upcomingEvents.isEmpty {
                            ZStack {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 80))
                                    .foregroundColor(Color.gray.opacity(0.1))
                                Text("No upcoming events yet.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        } else {
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
                    }
                    .padding(.vertical)
                    
                    // Event Invitations Section
                    let pendingInvitations = eventVM.events
                        .filter { event in
                            guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
                            return event.invitedUsers.contains(currentUserId) && 
                                   !event.acceptedUsers.contains(currentUserId)
                        }
                        .sorted { $0.date < $1.date }
                        .prefix(2) // Limit to first 2 invitations
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Event Invitations")
                            .font(.title3)
                            .padding(.horizontal)

                        if pendingInvitations.isEmpty {
                            ZStack {
                                Image(systemName: "envelope.open.badge.clock")
                                    .font(.system(size: 80))
                                    .foregroundColor(Color.gray.opacity(0.1))
                                Text("No pending invitations at the moment.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        } else {
                            ForEach(Array(pendingInvitations)) { event in
                                EventInvitationCard(event: event, viewModel: eventVM)
                            }
                        }
                    }
                    .padding(.vertical)
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
    
    // Generate a personalized welcome message
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

#Preview {
    HomeView(profileVM: ProfileViewModel(), eventVM: EventViewModel()).environmentObject(AuthViewModel())
}
