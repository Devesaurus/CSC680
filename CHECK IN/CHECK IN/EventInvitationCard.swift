import SwiftUI
import FirebaseAuth

struct EventInvitationCard: View {
    let event: Event
    @ObservedObject var viewModel: EventViewModel
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var shouldRemove = false
    
    var body: some View {
        if !shouldRemove {
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
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: acceptInvitation) {
                        if isAccepting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Accept")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isAccepting || isDeclining)
                    
                    Button(action: declineInvitation) {
                        if isDeclining {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Decline")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isAccepting || isDeclining)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
    
    private func acceptInvitation() {
        isAccepting = true
        Task {
            do {
                try await viewModel.acceptInvitation(event)
                await MainActor.run {
                    isAccepting = false
                    shouldRemove = true
                }
            } catch {
                await MainActor.run {
                    isAccepting = false
                    // Handle error if needed
                }
            }
        }
    }
    
    private func declineInvitation() {
        isDeclining = true
        Task {
            do {
                try await viewModel.declineInvitation(event)
                await MainActor.run {
                    isDeclining = false
                    shouldRemove = true
                }
            } catch {
                await MainActor.run {
                    isDeclining = false
                    // Handle error if needed
                }
            }
        }
    }
}
