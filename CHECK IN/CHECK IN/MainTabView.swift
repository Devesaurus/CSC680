import SwiftUI

struct MainAppView: View {
    // MARK: - Environment and State Objects
    // These are passed from ContentView or initialized if specific to this view tree

    // ViewModel for event-related data and operations
    @ObservedObject var eventVM: EventViewModel
    // ViewModel for profile-related data and operations
    @ObservedObject var profileVM: ProfileViewModel

    // MARK: - State Bindings
    // These states are controlled by ContentView and passed down

    // Binding to control the currently selected tab
    @Binding var selectedTab: Int
    // Binding to control the visibility of the create event sheet/popup
    @Binding var showingCreateEvent: Bool
    // Binding to control the visibility of the event detail sheet
    @Binding var showingEventDetail: Bool
    // Binding to manage the event selected for detail view
    @Binding var selectedEvent: Event?


    // MARK: - Body
    var body: some View {
        ZStack {
            // Tabbed interface for main sections of the app
            TabView(selection: $selectedTab) {
                // Home Tab
                NavigationStack {
                    HomeView(profileVM: profileVM, eventVM: eventVM)
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

                // Events Tab (assuming PageOneView is your events list)
                NavigationStack {
                    EventList(viewModel: eventVM)
                }
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }
                .tag(1)
                    
                // Friends Tab
                NavigationStack {
                    FriendsView()
                }
                .tabItem {
                    Label("Friends", systemImage: "person.2.fill")
                }
                .tag(2)
                    
                // Profile Tab
                NavigationStack {
                    ProfileView(viewModel: profileVM)
                }
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
                .tag(3)
            }
            .tint(.blue) // Sets the accent color for tab items and other interactive elements
            
            // Floating "Create Event" Button
            VStack {
                Spacer() // Pushes the button to the bottom
                Button(action: {
                    showingCreateEvent = true // Triggers the create event popup
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                        .background(Color(.systemBackground)) // Ensures button is visible on different backgrounds
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                }
                .offset(y: -30) // Adjusts vertical position slightly above the tab bar
            }
            
            // "Create Event" Popup/Modal View
            // This section is displayed conditionally when showingCreateEvent is true
            if showingCreateEvent {
                // Semi-transparent background overlay
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingCreateEvent = false // Dismiss popup on background tap
                    }
                
                // The actual view for creating an event
                CreateEventView(viewModel: eventVM, isPresented: $showingCreateEvent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Allows it to take up modal space
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                    .padding() // Adds padding around the CreateEventView
                    .transition(.move(edge: .bottom)) // Animation for appearance
                    .animation(.spring(), value: showingCreateEvent) // Spring animation
                    .onDisappear {
                        // Ensure state is reset if view disappears for other reasons
                        if showingCreateEvent { // Check to avoid issues if already set by tap
                           showingCreateEvent = false
                        }
                    }
            }
        }
        // .onAppear for MainAppView specific logic (if any) could go here.
        // .sheet for EventDetailView is now handled in ContentView since it's at a higher level.
    }
}
