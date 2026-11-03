import Testing
@testable import BeatTrainCore

struct TimingConfigurationTests {

    @Test func backWindowIsTotalMinusFront() {
        let timing = TimingConfiguration(totalSec: 0.12, frontSec: 0.05, offsetMs: 70)
        #expect(abs(timing.hitWindowTotalSec - 0.12) < 1e-9)
        #expect(abs(timing.hitWindowFrontSec - 0.05) < 1e-9)
        #expect(abs(timing.hitWindowBackSec - 0.07) < 1e-9)
    }

    @Test func clampsTotalIntoRange() {
        #expect(TimingConfiguration(totalSec: 0.0, frontSec: 0, offsetMs: 0).hitWindowTotalSec == TimingConfiguration.minTotalSec)
        #expect(TimingConfiguration(totalSec: 1.0, frontSec: 0, offsetMs: 0).hitWindowTotalSec == TimingConfiguration.maxTotalSec)
    }

    @Test func frontNeverLeavesLessThanMinSegmentForBack() {
        // front larger than total → clamped so back >= minSegmentSec.
        let timing = TimingConfiguration(totalSec: 0.10, frontSec: 0.50, offsetMs: 0)
        #expect(timing.hitWindowFrontSec <= timing.hitWindowTotalSec - TimingConfiguration.minSegmentSec + 1e-9)
        #expect(timing.hitWindowBackSec >= TimingConfiguration.minSegmentSec - 1e-9)
    }

    @Test func clampsOffsetIntoRange() {
        #expect(TimingConfiguration(totalSec: 0.12, frontSec: 0.05, offsetMs: 999).timingOffsetMs == TimingConfiguration.offsetRangeMs)
        #expect(TimingConfiguration(totalSec: 0.12, frontSec: 0.05, offsetMs: -999).timingOffsetMs == -TimingConfiguration.offsetRangeMs)
    }

    @Test func offsetSecondsDerivedFromMilliseconds() {
        #expect(abs(TimingConfiguration(totalSec: 0.12, frontSec: 0.05, offsetMs: 70).timingOffsetSec - 0.07) < 1e-9)
    }
}
