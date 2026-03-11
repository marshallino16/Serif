import Foundation

extension Date {
    /// Full date with time, for detail views: "Mar 1, 2025 at 2:34 PM" or "Today at 2:34 PM".
    var formattedFull: String {
        let calendar = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let time = timeFmt.string(from: self)

        if calendar.isDateInToday(self) {
            return "Today, \(time)"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday, \(time)"
        } else {
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = calendar.component(.year, from: self) != calendar.component(.year, from: Date())
                ? "MMM d, yyyy"
                : "MMM d"
            return "\(dateFmt.string(from: self)), \(time)"
        }
    }

    /// Formats a date relative to today: time for today, "Yesterday", or "MMM d" otherwise.
    var formattedRelative: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(self) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else if calendar.component(.year, from: self) != calendar.component(.year, from: Date()) {
            formatter.dateFormat = "MMM d, yyyy"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: self)
    }

    /// Medium date with short time: "Mar 1, 2025, 2:34 PM".
    var formattedMedium: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: self)
    }

    /// Long date with medium time: "March 1, 2025 at 2:34:56 PM".
    var formattedLong: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .medium
        return fmt.string(from: self)
    }

    /// Long date with short time: "March 1, 2025 at 2:34 PM".
    var formattedLongShort: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .short
        return fmt.string(from: self)
    }

    /// Medium date only: "Mar 1, 2025".
    var formattedDateOnly: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: self)
    }
}
