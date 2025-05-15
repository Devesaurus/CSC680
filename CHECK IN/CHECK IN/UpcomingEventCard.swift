import SwiftUI

// TO DISPLAY ON THE HOMEPAGE
struct UpcomingEventCard: View {
    let event: Event
    
    var body: some View {
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.date)
    }
}
