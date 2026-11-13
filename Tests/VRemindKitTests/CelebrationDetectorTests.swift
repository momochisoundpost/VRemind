import Foundation
import Testing
@testable import VRemindKit

struct CelebrationDetectorTests {
    private static var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return testCalendar.date(from: comps)!
    }

    @Test func testEnglishKeywords() {
        // Birthday
        let birthday1 = CelebrationDetector.detect(title: "My Birthday Stream!")
        #expect(birthday1.isCelebration)
        #expect(birthday1.type == .birthday)

        let birthday2 = CelebrationDetector.detect(title: "3D Bday Party")
        #expect(birthday2.isCelebration)
        #expect(birthday2.type == .birthday)

        // Debut
        let debut1 = CelebrationDetector.detect(title: "VTuber Debut Stream")
        #expect(debut1.isCelebration)
        #expect(debut1.type == .debut)

        let debut2 = CelebrationDetector.detect(title: "Re-Debut Announcement")
        #expect(debut2.isCelebration)
        #expect(debut2.type == .debut)

        // Anniversary
        let anni1 = CelebrationDetector.detect(title: "3rd Anniversary")
        #expect(anni1.isCelebration)
        #expect(anni1.type == .anniversary)

        let anni2 = CelebrationDetector.detect(title: "2nd Anni")
        #expect(anni2.isCelebration)
        #expect(anni2.type == .anniversary)

        // Rejections (word-boundary safety)
        let rejected1 = CelebrationDetector.detect(title: "unbirthday")
        #expect(!rejected1.isCelebration)
        #expect(rejected1.type == nil)
        #expect(rejected1 == .none)

        let rejected2 = CelebrationDetector.detect(title: "annihilation")
        #expect(!rejected2.isCelebration)
        #expect(rejected2.type == nil)
        #expect(rejected2 == .none)
    }

    @Test func testIndonesianKeywords() {
        let ultah = CelebrationDetector.detect(title: "Stream Ultah ke-20")
        #expect(ultah.isCelebration)
        #expect(ultah.type == .birthday)

        let ulangTahun = CelebrationDetector.detect(title: "Ulang Tahun Bareng")
        #expect(ulangTahun.isCelebration)
        #expect(ulangTahun.type == .birthday)

        let hariJadi = CelebrationDetector.detect(title: "Hari Jadi Channel")
        #expect(hariJadi.isCelebration)
        #expect(hariJadi.type == .anniversary)

        let anniv = CelebrationDetector.detect(title: "Anniv 1 Tahun")
        #expect(anniv.isCelebration)
        #expect(anniv.type == .anniversary)
    }

    @Test func testJapaneseKeywords() {
        let seitan = CelebrationDetector.detect(title: "【生誕祭】お祝い")
        #expect(seitan.isCelebration)
        #expect(seitan.type == .birthday)

        let tanjoubi = CelebrationDetector.detect(title: "誕生日配信")
        #expect(tanjoubi.isCelebration)
        #expect(tanjoubi.type == .birthday)

        let birthday = CelebrationDetector.detect(title: "バースデーライブ")
        #expect(birthday.isCelebration)
        #expect(birthday.type == .birthday)

        let debut = CelebrationDetector.detect(title: "【初配信/DEBUT】")
        #expect(debut.isCelebration)
        #expect(debut.type == .debut)

        let ohirome = CelebrationDetector.detect(title: "新衣装お披露目")
        #expect(ohirome.isCelebration)
        #expect(ohirome.type == .debut)

        let shuunen = CelebrationDetector.detect(title: "3周年記念配信")
        #expect(shuunen.isCelebration)
        #expect(shuunen.type == .anniversary)

        let kinenwaku = CelebrationDetector.detect(title: "記念枠")
        #expect(kinenwaku.isCelebration)
        #expect(kinenwaku.type == .anniversary)

        let arigatou = CelebrationDetector.detect(title: "1周年ありがとう")
        #expect(arigatou.isCelebration)
        #expect(arigatou.type == .anniversary)
    }

    @Test func testDeveloperBirthdayDateBoundary() {
        let calendar = Self.testCalendar

        // Dec 31, 2000 -> true
        let dec31_2000 = Self.makeDate(year: 2000, month: 12, day: 31)
        #expect(CelebrationDetector.isDeveloperBirthday(date: dec31_2000, calendar: calendar))

        // Dec 31, 2026 -> true
        let dec31_2026 = Self.makeDate(year: 2026, month: 12, day: 31)
        #expect(CelebrationDetector.isDeveloperBirthday(date: dec31_2026, calendar: calendar))

        // Dec 31, 1999 -> false (year must be > 1999)
        let dec31_1999 = Self.makeDate(year: 1999, month: 12, day: 31)
        #expect(!CelebrationDetector.isDeveloperBirthday(date: dec31_1999, calendar: calendar))

        // Dec 30, 2026 -> false
        let dec30_2026 = Self.makeDate(year: 2026, month: 12, day: 30)
        #expect(!CelebrationDetector.isDeveloperBirthday(date: dec30_2026, calendar: calendar))

        // Jan 1, 2027 -> false
        let jan1_2027 = Self.makeDate(year: 2027, month: 1, day: 1)
        #expect(!CelebrationDetector.isDeveloperBirthday(date: jan1_2027, calendar: calendar))
    }

    @Test func testTargetChannelDetection() {
        let handleChannel = WatchedChannel(id: "c1", name: "Caitlyn", handle: "@bukancaitlyn")
        #expect(CelebrationDetector.isTargetDeveloperChannel(handleChannel))

        let uppercaseHandleChannel = WatchedChannel(id: "c2", name: "Caitlyn", handle: "BUKANCAITLYN")
        #expect(CelebrationDetector.isTargetDeveloperChannel(uppercaseHandleChannel))

        let displayNameChannel = WatchedChannel(id: "c3", name: "Caitlyn Momochi", handle: "@somehandle")
        #expect(CelebrationDetector.isTargetDeveloperChannel(displayNameChannel))

        let idChannel = WatchedChannel(id: "bukancaitlyn", name: "Unknown", handle: "@unknown")
        #expect(CelebrationDetector.isTargetDeveloperChannel(idChannel))

        let otherChannel = WatchedChannel(id: "c4", name: "Other VTuber", handle: "@othervtuber")
        #expect(!CelebrationDetector.isTargetDeveloperChannel(otherChannel))
    }

    @Test func testShouldShowConfettiScope() {
        let calendar = Self.testCalendar
        let baseDate = Self.makeDate(year: 2026, month: 11, day: 12, hour: 10)
        let channel = WatchedChannel(id: "ch1", name: "VTuber", handle: "@vtuber")

        // 1. Live celebration stream -> true
        let liveStatus = StreamStatus.live(videoId: "v1", title: "My Birthday Stream!", startedAt: baseDate)
        #expect(CelebrationDetector.shouldShowConfetti(
            channels: [channel],
            statuses: [channel.id: liveStatus],
            date: baseDate,
            calendar: calendar
        ))

        // 2. Upcoming celebration stream scheduled later today (date + 3600s) -> true
        let upcomingToday = StreamStatus.upcoming(
            videoId: "v2",
            title: "VTuber Debut Stream",
            scheduledStartTime: baseDate.addingTimeInterval(3600)
        )
        #expect(CelebrationDetector.shouldShowConfetti(
            channels: [channel],
            statuses: [channel.id: upcomingToday],
            date: baseDate,
            calendar: calendar
        ))

        // 3. Upcoming celebration stream scheduled 3 days in future (date + 3*86400s) -> false
        // (even though detect(...) for that row returns isCelebration == true)
        let upcomingFuture = StreamStatus.upcoming(
            videoId: "v3",
            title: "3rd Anniversary",
            scheduledStartTime: baseDate.addingTimeInterval(3 * 86400)
        )
        let rowResult = CelebrationDetector.detect(status: upcomingFuture, channel: channel, date: baseDate, calendar: calendar)
        #expect(rowResult.isCelebration)
        #expect(rowResult.type == .anniversary)

        #expect(!CelebrationDetector.shouldShowConfetti(
            channels: [channel],
            statuses: [channel.id: upcomingFuture],
            date: baseDate,
            calendar: calendar
        ))

        // 4. Offline @bukancaitlyn on Dec 31, 2026 -> true
        let devChannel = WatchedChannel(id: "dev", name: "Caitlyn Momochi", handle: "@bukancaitlyn")
        let offlineStatus = StreamStatus.offline(lastStreamedAt: nil)
        let dec31 = Self.makeDate(year: 2026, month: 12, day: 31)
        #expect(CelebrationDetector.shouldShowConfetti(
            channels: [devChannel],
            statuses: [devChannel.id: offlineStatus],
            date: dec31,
            calendar: calendar
        ))

        // 5. Offline @bukancaitlyn on Nov 12, 2026 -> false
        let nov12 = Self.makeDate(year: 2026, month: 11, day: 12)
        #expect(!CelebrationDetector.shouldShowConfetti(
            channels: [devChannel],
            statuses: [devChannel.id: offlineStatus],
            date: nov12,
            calendar: calendar
        ))
    }
}
