import Foundation

/// Access to localized strings.
///
/// `Bundle.main` is the current process's bundle: the app for the window, but
/// the extension itself when the code runs inside an `.appex`. Every bundle
/// therefore ships its own copy of the translations, and no caller needs to
/// know where it is running.
@inline(__always)
public func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// Formatted variant, for messages that carry a value.
@inline(__always)
public func L(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""),
           locale: .current, arguments: arguments)
}
