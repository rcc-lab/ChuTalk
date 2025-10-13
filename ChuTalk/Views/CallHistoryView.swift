//
//  CallHistoryView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct CallHistoryView: View {
    @State private var callHistory: [CallHistory] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if callHistory.isEmpty {
                    emptyStateView
                } else {
                    historyList
                }
            }
            .navigationTitle("通話履歴")
            .refreshable {
                await loadCallHistory()
            }
        }
        .task {
            await loadCallHistory()
        }
    }

    private var historyList: some View {
        List {
            ForEach(groupedHistory.keys.sorted(by: >), id: \.self) { date in
                Section(header: Text(formatSectionDate(date))) {
                    ForEach(groupedHistory[date] ?? []) { call in
                        CallHistoryRow(call: call)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "phone.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("通話履歴がありません")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("連絡先から通話を開始してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var groupedHistory: [String: [CallHistory]] {
        Dictionary(grouping: callHistory) { call in
            formatDate(call.timestamp)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatSectionDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今日"
        } else if calendar.isDateInYesterday(date) {
            return "昨日"
        } else {
            formatter.dateFormat = "M月d日"
            return formatter.string(from: date)
        }
    }

    private func loadCallHistory() async {
        isLoading = true
        errorMessage = nil

        // Note: Server doesn't have GET /api/calls endpoint yet, only POST
        // For now, use empty history
        await MainActor.run {
            self.callHistory = []
            self.isLoading = false
        }

        /*
        do {
            let history = try await APIService.shared.getCallHistory()

            // Populate contact names
            let contactsService = ContactsService.shared
            var enrichedHistory = history

            for index in enrichedHistory.indices {
                if let contact = try? await contactsService.getContact(byId: enrichedHistory[index].contactId) {
                    enrichedHistory[index].contactName = contact.displayName
                }
            }

            await MainActor.run {
                self.callHistory = enrichedHistory.sorted { $0.timestamp > $1.timestamp }
                self.isLoading = false
            }
        } catch {
            print("⚠️ CallHistoryView: Failed to load history - \(error)")
            await MainActor.run {
                // Set empty history instead of showing error
                self.callHistory = []
                self.errorMessage = nil
                self.isLoading = false
            }
        }
        */
    }
}

struct CallHistoryRow: View {
    let call: CallHistory

    var body: some View {
        HStack(spacing: 12) {
            // Call type icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 40, height: 40)

                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 18))
            }

            // Call info
            VStack(alignment: .leading, spacing: 4) {
                Text(call.contactName ?? "Unknown")
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(callTypeText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if call.duration > 0 {
                        Text("•")
                            .foregroundColor(.secondary)

                        Text(call.durationString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Time
            Text(formatTime(call.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch call.type {
        case .incoming:
            return "phone.arrow.down.left.fill"
        case .outgoing:
            return "phone.arrow.up.right.fill"
        case .missed:
            return "phone.down.fill"
        }
    }

    private var iconColor: Color {
        switch call.type {
        case .incoming:
            return .green
        case .outgoing:
            return .blue
        case .missed:
            return .red
        }
    }

    private var iconBackgroundColor: Color {
        switch call.type {
        case .incoming:
            return .green.opacity(0.15)
        case .outgoing:
            return .blue.opacity(0.15)
        case .missed:
            return .red.opacity(0.15)
        }
    }

    private var callTypeText: String {
        switch call.type {
        case .incoming:
            return "着信"
        case .outgoing:
            return "発信"
        case .missed:
            return "不在着信"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    CallHistoryView()
}
