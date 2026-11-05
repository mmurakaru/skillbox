import Foundation
import Testing

@testable import Skillbox

struct SparkleUpdateConfigurationTests {
    @Test func sourceBuildsDoNotStartAnUnconfiguredUpdater() {
        #expect(!SparkleUpdateConfiguration.hasValidSigningKey(nil))
        #expect(!SparkleUpdateConfiguration.hasValidSigningKey(""))
        #expect(!SparkleUpdateConfiguration.hasValidSigningKey("REPLACE_WITH_SPARKLE_PUBLIC_KEY"))
        #expect(!SparkleUpdateConfiguration.hasValidSigningKey(Data(repeating: 1, count: 31).base64EncodedString()))
        #expect(SparkleUpdateConfiguration.hasValidSigningKey(Data(repeating: 1, count: 32).base64EncodedString()))
    }
}
