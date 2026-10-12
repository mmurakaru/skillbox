import Testing
@testable import ModelInventory

struct ModelRAMFitTests {
    @Test func estimateAddsTwentyPercentOverhead() {
        #expect(ModelRAMEstimate.bytes(forModelSize: 1_000_000_000) == 1_200_000_000)
        #expect(ModelRAMEstimate.bytes(forModelSize: 0) == 0)
    }

    @Test func fitsWellUnderPhysicalMemory() {
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 5_000_000_000, physicalMemoryBytes: 36_000_000_000) == .fits)
    }

    @Test func tightNearTheLimit() {
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 30_000_000_000, physicalMemoryBytes: 36_000_000_000) == .tight)
    }

    @Test func tooBigOverPhysicalMemory() {
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 40_000_000_000, physicalMemoryBytes: 36_000_000_000) == .tooBig)
    }

    @Test func zeroPhysicalMemoryIsTooBig() {
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 1, physicalMemoryBytes: 0) == .tooBig)
    }

    @Test func boundariesAtSeventyAndHundredPercent() {
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 70, physicalMemoryBytes: 100) == .fits)
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 71, physicalMemoryBytes: 100) == .tight)
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 100, physicalMemoryBytes: 100) == .tight)
        #expect(ModelRAMFit.evaluate(estimatedRAMBytes: 101, physicalMemoryBytes: 100) == .tooBig)
    }
}
