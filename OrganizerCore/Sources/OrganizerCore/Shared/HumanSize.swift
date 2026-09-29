import Foundation

public enum HumanSize {
    /// Format a byte count as a short human-readable string ("4.8 GB", "512 B").
    public static func string(_ bytes: Int64) -> String {
        var value = Double(bytes)
        if value < 1024 { return String(format: "%.0f B", value) }
        for unit in ["KB", "MB", "GB", "TB"] {
            value /= 1024
            if value < 1024 || unit == "TB" {
                return String(format: "%.1f %@", value, unit)
            }
        }
        return String(format: "%.1f TB", value)
    }
}
