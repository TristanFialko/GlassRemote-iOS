import Foundation

// Phase 9 recovery §5: the Samsung TV's UPnP RenderingControl replies, parsed strictly.
//
// Diagnosis (physical-device regression "volume does not work"): the old exchange returned whatever
// bytes had arrived when the socket errored or the 2.5 s timer fired, and only the status line was
// checked. A half-received reply, an empty 200 or a SOAP fault inside a 200 therefore counted as a
// successful SetVolume, the slider believed the TV had moved, and nothing told the user it had not.
//
// Now a reply is accepted only when it is complete by its own framing (Content-Length, chunked
// encoding, or the TV closing a connection that declared neither), is HTTP 200, carries no SOAP
// fault / UPnPError, and actually contains the `<Action>Response` element. Pure, so every case is
// unit tested without a TV (Phase9RecoveryVolumeTests).

/// One HTTP reply from the TV, with lower-cased header names.
struct UPnPHTTPResponse: Equatable, Sendable {
    var status: Int
    var headers: [String: String]
    var body: String

    enum Parse: Equatable, Sendable {
        /// Every byte the framing promised has arrived.
        case complete(UPnPHTTPResponse)
        /// More bytes are needed. If the connection has already ended this is a failure.
        case incomplete
        /// Not an HTTP reply the app can trust.
        case malformed
    }

    /// Parses `data` received so far. `connectionClosed` is true only when the TV closed the
    /// connection cleanly; that is the end of a body that declared neither a length nor chunks.
    static func parse(_ data: Data, connectionClosed: Bool) -> Parse {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return connectionClosed && !data.isEmpty ? .malformed : .incomplete
        }
        let head = String(decoding: data[data.startIndex..<headEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .malformed }
        let statusParts = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/"),
              let status = Int(statusParts[1]), (100...599).contains(status) else { return .malformed }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }
        let rest = Data(data[headEnd.upperBound...])

        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            switch decodeChunked(rest) {
            case .complete(let body):
                return .complete(UPnPHTTPResponse(status: status, headers: headers,
                                                  body: String(decoding: body, as: UTF8.self)))
            case .incomplete: return .incomplete
            case .malformed: return .malformed
            }
        }
        if let declared = headers["content-length"] {
            guard let length = Int(declared), length >= 0 else { return .malformed }
            guard rest.count >= length else { return .incomplete }
            return .complete(UPnPHTTPResponse(status: status, headers: headers,
                                              body: String(decoding: rest.prefix(length), as: UTF8.self)))
        }
        // Neither a length nor chunks: the body ends only when the TV closes the connection.
        guard connectionClosed else { return .incomplete }
        return .complete(UPnPHTTPResponse(status: status, headers: headers,
                                          body: String(decoding: rest, as: UTF8.self)))
    }

    enum Chunked: Equatable, Sendable { case complete(Data), incomplete, malformed }

    /// RFC 9112 chunked transfer coding. Chunk extensions are ignored; trailers are not needed.
    static func decodeChunked(_ data: Data) -> Chunked {
        let bytes = [UInt8](data)
        var index = 0
        var out: [UInt8] = []
        while true {
            guard let lineEnd = crlf(in: bytes, from: index) else { return .incomplete }
            let sizeLine = String(decoding: bytes[index..<lineEnd], as: UTF8.self)
            let sizeText = (sizeLine.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) }) ?? ""
            guard !sizeText.isEmpty, let size = Int(sizeText, radix: 16), size >= 0 else { return .malformed }
            index = lineEnd + 2
            if size == 0 { return .complete(Data(out)) }
            guard bytes.count >= index + size + 2 else { return .incomplete }
            out.append(contentsOf: bytes[index..<(index + size)])
            index += size
            guard bytes[index] == 13, bytes[index + 1] == 10 else { return .malformed }
            index += 2
        }
    }

    private static func crlf(in bytes: [UInt8], from start: Int) -> Int? {
        var i = start
        while i + 1 < bytes.count {
            if bytes[i] == 13, bytes[i + 1] == 10 { return i }
            i += 1
        }
        return nil
    }

    /// A SOAP fault (normally HTTP 500, but some firmware sends it with 200) or a UPnPError body.
    var isSOAPFault: Bool {
        body.range(of: "Fault>", options: .caseInsensitive) != nil || body.contains("UPnPError")
    }

    /// The UPnP error code inside a fault (e.g. 401 Invalid Action, 501 Action Failed).
    var upnpErrorCode: Int? { UPnPRenderingControl.integer("errorCode", in: body) }

    /// True only for a 200 reply without a fault that really answers `action`.
    func confirms(_ action: String) -> Bool {
        status == 200 && !isSOAPFault && body.contains("\(action)Response")
    }
}

/// The RenderingControl requests the app sends, and the values it reads back. Pure.
enum UPnPRenderingControl {
    static let port: UInt16 = 9197
    static let path = "/upnp/control/RenderingControl1"
    static let service = "urn:schemas-upnp-org:service:RenderingControl:1"
    static let master = "<InstanceID>0</InstanceID><Channel>Master</Channel>"

    static func setVolumeArguments(_ level: Int) -> String {
        master + "<DesiredVolume>\(min(max(level, 0), 100))</DesiredVolume>"
    }

    static func setMuteArguments(_ muted: Bool) -> String {
        master + "<DesiredMute>\(muted ? 1 : 0)</DesiredMute>"
    }

    static func envelope(action: String, arguments: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
            + "<u:\(action) xmlns:u=\"\(service)\">\(arguments)</u:\(action)>"
            + "</s:Body></s:Envelope>"
    }

    /// The full request. CONTENT-LENGTH counts UTF-8 bytes, so the TV never waits for more body.
    static func request(host: String, action: String, arguments: String) -> Data {
        let payload = Data(envelope(action: action, arguments: arguments).utf8)
        let head = "POST \(path) HTTP/1.1\r\n"
            + "HOST: \(host):\(port)\r\n"
            + "CONTENT-TYPE: text/xml; charset=\"utf-8\"\r\n"
            + "SOAPACTION: \"\(service)#\(action)\"\r\n"
            + "CONTENT-LENGTH: \(payload.count)\r\n"
            + "CONNECTION: close\r\n\r\n"
        return Data(head.utf8) + payload
    }

    /// Text of the first `<tag>` element (namespace prefixes on the tag are accepted).
    static func element(_ tag: String, in xml: String) -> String? {
        for open in ["<\(tag)>", ":\(tag)>"] {
            guard let start = xml.range(of: open) else { continue }
            guard let end = xml.range(of: "</", range: start.upperBound..<xml.endIndex) else { return nil }
            return xml[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func integer(_ tag: String, in xml: String) -> Int? {
        element(tag, in: xml).flatMap { Int($0) }
    }

    /// CurrentVolume, only when it is a real 0...100 level.
    static func currentVolume(in xml: String) -> Int? {
        guard let value = integer("CurrentVolume", in: xml), (0...100).contains(value) else { return nil }
        return value
    }

    /// CurrentMute as 0/1 or true/false (both appear in the wild).
    static func currentMute(in xml: String) -> Bool? {
        switch element("CurrentMute", in: xml)?.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}
