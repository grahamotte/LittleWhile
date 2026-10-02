import XCTest
@testable import App

@MainActor
final class RunStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let storageKey = "littlewhile.runs.v1"

    func testCreatesAndPersistsOneReadyRunOnFirstLaunch() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            XCTAssertEqual(store.runs.count, 1)
            XCTAssertTrue(store.history.isEmpty)
            XCTAssertEqual(store.currentRun.createdAt, date)
            XCTAssertEqual(store.currentRun.goalSeconds, 1_500)
            XCTAssertEqual(store.currentRun.restSeconds, 300)
            XCTAssertEqual(store.currentRun.theme, "boring")
            XCTAssertFalse(store.currentRun.hasStarted)
            XCTAssertFalse(store.currentRun.isRunning)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testFirstStartRecordsStartTimeAndPersistsRunningState() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let start = date.addingTimeInterval(30)

            store.start(at: start)

            XCTAssertEqual(store.currentRun.createdAt, date)
            XCTAssertEqual(store.currentRun.startedAt, start)
            XCTAssertEqual(store.currentRun.resumedAt, start)
            XCTAssertEqual(store.currentRun.elapsed(at: start.addingTimeInterval(5.5)), 5.5)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testPauseAndResumePreserveFractionalProgressAndOriginalStart() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.start(at: date)
            store.pause(at: date.addingTimeInterval(10.25))
            XCTAssertEqual(store.currentRun.progressSeconds, 10.25)
            XCTAssertNil(store.currentRun.resumedAt)
            XCTAssertEqual(store.currentRun.elapsed(at: date.addingTimeInterval(200)), 10.25)

            store.start(at: date.addingTimeInterval(200))
            store.pause(at: date.addingTimeInterval(201.5))

            XCTAssertEqual(store.currentRun.progressSeconds, 11.75)
            XCTAssertEqual(store.currentRun.startedAt, date)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testStartingAlreadyRunningDoesNotResetItsClock() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.start(at: date)
            store.start(at: date.addingTimeInterval(5.25))
            store.pause(at: date.addingTimeInterval(9.5))

            XCTAssertEqual(store.currentRun.startedAt, date)
            XCTAssertEqual(store.currentRun.progressSeconds, 9.5)
        }
    }

    func testTogglingStartsPausesAndResumes() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.toggle(at: date)
            XCTAssertTrue(store.currentRun.isRunning)
            store.toggle(at: date.addingTimeInterval(20))
            XCTAssertFalse(store.currentRun.isRunning)
            store.toggle(at: date.addingTimeInterval(40))
            XCTAssertTrue(store.currentRun.isRunning)
            XCTAssertEqual(store.currentRun.elapsed(at: date.addingTimeInterval(50)), 30)
        }
    }

    func testPausingReadyRunDoesNotStartIt() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.pause(at: date.addingTimeInterval(20))

            XCTAssertFalse(store.currentRun.hasStarted)
            XCTAssertFalse(store.currentRun.isRunning)
            XCTAssertEqual(store.currentRun.progressSeconds, 0)
        }
    }

    func testRefreshCheckpointsFractionalProgressWithoutLosingTime() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)

            store.refresh(at: date.addingTimeInterval(10.125))
            store.refresh(at: date.addingTimeInterval(11.375))

            XCTAssertEqual(store.currentRun.progressSeconds, 11.375)
            XCTAssertEqual(store.currentRun.resumedAt, date.addingTimeInterval(11.375))
            XCTAssertEqual(store.currentRun.elapsed(at: date.addingTimeInterval(12.25)), 12.25)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testCompletionStopsAtGoalAndCannotBeStartedAgain() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.createRun(minutes: 1, theme: "boring", at: date)
            let identifier = store.currentRun.id
            store.start(at: date)

            store.refresh(at: date.addingTimeInterval(75))
            store.start(at: date.addingTimeInterval(90))
            store.toggle(at: date.addingTimeInterval(100))

            XCTAssertEqual(store.currentRun.id, identifier)
            XCTAssertEqual(store.currentRun.progressSeconds, 60)
            XCTAssertTrue(store.currentRun.isComplete(at: date))
            XCTAssertFalse(store.currentRun.isRunning)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testPauseAfterGoalAlsoCompletesRun() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)

            store.pause(at: date.addingTimeInterval(2_000))

            XCTAssertEqual(store.currentRun.progressSeconds, 1_800)
            XCTAssertFalse(store.currentRun.isRunning)
        }
    }

    func testSetArchivesRunningRunAndCreatesReadyRunWithChosenSettings() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let originalIdentifier = store.currentRun.id
            store.start(at: date)
            let settingDate = date.addingTimeInterval(90.25)

            store.createRun(minutes: 45, theme: "future-theme", at: settingDate)

            XCTAssertNotEqual(store.currentRun.id, originalIdentifier)
            XCTAssertEqual(store.currentRun.goalSeconds, 2_700)
            XCTAssertEqual(store.currentRun.theme, "future-theme")
            XCTAssertEqual(store.currentRun.createdAt, settingDate)
            XCTAssertFalse(store.currentRun.hasStarted)
            XCTAssertFalse(store.currentRun.isRunning)
            XCTAssertEqual(store.currentRun.progressSeconds, 0)
            XCTAssertEqual(store.history.count, 1)
            XCTAssertEqual(store.history[0].id, originalIdentifier)
            XCTAssertEqual(store.history[0].progressSeconds, 90.25)
            XCTAssertEqual(store.history[0].theme, "boring")
            XCTAssertFalse(store.history[0].isRunning)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testStartingSelectedSettingsReplacesReadyRunningPausedAndCompletedRuns() async throws {
        for status in [TimerSnapshot.Status.ready, .running, .paused, .complete] {
            try withDefaults { defaults in
                let store = RunStore(defaults: defaults, now: date)
                let originalIdentifier = store.currentRun.id
                let startDate = date.addingTimeInterval(2_000)
                switch status {
                case .ready:
                    break
                case .running:
                    store.start(at: startDate.addingTimeInterval(-90.25))
                case .paused:
                    store.start(at: date)
                    store.pause(at: date.addingTimeInterval(90.25))
                case .complete:
                    store.start(at: date)
                    store.refresh(at: startDate)
                }

                store.startRun(minutes: 45, theme: "mr-smiles", restMinutes: 8, at: startDate)

                XCTAssertNotEqual(store.currentRun.id, originalIdentifier)
                XCTAssertEqual(store.currentRun.goalSeconds, 2_700)
                XCTAssertEqual(store.currentRun.restSeconds, 480)
                XCTAssertEqual(store.currentRun.theme, "mr-smiles")
                XCTAssertEqual(store.currentRun.createdAt, startDate)
                XCTAssertEqual(store.currentRun.startedAt, startDate)
                XCTAssertEqual(store.currentRun.resumedAt, startDate)
                XCTAssertEqual(TimerSnapshot(run: store.currentRun, at: startDate).status, .running)
                XCTAssertEqual(store.currentRun.elapsed(at: startDate.addingTimeInterval(10)), 10)
                XCTAssertEqual(store.history.count, 1)
                XCTAssertEqual(store.history[0].id, originalIdentifier)
                XCTAssertFalse(store.history[0].isRunning)
                let expectedProgress: TimeInterval = status == .ready ? 0 : status == .complete ? 1_800 : 90.25
                XCTAssertEqual(store.history[0].progressSeconds, expectedProgress)
                XCTAssertEqual(try savedRuns(defaults), store.runs)
            }
        }
    }

    func testStartedSettingsRestoreRunningAndCompleteWithoutRest() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.startRun(minutes: 1, theme: "boring", restMinutes: 0, at: date)

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(30))

            XCTAssertEqual(restored.currentRun.id, store.currentRun.id)
            XCTAssertEqual(restored.currentRun.startedAt, date)
            XCTAssertEqual(restored.currentRun.restSeconds, 0)
            XCTAssertEqual(TimerSnapshot(run: restored.currentRun, at: date.addingTimeInterval(30)).clockText, "00:30")
            XCTAssertTrue(restored.currentRun.isRunning)

            restored.refresh(at: date.addingTimeInterval(60))

            XCTAssertTrue(restored.currentRun.isComplete(at: date.addingTimeInterval(60)))
            XCTAssertFalse(restored.currentRun.isRunning)
            XCTAssertEqual(try savedRuns(defaults), restored.runs)
        }
    }

    func testSetKeepsUnstartedRunInHistoryAndUsesNewestFirstOrder() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let first = store.currentRun.id
            store.createRun(minutes: 10, theme: "boring", at: date.addingTimeInterval(1))
            let second = store.currentRun.id

            store.createRun(minutes: 15, theme: "boring", at: date.addingTimeInterval(2))

            XCTAssertEqual(store.history.map(\.id), [second, first])
            XCTAssertTrue(store.history.allSatisfy { !$0.hasStarted && $0.progressSeconds == 0 })
        }
    }

    func testVisibleRunsIncludesCurrentAndOmitsUnstartedHistory() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let unstartedIdentifier = store.currentRun.id
            store.createRun(minutes: 10, theme: "boring", at: date.addingTimeInterval(1))
            let startedIdentifier = store.currentRun.id
            store.start(at: date.addingTimeInterval(2))
            store.pause(at: date.addingTimeInterval(32))
            store.createRun(minutes: 15, theme: "boring", at: date.addingTimeInterval(33))
            let currentIdentifier = store.currentRun.id

            let visibleRuns = store.visibleRuns(at: date.addingTimeInterval(33))

            XCTAssertEqual(visibleRuns.map(\.id), [currentIdentifier, startedIdentifier])
            XCTAssertEqual(visibleRuns[0].fraction(at: date.addingTimeInterval(33)), 0)
            XCTAssertFalse(visibleRuns.map(\.id).contains(unstartedIdentifier))

            store.start(at: date.addingTimeInterval(34))
            let progressedRuns = store.visibleRuns(at: date.addingTimeInterval(64))

            XCTAssertEqual(progressedRuns.map(\.id), [currentIdentifier, startedIdentifier])
            XCTAssertEqual(progressedRuns[0].fraction(at: date.addingTimeInterval(64)), 30.0 / 900.0)
        }
    }

    func testMinuteBoundsAreClampedBeforeMultiplication() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.createRun(minutes: Int.min, theme: "boring", at: date)
            XCTAssertEqual(store.currentRun.goalSeconds, 60)
            store.createRun(minutes: Int.max, theme: "boring", at: date)
            XCTAssertEqual(store.currentRun.goalSeconds, 7_200)
            store.createRun(minutes: 25, theme: "boring", at: date)
            XCTAssertEqual(store.currentRun.goalSeconds, 1_500)
            store.createRun(minutes: 25, theme: "boring", restMinutes: Int.min, at: date)
            XCTAssertEqual(store.currentRun.restSeconds, 0)
            store.createRun(minutes: 25, theme: "boring", restMinutes: Int.max, at: date)
            XCTAssertEqual(store.currentRun.restSeconds, 7_200)
            store.createRun(minutes: 25, theme: "boring", restMinutes: 5, at: date)
            XCTAssertEqual(store.currentRun.restSeconds, 300)
        }
    }

    func testBlankThemeUsesBoringAndUnknownThemesArePreserved() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.createRun(minutes: 25, theme: " \n\t ", at: date)
            XCTAssertEqual(store.currentRun.theme, "boring")
            store.createRun(minutes: 25, theme: "garden", at: date)
            XCTAssertEqual(store.currentRun.theme, "garden")
        }
    }

    func testRestorationTreatsMissingRestSecondsAsZero() async throws {
        try withDefaults { defaults in
            let run = FocusRun(createdAt: date, goalSeconds: 1_200, theme: "garden")
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode([run]))
            var objects = try XCTUnwrap(encoded as? [[String: Any]])
            objects[0].removeValue(forKey: "restSeconds")
            defaults.set(try JSONSerialization.data(withJSONObject: objects), forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date)

            XCTAssertEqual(store.currentRun.restSeconds, 0)
            XCTAssertEqual(store.currentRun.goalSeconds, 1_200)
        }
    }

    func testRestorationMigratesStandardThemeToBoring() async throws {
        try withDefaults { defaults in
            let run = FocusRun(createdAt: date, theme: "standard")
            defaults.set(try JSONEncoder().encode([run]), forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date)

            XCTAssertEqual(store.currentRun.theme, "boring")
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testSetAndRestartPreserveRestDuration() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.createRun(minutes: 25, theme: "garden", restMinutes: 8, at: date)
            store.start(at: date)

            store.restart(at: date.addingTimeInterval(30))

            XCTAssertEqual(store.currentRun.goalSeconds, 1_500)
            XCTAssertEqual(store.currentRun.restSeconds, 480)
            XCTAssertEqual(store.currentRun.theme, "garden")
            XCTAssertEqual(store.history[0].restSeconds, 480)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testRestartArchivesProgressAndPreservesSettingsInReadyRun() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.createRun(minutes: 40, theme: "garden", at: date)
            let oldIdentifier = store.currentRun.id
            store.start(at: date)

            store.restart(at: date.addingTimeInterval(30.5))

            XCTAssertNotEqual(store.currentRun.id, oldIdentifier)
            XCTAssertEqual(store.currentRun.goalSeconds, 2_400)
            XCTAssertEqual(store.currentRun.restSeconds, 0)
            XCTAssertEqual(store.currentRun.theme, "garden")
            XCTAssertEqual(store.currentRun.progressSeconds, 0)
            XCTAssertFalse(store.currentRun.hasStarted)
            XCTAssertFalse(store.currentRun.isRunning)
            XCTAssertEqual(store.history[0].id, oldIdentifier)
            XCTAssertEqual(store.history[0].progressSeconds, 30.5)
            XCTAssertFalse(store.history[0].isRunning)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testDeleteRemovesOnlySelectedPastRunAndPersists() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let firstIdentifier = store.currentRun.id
            store.createRun(minutes: 20, theme: "boring", at: date.addingTimeInterval(1))
            let secondIdentifier = store.currentRun.id
            store.createRun(minutes: 30, theme: "boring", at: date.addingTimeInterval(2))
            let currentIdentifier = store.currentRun.id

            store.deleteRun(id: secondIdentifier)

            XCTAssertEqual(store.currentRun.id, currentIdentifier)
            XCTAssertEqual(store.history.map(\.id), [firstIdentifier])
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testDeleteCannotRemoveCurrentOrChangeRunsForUnknownIdentifier() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let original = store.runs

            store.deleteRun(id: store.currentRun.id)
            store.deleteRun(id: UUID())

            XCTAssertEqual(store.runs, original)
        }
    }

    func testRunningRunRestoresElapsedBackgroundTime() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)
            store.refresh(at: date.addingTimeInterval(10.25))

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(100.5))

            XCTAssertEqual(restored.currentRun.id, store.currentRun.id)
            XCTAssertEqual(restored.currentRun.startedAt, date)
            XCTAssertEqual(restored.currentRun.progressSeconds, 100.5)
            XCTAssertEqual(restored.currentRun.elapsed(at: date.addingTimeInterval(101.75)), 101.75)
            XCTAssertTrue(restored.currentRun.isRunning)
        }
    }

    func testRunCompletedWhileAwayRestoresCompleteAndStopped() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(10_000))

            XCTAssertEqual(restored.currentRun.progressSeconds, 1_800)
            XCTAssertFalse(restored.currentRun.isRunning)
            XCTAssertEqual(try savedRuns(defaults), restored.runs)
        }
    }

    func testRelaunchAfterPauseWindowResumesFromDeadline() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)
            store.pause(at: date.addingTimeInterval(10))

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(100))

            XCTAssertTrue(restored.currentRun.isRunning)
            XCTAssertNil(restored.currentRun.pausedAt)
            XCTAssertEqual(restored.currentRun.elapsed(at: date.addingTimeInterval(100)), 40)
        }
    }

    func testPausedRunDoesNotAccumulateDuringRelaunch() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)
            store.pause(at: date.addingTimeInterval(13.125))

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(30))

            XCTAssertEqual(restored.currentRun, store.currentRun)
            XCTAssertEqual(restored.currentRun.progressSeconds, 13.125)
            XCTAssertFalse(restored.currentRun.isRunning)
        }
    }

    func testHistoryDeletionSurvivesRelaunch() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let oldIdentifier = store.currentRun.id
            store.createRun(minutes: 30, theme: "garden", at: date.addingTimeInterval(1))
            store.deleteRun(id: oldIdentifier)

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(2))

            XCTAssertEqual(restored.runs, store.runs)
            XCTAssertTrue(restored.history.isEmpty)
        }
    }

    func testCorruptAndEmptyStorageRecoverOneReadyRun() async {
        for data in [Data("broken".utf8), Data("[]".utf8), Data("{}".utf8), Data("[null, 4, {}]".utf8)] {
            withDefaults { defaults in
                defaults.set(data, forKey: storageKey)

                let store = RunStore(defaults: defaults, now: date)

                XCTAssertEqual(store.runs.count, 1)
                XCTAssertEqual(store.currentRun.createdAt, date)
                XCTAssertFalse(store.currentRun.hasStarted)
            }
        }
    }

    func testMalformedRowsDoNotDiscardHealthyCurrentRunOrHistory() async throws {
        try withDefaults { defaults in
            let newest = FocusRun(createdAt: date, goalSeconds: 1_200, theme: "garden")
            let older = FocusRun(createdAt: date.addingTimeInterval(-100), startedAt: date, progressSeconds: 12.5)
            let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode([newest, older])) as? [Any])
            let data = try JSONSerialization.data(withJSONObject: [objects[0], NSNull(), ["goalSeconds": "bad"], objects[1]])
            defaults.set(data, forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date)

            XCTAssertEqual(store.runs, [newest, older])
            XCTAssertEqual(try savedRuns(defaults), [newest, older])
        }
    }

    func testDuplicateIdentifiersKeepFirstOccurrenceAndOtherHistory() async throws {
        try withDefaults { defaults in
            let newest = FocusRun(createdAt: date)
            let older = FocusRun(createdAt: date.addingTimeInterval(-100))
            defaults.set(try JSONEncoder().encode([newest, newest, older, older]), forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date)

            XCTAssertEqual(store.runs, [newest, older])
        }
    }

    func testRestorationRepairsGoalProgressAndBlankThemeWithoutLosingIdentifiers() async throws {
        try withDefaults { defaults in
            let newest = FocusRun(createdAt: date, progressSeconds: -30, goalSeconds: -1, theme: " \n ")
            let older = FocusRun(createdAt: date.addingTimeInterval(-100), progressSeconds: 10_000, goalSeconds: 100_000, theme: "garden")
            defaults.set(try JSONEncoder().encode([newest, older]), forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date)

            XCTAssertEqual(store.currentRun.id, newest.id)
            XCTAssertEqual(store.currentRun.goalSeconds, 60)
            XCTAssertEqual(store.currentRun.progressSeconds, 0)
            XCTAssertEqual(store.currentRun.theme, "boring")
            XCTAssertEqual(store.history[0].id, older.id)
            XCTAssertEqual(store.history[0].goalSeconds, 7_200)
            XCTAssertEqual(store.history[0].progressSeconds, 7_200)
            XCTAssertEqual(store.history[0].startedAt, older.createdAt)
            XCTAssertEqual(store.history[0].theme, "garden")
        }
    }

    func testRestorationFreezesMistakenlyRunningHistoryAtNextRunCreation() async throws {
        try withDefaults { defaults in
            let newest = FocusRun(createdAt: date.addingTimeInterval(100))
            let older = FocusRun(createdAt: date, startedAt: date, progressSeconds: 20.25, resumedAt: date)
            defaults.set(try JSONEncoder().encode([newest, older]), forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date.addingTimeInterval(1_000))

            XCTAssertEqual(store.currentRun, newest)
            XCTAssertEqual(store.history[0].progressSeconds, 120.25)
            XCTAssertFalse(store.history[0].isRunning)
        }
    }

    func testRestorationRecoversMissingStartAndFutureResumeDate() async throws {
        try withDefaults { defaults in
            let run = FocusRun(createdAt: date, progressSeconds: 12.5, resumedAt: date.addingTimeInterval(100))
            defaults.set(try JSONEncoder().encode([run]), forKey: storageKey)

            let store = RunStore(defaults: defaults, now: date.addingTimeInterval(10))

            XCTAssertEqual(store.currentRun.startedAt, date)
            XCTAssertEqual(store.currentRun.progressSeconds, 12.5)
            XCTAssertEqual(store.currentRun.resumedAt, date.addingTimeInterval(10))
            XCTAssertEqual(store.currentRun.elapsed(at: date.addingTimeInterval(20)), 22.5)
        }
    }

    func testBackwardClockRefreshDoesNotCreateExtraElapsedTime() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)
            store.refresh(at: date.addingTimeInterval(10))

            store.refresh(at: date.addingTimeInterval(5))

            XCTAssertEqual(store.currentRun.progressSeconds, 10)
            XCTAssertEqual(store.currentRun.resumedAt, date.addingTimeInterval(10))
            XCTAssertEqual(store.currentRun.elapsed(at: date.addingTimeInterval(11)), 11)
        }
    }

    func testClockRollbackDoesNotPromoteOldRunAfterRelaunch() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let originalIdentifier = store.currentRun.id
            let earlier = date.addingTimeInterval(-100)
            store.createRun(minutes: 15, theme: "garden", at: earlier)

            let restored = RunStore(defaults: defaults, now: earlier)

            XCTAssertEqual(restored.currentRun.id, store.currentRun.id)
            XCTAssertEqual(restored.currentRun.goalSeconds, 900)
            XCTAssertEqual(restored.history[0].id, originalIdentifier)
        }
    }

    func testStartRunAndRestartPreserveLoop() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.startRun(minutes: 5, theme: "boring", restMinutes: 1, loops: true, at: date)

            XCTAssertTrue(store.currentRun.loops)
            XCTAssertTrue(store.currentRun.isRunning)

            store.restart(at: date.addingTimeInterval(30))

            XCTAssertTrue(store.currentRun.loops)
            XCTAssertFalse(store.currentRun.hasStarted)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testLoopingRunKeepsRunningAcrossCyclesAndRelaunch() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.startRun(minutes: 5, theme: "boring", restMinutes: 1, loops: true, at: date)

            store.refresh(at: date.addingTimeInterval(400))

            XCTAssertTrue(store.currentRun.isRunning)
            XCTAssertEqual(store.currentRun.progressSeconds, 400)
            XCTAssertEqual(store.currentRun.completedCycles(at: date.addingTimeInterval(400)), 1)

            let restored = RunStore(defaults: defaults, now: date.addingTimeInterval(1_000))

            XCTAssertTrue(restored.currentRun.isRunning)
            XCTAssertEqual(restored.currentRun.elapsed(at: date.addingTimeInterval(1_000)), 1_000)
            XCTAssertFalse(restored.currentRun.isComplete(at: date.addingTimeInterval(1_000)))
        }
    }

    func testStopArchivesRunAndLeavesFreshReadyRunWithSameSettings() async throws {
        try withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.startRun(minutes: 5, theme: "garden", restMinutes: 1, loops: true, at: date)
            let stoppedID = store.currentRun.id

            store.stop(at: date.addingTimeInterval(500))

            XCTAssertNotEqual(store.currentRun.id, stoppedID)
            XCTAssertFalse(store.currentRun.hasStarted)
            XCTAssertFalse(store.currentRun.isComplete(at: date.addingTimeInterval(500)))
            XCTAssertEqual(store.currentRun.goalSeconds, 300)
            XCTAssertEqual(store.currentRun.restSeconds, 60)
            XCTAssertEqual(store.currentRun.theme, "garden")
            XCTAssertTrue(store.currentRun.loops)
            XCTAssertEqual(store.history[0].id, stoppedID)
            XCTAssertEqual(store.history[0].progressSeconds, 500)
            XCTAssertFalse(store.history[0].isRunning)
            XCTAssertEqual(try savedRuns(defaults), store.runs)
        }
    }

    func testStopCountsTimeAfterAnExpiredPauseWindow() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            store.start(at: date)
            store.pause(at: date.addingTimeInterval(100))

            store.stop(at: date.addingTimeInterval(200))

            XCTAssertEqual(store.history[0].progressSeconds, 140)
            XCTAssertNil(store.history[0].pausedAt)
            XCTAssertFalse(store.currentRun.hasStarted)
        }
    }

    func testStopIgnoresReadyAndCompletedRuns() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)
            let readyID = store.currentRun.id
            store.stop(at: date)
            XCTAssertEqual(store.currentRun.id, readyID)

            store.createRun(minutes: 1, theme: "boring", at: date)
            let completedID = store.currentRun.id
            store.start(at: date)
            store.stop(at: date.addingTimeInterval(120))

            XCTAssertEqual(store.currentRun.id, completedID)
            XCTAssertEqual(store.currentRun.progressSeconds, 60)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "RunStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func savedRuns(_ defaults: UserDefaults) throws -> [FocusRun] {
        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        return try JSONDecoder().decode([FocusRun].self, from: data)
    }

    func testPauseOpensWindowAndRefreshAutoResumesAtDeadline() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.start(at: date)
            store.pause(at: date.addingTimeInterval(10))
            XCTAssertEqual(store.currentRun.pausedAt, date.addingTimeInterval(10))

            store.refresh(at: date.addingTimeInterval(40))
            XCTAssertFalse(store.currentRun.isRunning)

            store.refresh(at: date.addingTimeInterval(100))
            XCTAssertTrue(store.currentRun.isRunning)
            XCTAssertNil(store.currentRun.pausedAt)
            XCTAssertEqual(store.currentRun.elapsed(at: date.addingTimeInterval(100)), 40)
        }
    }

    func testManualResumeClearsPauseWindow() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.start(at: date)
            store.pause(at: date.addingTimeInterval(10))
            store.start(at: date.addingTimeInterval(20))

            XCTAssertNil(store.currentRun.pausedAt)
            XCTAssertTrue(store.currentRun.isRunning)
        }
    }

    func testNewRunDoesNotLeavePauseWindowOnHistory() async {
        withDefaults { defaults in
            let store = RunStore(defaults: defaults, now: date)

            store.start(at: date)
            store.pause(at: date.addingTimeInterval(10))
            store.createRun(minutes: 5, theme: "boring", at: date.addingTimeInterval(20))

            XCTAssertNil(store.history[0].pausedAt)
            XCTAssertNil(store.currentRun.pausedAt)
        }
    }
}
