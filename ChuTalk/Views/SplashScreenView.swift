//
//  SplashScreenView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    @State private var showText = false

    private let primaryOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    private let accentOrange = Color(red: 0.95, green: 0.5, blue: 0.1)

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                colors: [primaryOrange, accentOrange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                // アイコン
                ZStack {
                    // 外側の光る輪
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .scaleEffect(isAnimating ? 1.2 : 0.8)
                        .opacity(isAnimating ? 0 : 1)

                    // メインアイコン
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 140, height: 140)
                            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)

                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 65))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [primaryOrange, accentOrange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                }

                // アプリ名
                if showText {
                    VStack(spacing: 12) {
                        Text("チュートーク")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)

                        Text("中部特機で、トーク中。")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .tracking(2)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .onAppear {
            // アニメーション
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }

            // 外側の輪のアニメーションを繰り返す
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }

            // テキストを少し遅れて表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.6)) {
                    showText = true
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
