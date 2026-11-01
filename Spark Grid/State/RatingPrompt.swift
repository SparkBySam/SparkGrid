import Foundation

/// When to ask for an App Store rating: after someone has used Spark Grid on several days, and at
/// most once per version. The system decides whether the prompt actually shows (a few times a
/// year at most) and draws it. Nothing is sent anywhere by this code.
enum RatingPrompt {
  static let opensBeforeAsking = 5
  static let daysBeforeAsking = 3

  private enum Key {
    static let firstOpen = "ratingPrompt.firstOpen"
    static let opens = "ratingPrompt.opens"
    static let askedVersion = "ratingPrompt.askedVersion"
  }

  /// Counts a file opened with real content. Benchmarks and tests don't count.
  static func recordOpen(defaults: UserDefaults = .standard, now: Date = Date()) {
    if defaults.object(forKey: Key.firstOpen) == nil {
      defaults.set(now, forKey: Key.firstOpen)
    }
    defaults.set(defaults.integer(forKey: Key.opens) + 1, forKey: Key.opens)
  }

  /// True once enough use has passed and this version has not asked yet.
  static func shouldAsk(
    version: String,
    defaults: UserDefaults = .standard,
    now: Date = Date()
  ) -> Bool {
    guard defaults.string(forKey: Key.askedVersion) != version,
      defaults.integer(forKey: Key.opens) >= opensBeforeAsking,
      let first = defaults.object(forKey: Key.firstOpen) as? Date,
      now.timeIntervalSince(first) >= Double(daysBeforeAsking) * 86_400
    else { return false }
    return true
  }

  static func markAsked(version: String, defaults: UserDefaults = .standard) {
    defaults.set(version, forKey: Key.askedVersion)
  }

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }
}
