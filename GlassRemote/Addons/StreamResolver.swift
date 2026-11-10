import Foundation

struct StreamOption: Identifiable, Hashable, Sendable {
    let id: String
    let addonName: String
    let stream: AddonStream
}

struct StreamLookup: Sendable {
    var options: [StreamOption] = []
    /// One line per add-on that failed, e.g. "Torrentio: Couldn't reach the add-on."
    var failures: [String] = []
    var queried = 0
}

/// Asks every enabled stream add-on in parallel. Each request has the client's own timeout, so one
/// slow add-on never blocks the others; results keep the user's add-on order and each add-on's own
/// ordering, with streams the TV can actually play moved ahead of ones it can't.
enum StreamResolver {
    static func lookup(type: String, id: String, sources: [StreamSource], client: AddonClient = .shared) async -> StreamLookup {
        var lookup = StreamLookup()
        lookup.queried = sources.count
        guard !sources.isEmpty else { return lookup }
        var collected: [(Int, [AddonStream])] = []
        await withTaskGroup(of: (Int, [AddonStream], String?).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do {
                        return (index, try await client.streams(type: type, id: id, base: source.base), nil)
                    } catch {
                        return (index, [], describe(error))
                    }
                }
            }
            for await (index, streams, failure) in group {
                if let failure { lookup.failures.append("\(sources[index].name): \(failure)") }
                collected.append((index, streams))
            }
        }
        var options: [StreamOption] = []
        for (index, streams) in collected.sorted(by: { $0.0 < $1.0 }) {
            let source = sources[index]
            for (n, stream) in streams.enumerated() {
                options.append(StreamOption(id: "\(source.addonID)#\(n)", addonName: source.name, stream: stream))
            }
        }
        lookup.options = rank(options)
        return lookup
    }

    /// Stable: playable before unplayable, otherwise original order.
    static func rank(_ options: [StreamOption]) -> [StreamOption] {
        options.enumerated().sorted { a, b in
            let pa = a.element.stream.canSendToTV, pb = b.element.stream.canSendToTV
            if pa != pb { return pa }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func describe(_ error: Error) -> String {
        if error is CancellationError { return "Cancelled." }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
