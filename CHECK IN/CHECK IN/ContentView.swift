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
        Group {
            if authVM.user != nil {
                if profileVM.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight:
                        .infinity)
                        .background(Color.black.opacity(0.1))
                }
                MainAppView(
                    eventVM: eventVM,
                    profileVM: profileVM,
                    selectedTab: $selectedTab,
                    showingCreateEvent: $showingCreateEvent,
                    showingEventDetail: $showingEventDetail,
                    selectedEvent: $selectedEvent
                )
            } else {
                LoginView()
            }
        }
        .onChange(of: authVM.user) { _, newUser in
            if newUser != nil {
                print("Debug: authVM.user changed, user is now logged in. Calling loadProfile.")
                profileVM.loadProfile()
            } else {
                print("Debug: authVM.user changed, user is now logged out. Clearing profile state.")
                profileVM.clearState() // Clear profile data on logout
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(AuthViewModel())
}
