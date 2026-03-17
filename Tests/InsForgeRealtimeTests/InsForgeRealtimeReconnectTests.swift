import XCTest
@testable import InsForgeRealtime

final class InsForgeRealtimeReconnectTests: XCTestCase {
    func testReconnectPolicyBaseDelayGrowsExponentiallyAndCaps() {
        let policy = ReconnectPolicy.default

        XCTAssertEqual(policy.baseDelay(forAttempt: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.baseDelay(forAttempt: 2), 2.0, accuracy: 0.0001)
        XCTAssertEqual(policy.baseDelay(forAttempt: 3), 4.0, accuracy: 0.0001)
        XCTAssertEqual(policy.baseDelay(forAttempt: 4), 8.0, accuracy: 0.0001)

        // Attempts after the cap should never exceed maxDelay (30s)
        XCTAssertEqual(policy.baseDelay(forAttempt: 6), 30.0, accuracy: 0.0001)
        XCTAssertEqual(policy.baseDelay(forAttempt: 9), 30.0, accuracy: 0.0001)
    }

    func testReconnectPolicyJitterStaysWithinExpectedBounds() {
        let policy = ReconnectPolicy.default
        let baseDelay: TimeInterval = 10

        // With ±20% jitter, bounds are [8.0, 12.0]
        XCTAssertEqual(policy.applyJitter(to: baseDelay, randomUnit: 0.0), 8.0, accuracy: 0.0001)
        XCTAssertEqual(policy.applyJitter(to: baseDelay, randomUnit: 0.5), 10.0, accuracy: 0.0001)
        XCTAssertEqual(policy.applyJitter(to: baseDelay, randomUnit: 1.0), 12.0, accuracy: 0.0001)
    }

    func testReconnectDecisionStopsAtMaxAttempts() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()

        for attempt in 1...policy.maxAttempts {
            let decision = state.nextReconnectDecision(
                policy: policy,
                hasPendingReconnectTask: false,
                hasActiveConnectTask: false,
                isSocketConnected: false
            )

            switch decision {
            case .schedule(let currentAttempt, _):
                XCTAssertEqual(currentAttempt, attempt)
            default:
                XCTFail("Expected scheduled reconnect attempt \(attempt)")
            }
        }

        let exhaustedDecision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        XCTAssertEqual(exhaustedDecision, .maxedOut)
        XCTAssertFalse(state.shouldMaintainConnection)
    }

    func testReconnectDecisionBlockedWhenNetworkUnavailable() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()
        _ = state.applyNetworkAvailability(false)

        let decision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        XCTAssertEqual(decision, .none)
    }

    func testReconnectDecisionResumesAfterNetworkBecomesAvailable() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()

        _ = state.applyNetworkAvailability(false)
        let blockedDecision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )
        XCTAssertEqual(blockedDecision, .none)

        _ = state.applyNetworkAvailability(true)
        let resumedDecision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        if case .schedule(let attempt, let baseDelay) = resumedDecision {
            XCTAssertEqual(attempt, 1)
            XCTAssertEqual(baseDelay, 1.0, accuracy: 0.0001)
        } else {
            XCTFail("Expected reconnect to be scheduled when network is restored")
        }
    }

    func testManualDisconnectPreventsReconnect() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()
        state.markManualDisconnect()

        let decision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        XCTAssertEqual(decision, .none)
        XCTAssertFalse(state.shouldMaintainConnection)
        XCTAssertTrue(state.isManuallyDisconnected)
    }

    func testSuccessfulConnectResetsRetryAttempt() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()

        _ = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )
        _ = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        XCTAssertEqual(state.retryAttempt, 2)

        state.markConnectSucceeded()

        XCTAssertEqual(state.retryAttempt, 0)
        XCTAssertTrue(state.shouldMaintainConnection)
        XCTAssertFalse(state.isManuallyDisconnected)
    }

    func testReconnectDecisionIsSuppressedWhenReconnectTaskIsPending() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()

        let decision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: true,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        XCTAssertEqual(decision, .none)
        XCTAssertEqual(state.retryAttempt, 0)
    }

    func testRetryAttemptResetsWhenNetworkIsRestored() {
        let policy = ReconnectPolicy.default
        var state = ReconnectRuntimeState()
        state.prepareForConnectionRequest()

        _ = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )
        _ = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        XCTAssertEqual(state.retryAttempt, 2)

        let becameOffline = state.applyNetworkAvailability(false)
        XCTAssertTrue(becameOffline.didChange)
        XCTAssertFalse(becameOffline.becameAvailable)
        XCTAssertEqual(state.retryAttempt, 2)

        let becameOnline = state.applyNetworkAvailability(true)
        XCTAssertTrue(becameOnline.didChange)
        XCTAssertTrue(becameOnline.becameAvailable)
        XCTAssertEqual(state.retryAttempt, 0)

        let decision = state.nextReconnectDecision(
            policy: policy,
            hasPendingReconnectTask: false,
            hasActiveConnectTask: false,
            isSocketConnected: false
        )

        if case .schedule(let attempt, _) = decision {
            XCTAssertEqual(attempt, 1)
        } else {
            XCTFail("Expected reconnect attempt counter to restart after network recovery")
        }
    }
}
