import SwiftUI

struct MainAppView: View {
    
    // ViewModel for event related data and operations
    @ObservedObject var eventVM: EventViewModel
    // ViewModel for profile related data and operations
    @ObservedObject var profileVM: ProfileViewModel

    // These states are controlled by ContentView and passed down
    
    // Binding to control the currently selected tab
    @Binding var selectedTab: Int
    // Binding to control the visibility of the create event sheet/popup
    @Binding var showingCreateEvent: Bool
    // Binding to control the visibility of the event detail sheet
    @Binding var showingEventDetail: Bool
    // Binding to manage the event selected for detail view
    @Binding var selectedEvent: Event?

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
            .tint(.blue)
            
            // Floating "Create Event" Button
            VStack {
                Spacer()
                Button(action: {
                    showingCreateEvent = true // Triggers the create event popup
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
            
            // "Create Event" Popup View
            // This section is displayed conditionally when showingCreateEvent is true
            if showingCreateEvent {
                Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                showingCreateEvent = false // Dismiss popup on background tap
            }
                
                // The actual view for creating an event
            CreateEventView(viewModel: eventVM, isPresented: $showingCreateEvent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                    .padding()
                    .transition(.move(edge: .bottom))
                    .animation(.spring(), value: showingCreateEvent)
                    .onDisappear {
                    // Ensure state is reset if view disappears for other reasons
                    if showingCreateEvent {
                       showingCreateEvent = false
                    }
                }
            }
        }
    }
}
