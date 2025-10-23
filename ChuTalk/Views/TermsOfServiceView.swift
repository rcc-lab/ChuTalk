//
//  TermsOfServiceView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isAccepted: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(termsText)
                        .font(.body)
                        .padding()
                }
            }
            .navigationTitle("利用規約")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("同意する") {
                        isAccepted = true
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private var termsText: String {
        guard let path = Bundle.main.path(forResource: "TermsOfService", ofType: "txt"),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "利用規約を読み込めませんでした。"
        }
        return content
    }
}

#Preview {
    TermsOfServiceView(isAccepted: .constant(false))
}
