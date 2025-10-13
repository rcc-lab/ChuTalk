//
//  Date+Extensions.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

extension Date {
    func timeAgo() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.second, .minute, .hour, .day, .month, .year], from: self, to: now)

        if let year = components.year, year > 0 {
            return year == 1 ? "1年前" : "\(year)年前"
        }

        if let month = components.month, month > 0 {
            return month == 1 ? "1ヶ月前" : "\(month)ヶ月前"
        }

        if let day = components.day, day > 0 {
            return day == 1 ? "1日前" : "\(day)日前"
        }

        if let hour = components.hour, hour > 0 {
            return hour == 1 ? "1時間前" : "\(hour)時間前"
        }

        if let minute = components.minute, minute > 0 {
            return minute == 1 ? "1分前" : "\(minute)分前"
        }

        return "たった今"
    }

    func formatted(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: self)
    }

    func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: self)
    }

    func formattedDateTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: self)
    }
}
