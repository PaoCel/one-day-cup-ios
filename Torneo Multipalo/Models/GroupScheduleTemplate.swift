import Foundation

enum GroupScheduleTemplate {
    static let letters = ["A", "B", "C", "D", "E", "F", "G"]

    struct FieldMatch: Hashable {
        let fieldNumber: String
        let homeLetter: String
        let awayLetter: String
    }

    struct TimeSlot: Identifiable, Hashable {
        let giornata: Int
        let timeLabel: String
        let matches: [FieldMatch]

        var id: Int { giornata }
    }

    struct ScheduledMatchDefinition: Identifiable, Hashable {
        let giornata: Int
        let timeLabel: String
        let fieldNumber: String
        let homeLetter: String
        let awayLetter: String
        let sortIndex: Int

        var id: String { "\(giornata)-\(fieldNumber)" }
    }

    static let timeSlots: [TimeSlot] = [
        TimeSlot(
            giornata: 1,
            timeLabel: "09:00 - 09:25",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "A", awayLetter: "B"),
                FieldMatch(fieldNumber: "2", homeLetter: "C", awayLetter: "D")
            ]
        ),
        TimeSlot(
            giornata: 2,
            timeLabel: "09:30 - 09:55",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "E", awayLetter: "F"),
                FieldMatch(fieldNumber: "2", homeLetter: "G", awayLetter: "A")
            ]
        ),
        TimeSlot(
            giornata: 3,
            timeLabel: "10:00 - 10:25",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "B", awayLetter: "C"),
                FieldMatch(fieldNumber: "2", homeLetter: "D", awayLetter: "E")
            ]
        ),
        TimeSlot(
            giornata: 4,
            timeLabel: "10:30 - 10:55",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "F", awayLetter: "G"),
                FieldMatch(fieldNumber: "2", homeLetter: "A", awayLetter: "C")
            ]
        ),
        TimeSlot(
            giornata: 5,
            timeLabel: "11:00 - 11:25",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "B", awayLetter: "D"),
                FieldMatch(fieldNumber: "2", homeLetter: "E", awayLetter: "G")
            ]
        ),
        TimeSlot(
            giornata: 6,
            timeLabel: "11:30 - 11:55",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "A", awayLetter: "F"),
                FieldMatch(fieldNumber: "2", homeLetter: "C", awayLetter: "E")
            ]
        ),
        TimeSlot(
            giornata: 7,
            timeLabel: "12:00 - 12:25",
            matches: [
                FieldMatch(fieldNumber: "1", homeLetter: "B", awayLetter: "G"),
                FieldMatch(fieldNumber: "2", homeLetter: "D", awayLetter: "F")
            ]
        )
    ]

    static let scheduledMatches: [ScheduledMatchDefinition] = timeSlots.enumerated().flatMap { slotIndex, slot in
        slot.matches.map { match in
            ScheduledMatchDefinition(
                giornata: slot.giornata,
                timeLabel: slot.timeLabel,
                fieldNumber: match.fieldNumber,
                homeLetter: match.homeLetter,
                awayLetter: match.awayLetter,
                sortIndex: (slotIndex * 10) + (Int(match.fieldNumber) ?? 0)
            )
        }
    }
}
