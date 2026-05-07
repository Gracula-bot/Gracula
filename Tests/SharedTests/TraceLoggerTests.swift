import Foundation
import Shared
import Testing

@Test
func traceLoggerRedactsSensitiveFieldsAndAppliesLogLevel() async {
    let logger = TraceLogger(
        configuration: TraceLoggingConfiguration(
            enabled: true,
            includeFullContext: true,
            includeResponseBodies: true,
            redactSensitiveData: true,
            minimumLevel: .info
        ),
        logFileURL: nil
    )
    let trace = RequestTraceContext(traceID: "trace-shared-test", sessionID: "session-1")

    await RequestTrace.$current.withValue(trace) {
        await logger.record(
            level: .debug,
            event: "debug.event",
            component: "TraceLoggerTests",
            payload: ["message": .string("hidden")]
        )
        await logger.record(
            level: .info,
            event: "info.event",
            component: "TraceLoggerTests",
            payload: [
                "authorization": .string("Bearer sk-secret-value"),
                "nested": .object([
                    "apiKey": .string("live-secret"),
                    "note": .string("user@example.com +79991234567")
                ])
            ]
        )
    }

    let events = await logger.events()
    #expect(events.count == 1)
    #expect(events[0].traceID == "trace-shared-test")
    #expect(events[0].event == "info.event")
    #expect(events[0].payload["authorization"] == .string("<redacted>"))
    #expect(events[0].payload["nested"] == .object([
        "apiKey": .string("<redacted>"),
        "note": .string("<redacted:email> <redacted:phone>")
    ]))
}
