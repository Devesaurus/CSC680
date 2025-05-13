import SwiftUI

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EventViewModel
    @State private var eventName: String = ""
    @State private var eventDate: Date = Date()
    @State private var eventDescription: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isCreating = false
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 20)
                    
                    // Event Name
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Event Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("*")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                        TextField("Enter event name", text: $eventName)
                            .textFieldStyle(CustomTextFieldStyle())
                            .frame(height: 44)
                            .frame(width: 280)
                    }
                    
                    // Event Date
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Event Date")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("*")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                        HStack(spacing: 0) {
                            DatePicker("", selection: $eventDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .frame(width: 140)
                            
                            DatePicker("", selection: $eventDate, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .frame(width: 140)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(height: 44)
                        .frame(width: 280)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    // Event Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter event description", text: $eventDescription, axis: .vertical)
                            .textFieldStyle(CustomTextFieldStyle())
                            .frame(minHeight: 44)
                            .frame(width: 280)
                            .lineLimit(3...6)
                    }
                    
                    // Create Button
                    Button(action: createEvent) {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Create Event")
                                .font(.headline)
                        }
                    }
                    .frame(width: 280)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                    .disabled(isCreating)
                    .padding(.top, 16)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isCreating)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createEvent() {
        let trimmedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            errorMessage = "Event name is required"
            showingError = true
            return
        }
        
        if eventDate < Date() {
            errorMessage = "Event date must be in the future"
            showingError = true
            return
        }
        
        isCreating = true
        
        Task {
            do {
                try await viewModel.createEvent(
                    name: trimmedName,
                    date: eventDate,
                    description: trimmedDescription
                )
                await MainActor.run {
                    isCreating = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}
