import Foundation
import Testing
@testable import FitnessTracker

@Suite("CalendarDay")
struct CalendarDayTests {
    private let oct8 = CalendarDay(year: 2026, month: 10, day: 8)

    @Test("decodes the server's UTC-midnight DATE as that day", arguments: [
        "2026-10-08T00:00:00.000Z",
        "2026-10-08T00:00:00Z",
        "2026-10-08",
    ])
    func decodesWireForms(raw: String) throws {
        let dto = try JSONCoding.decoder.decode(
            ScheduledWorkoutDTO.self,
            from: Data("""
            {"id":"sw1","userProgramId":"up1","weekNumber":1,"dayNumber":2,\
            "scheduledDate":"\(raw)","createdAt":"2026-10-01T12:00:00.000Z"}
            """.utf8)
        )
        #expect(dto.scheduledDate == oct8)
    }

    @Test("rejects a value that isn't a date")
    func rejectsGarbage() {
        #expect(throws: DecodingError.self) {
            try JSONCoding.decoder.decode(CalendarDay.self, from: Data(#""next thursday""#.utf8))
        }
    }

    @Test("encodes as yyyy-MM-dd")
    func encodesAsDayString() throws {
        let data = try JSONCoding.encoder.encode(["scheduledDate": oct8])
        #expect(String(decoding: data, as: UTF8.self) == #"{"scheduledDate":"2026-10-08"}"#)
    }

    @Test("a local midnight is that local day, east and west of UTC", arguments: [
        "America/New_York", "Europe/Berlin", "Pacific/Auckland", "Pacific/Honolulu",
    ])
    func localDay(timeZone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        let lateEvening = try #require(calendar.date(byAdding: .minute, value: 24 * 60 - 1, to: midnight))
        #expect(CalendarDay(midnight, in: calendar) == oct8)
        #expect(CalendarDay(lateEvening, in: calendar) == oct8)
        #expect(CalendarDay(midnight, in: calendar).key == "2026-10-08")
    }
}
