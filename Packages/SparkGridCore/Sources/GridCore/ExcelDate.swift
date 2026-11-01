import Foundation

/// Excel-compatible date serials (days since 1899-12-30), ignoring the 1900 leap-year bug.
/// Serials are calendar values. Formatters read them in UTC, so `NOW` and `TODAY`
/// store the Mac wall clock rather than the UTC instant.
public nonisolated enum ExcelDate {
  /// Clock for `NOW` and `TODAY`. The app uses the Mac's current time and time zone.
  public static var wallClock: () -> (date: Date, timeZone: TimeZone) = {
    (Date(), .current)
  }

  private static let epoch: Date = {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 1899
    components.month = 12
    components.day = 30
    return components.date ?? Date(timeIntervalSince1970: -2_209_161_600)
  }()

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    if let utc = TimeZone(secondsFromGMT: 0) {
      calendar.timeZone = utc
    }
    return calendar
  }()

  public static func serial(from date: Date) -> Double {
    let days = date.timeIntervalSince(epoch) / 86_400
    return days.rounded(.down)
  }

  /// Date and time fraction of an absolute instant, on the UTC calendar.
  public static func serialWithTime(from date: Date) -> Double {
    date.timeIntervalSince(epoch) / 86_400
  }

  /// Integer serial for the wall-clock date in `timeZone`. `TODAY` uses this.
  public static func localSerial(from date: Date, timeZone: TimeZone = .current) -> Double {
    localSerialWithTime(from: date, timeZone: timeZone).rounded(.down)
  }

  /// Serial whose UTC fields match the wall clock in `timeZone`. `NOW` uses this.
  public static func localSerialWithTime(from date: Date, timeZone: TimeZone = .current) -> Double {
    let offset = Double(timeZone.secondsFromGMT(for: date))
    return (date.timeIntervalSince(epoch) + offset) / 86_400
  }

  public static func date(from serial: Double) -> Date? {
    epoch.addingTimeInterval(serial * 86_400)
  }

  /// Year, month, or day on the UTC calendar cell formats use.
  public static func utcComponent(_ component: Calendar.Component, from date: Date) -> Int {
    utcCalendar.component(component, from: date)
  }
}
