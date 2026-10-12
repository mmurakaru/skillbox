import Foundation
import Testing

@testable import Skillbox

struct ClaudeCLIUsageTests {
    @Test func parsesQuotaRowsAndIgnoresUsageInsights() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-11T13:00:00Z"))
        let status = Data(
            #"{"loggedIn":true,"authMethod":"claude.ai","email":"work@example.com","subscriptionType":"team","orgId":"work"}"#.utf8)
        let identity = try ClaudeCLIUsageReader.decodeIdentity(status)
        let report = """
            You are currently using your subscription to power your Claude Code usage
            Current session: 2% used · resets Oct 11 at 7:50pm (Europe/Madrid)
            Current week (all models): 75% used · resets Oct 12 at 8am (Europe/Madrid)
            Current week (Fable): 14% used · resets Oct 12 at 8am (Europe/Madrid)
            What's contributing to your limits usage?
              99% of your usage came from subagent-heavy sessions
            """
        let snapshot = try ClaudeCLIUsageReader.decodeReport(report, identity: identity, now: now)

        #expect(snapshot.windows.map(\.label) == ["Current session", "Weekly limit", "Fable weekly limit"])
        #expect(snapshot.windows.map(\.usedPercent) == [2, 75, 14])
        #expect(snapshot.windows.first?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-11T17:50:00Z"))
        #expect(snapshot.accountEmail == "work@example.com")
        #expect(snapshot.plan == "Team")
    }

    @Test func insightsAndInvalidPercentagesNeverBecomeQuotas() throws {
        let identity = try ClaudeCLIUsageReader.decodeIdentity(
            Data(#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"pro"}"#.utf8))

        for report in ["99% of your usage came from sessions", "Current session: 101% used", "Current week (all models): NaN% used"] {
            #expect(throws: (any Error).self) { try ClaudeCLIUsageReader.decodeReport(report, identity: identity) }
        }
        #expect(throws: (any Error).self) { try ClaudeCLIUsageReader.decodeIdentity(Data(#"{"loggedIn":false}"#.utf8)) }
    }

    @Test func accountSwitchDiscardsUsageInsteadOfMislabelingIt() async throws {
        let reader = ClaudeCLIUsageReader(commandRunner: { arguments in
            if arguments == ["auth", "status"] {
                return Data(#"{"loggedIn":true,"authMethod":"claude.ai","email":"personal@example.com","subscriptionType":"pro"}"#.utf8)
            }

            return Data("Current week (all models): 25% used".utf8)
        })
        let snapshot = try await reader.fetchUsage()

        #expect(snapshot.accountEmail == "personal@example.com")
        let runner = SwitchingClaudeUsageRunner()
        let switching = ClaudeCLIUsageReader(commandRunner: { try await runner.run($0) })

        await #expect(throws: (any Error).self) { try await switching.fetchUsage() }
    }

    @Test func serviceUsesTrustedCLIWithoutForeignKeychainAccess() async throws {
        let service = ProviderUsageService(
            claudeCLIReader: {
                .init(
                    provider: .claude, plan: "Team", windows: [.init(label: "Weekly limit", usedPercent: 75, resetsAt: nil)],
                    updatedAt: Date(), source: .live, accountEmail: "work@example.com")
            },
            claudeCredentialsReader: { _ in
                Issue.record("The CLI connection must not request foreign Keychain access")

                return .init(values: [:], source: .file)
            })
        let snapshot = try await service.fetchUsage(for: .claude)

        #expect(snapshot.plan == "Team")
        #expect(snapshot.accountEmail == "work@example.com")
    }
}

private actor SwitchingClaudeUsageRunner {
    private var authCalls = 0
    func run(_ arguments: [String]) throws -> Data {
        if arguments == ["auth", "status"] {
            authCalls += 1

            return Data(
                "{\"loggedIn\":true,\"authMethod\":\"claude.ai\",\"email\":\"\(authCalls == 1 ? "personal" : "work")@example.com\"}".utf8)
        }

        return Data("Current week (all models): 25% used".utf8)
    }
}
