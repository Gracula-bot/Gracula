import Foundation

public actor PendingTelegramReplyStore {
    public typealias Clock = @Sendable () -> Date

    private var pendingReply: PendingTelegramReply?
    private let ttl: TimeInterval
    private let clock: Clock

    public init(ttl: TimeInterval = 120, clock: @escaping Clock = { Date() }) {
        self.ttl = ttl
        self.clock = clock
    }

    public func save(_ reply: PendingTelegramReply) {
        pendingReply = reply
    }

    public func current() -> PendingTelegramReply? {
        guard var reply = pendingReply else {
            return nil
        }

        if isExpired(reply) {
            reply.status = .expired
            pendingReply = nil
            return reply
        }

        return reply
    }

    public func requireSendableReply() throws -> PendingTelegramReply {
        guard let reply = pendingReply else {
            throw TelegramCommandError.noPendingReply
        }

        guard !isExpired(reply) else {
            pendingReply = nil
            throw TelegramCommandError.pendingReplyExpired
        }

        return reply
    }

    public func markSentAndClear() {
        if var reply = pendingReply {
            reply.status = .sent
        }
        pendingReply = nil
    }

    public func cancelAndClear() throws {
        guard pendingReply != nil else {
            throw TelegramCommandError.noPendingReply
        }
        pendingReply = nil
    }

    public func clear() {
        pendingReply = nil
    }

    private func isExpired(_ reply: PendingTelegramReply) -> Bool {
        clock().timeIntervalSince(reply.createdAt) > ttl
    }
}

