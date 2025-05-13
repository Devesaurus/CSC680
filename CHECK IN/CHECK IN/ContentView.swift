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
                            
                        NavigationStack {
                            FriendsView()
                        }
                        .tabItem {
                            Label("Friends", systemImage: "person.2.fill")
                        }
                        .tag(2)
                            
                        NavigationStack {
                            ProfileView(viewModel: profileVM)
                        }
                        .tabItem {
                            Label("Profile", systemImage: "person.circle.fill")
                        }
                        .tag(3)
                    }
                    .tint(.blue)
                    
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


#Preview {
    ContentView().environmentObject(AuthViewModel())
}
