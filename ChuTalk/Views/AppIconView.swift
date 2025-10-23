//
//  AppIconView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

/// アプリアイコン生成用ビュー - シンプル版
/// オレンジの背景に"ChuTalk"テキストのみを表示
struct AppIconView: View {
    var body: some View {
        ZStack {
            // オレンジのグラデーション背景
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.6, blue: 0.2),   // 明るいオレンジ
                    Color(red: 0.95, green: 0.5, blue: 0.1)   // 濃いオレンジ
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // "ChuTalk" テキスト
            Text("ChuTalk")
                .font(.system(size: 180, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 10)
        }
        .frame(width: 1024, height: 1024)  // App Store用の最大サイズ
    }
}

/// 複数サイズのアイコンを一度に生成するためのプレビューヘルパー
struct AppIconGenerator: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // オレンジのグラデーション背景
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.6, blue: 0.2),
                    Color(red: 0.95, green: 0.5, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // "ChuTalk" テキスト（サイズに応じて調整）
            let fontSize: CGFloat = size >= 512 ? size * 0.18 : size >= 180 ? size * 0.16 : size >= 80 ? size * 0.14 : size * 0.12

            Text("ChuTalk")
                .font(.system(size: fontSize, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: size * 0.015, x: 0, y: size * 0.01)
        }
        .frame(width: size, height: size)
    }
}

#Preview("App Icon 1024x1024") {
    AppIconView()
}

#Preview("App Icon 180x180") {
    AppIconGenerator(size: 180)
}

#Preview("App Icon 120x120") {
    AppIconGenerator(size: 120)
}

#Preview("App Icon 60x60") {
    AppIconGenerator(size: 60)
}
