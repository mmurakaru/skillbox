import Testing
@testable import ModelInventory

struct ModelParameterSizeBucketTests {
    @Test func parsesBillions() {
        #expect(ModelParameterSizeBucket.billions(from: "8B") == 8)
        #expect(ModelParameterSizeBucket.billions(from: "70B") == 70)
        #expect(ModelParameterSizeBucket.billions(from: "1.5B") == 1.5)
        #expect(ModelParameterSizeBucket.billions(from: "8X7B") == 56)
        #expect(ModelParameterSizeBucket.billions(from: nil) == nil)
        #expect(ModelParameterSizeBucket.billions(from: "") == nil)
    }

    @Test func anyMatchesEverythingIncludingUnknownSizes() {
        #expect(ModelParameterSizeBucket.any.matches(nil))
        #expect(ModelParameterSizeBucket.any.matches("8B"))
    }

    @Test func bucketBoundaries() {
        #expect(ModelParameterSizeBucket.small.matches("4B"))
        #expect(!ModelParameterSizeBucket.small.matches("8B"))
        #expect(ModelParameterSizeBucket.medium.matches("8B"))
        #expect(ModelParameterSizeBucket.medium.matches("13B"))
        #expect(!ModelParameterSizeBucket.medium.matches("34B"))
        #expect(ModelParameterSizeBucket.large.matches("34B"))
        #expect(ModelParameterSizeBucket.extraLarge.matches("70B"))
    }

    @Test func sizedBucketsRejectUnknownSizes() {
        #expect(!ModelParameterSizeBucket.small.matches(nil))
        #expect(!ModelParameterSizeBucket.extraLarge.matches(nil))
    }
}
