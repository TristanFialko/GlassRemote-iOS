import Foundation

// Minimal protobuf wire codec for the Android TV Remote Service v2 protocol.
//
// Only the wire features the two v2 schemas use are supported: varint (0) and length-delimited (2)
// fields, plus skipping fixed32/fixed64 fields a newer device might add. Groups are rejected.
// Field numbers and enum values live in RemoteV2Polo.swift and RemoteV2Messages.swift and come
// from the pinned reference schemas listed in audit/REMOTE_V2_PROTOCOL_NOTES.md.

enum ProtoWireError: Error, Equatable {
    /// The input ended in the middle of a tag, varint or length-delimited field.
    case truncated
    /// A varint ran past 10 bytes or overflowed 64 bits.
    case varintTooLong
    /// Field number 0, or a wire type this codec does not accept (groups, 6, 7).
    case invalidTag(UInt64)
    /// A field had a different wire type than its schema says.
    case unexpectedWireType(field: Int)
    /// A required field was missing.
    case missingField(Int)
    /// A frame's declared length exceeds the configured limit.
    case frameTooLarge(Int)
    /// A string field was not valid UTF-8.
    case invalidUTF8(field: Int)
}

enum ProtoWireType: UInt8 {
    case varint = 0, fixed64 = 1, lengthDelimited = 2, fixed32 = 5
}

enum ProtoVarint {
    static func encode(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    /// Decodes a varint at `start`. Returns nil when the input ends before the varint does (more bytes
    /// may still arrive); throws when the varint can never be valid.
    static func decode(_ bytes: [UInt8], from start: Int) throws -> (value: UInt64, next: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if shift == 63 && byte > 1 { throw ProtoWireError.varintTooLong }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, index) }
            shift += 7
            if shift > 63 { throw ProtoWireError.varintTooLong }
        }
        return nil
    }
}

/// Serialises fields in the order they are written. Callers write fields in ascending field-number
/// order, which is what the reference (Google protobuf) serialiser produces, so byte fixtures match.
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    private mutating func tag(_ field: Int, _ type: ProtoWireType) {
        bytes += ProtoVarint.encode(UInt64(field) << 3 | UInt64(type.rawValue))
    }

    mutating func uint(_ field: Int, _ value: UInt64) {
        tag(field, .varint)
        bytes += ProtoVarint.encode(value)
    }

    /// proto3 scalars are omitted when they hold the default value.
    mutating func uintIfNonZero(_ field: Int, _ value: UInt64) {
        if value != 0 { uint(field, value) }
    }

    /// int32 and enum values: negatives are sign-extended to 10 bytes, as protobuf specifies.
    mutating func int32(_ field: Int, _ value: Int32) {
        uint(field, UInt64(bitPattern: Int64(value)))
    }

    mutating func int32IfNonZero(_ field: Int, _ value: Int32) {
        if value != 0 { int32(field, value) }
    }

    mutating func boolIfTrue(_ field: Int, _ value: Bool) {
        if value { uint(field, 1) }
    }

    mutating func data(_ field: Int, _ value: [UInt8]) {
        tag(field, .lengthDelimited)
        bytes += ProtoVarint.encode(UInt64(value.count))
        bytes += value
    }

    mutating func string(_ field: Int, _ value: String) {
        data(field, Array(value.utf8))
    }

    mutating func stringIfNonEmpty(_ field: Int, _ value: String) {
        if !value.isEmpty { string(field, value) }
    }

    /// A nested message. It is written even when empty: presence is meaningful (e.g. ConfigurationAck).
    mutating func message(_ field: Int, _ value: ProtoWriter) {
        data(field, value.bytes)
    }
}

struct ProtoField: Equatable {
    let number: Int
    let wireType: ProtoWireType
    /// Value of a varint field (0 for other wire types).
    let varint: UInt64
    /// Payload of a length-delimited or fixed field (empty for varints).
    let payload: [UInt8]
}

/// A parsed message: every field in wire order. Accessors use the last occurrence of a scalar field,
/// as protobuf does, and reject a field whose wire type contradicts the schema.
struct ProtoMessage {
    let fields: [ProtoField]

    init(_ bytes: [UInt8]) throws {
        var fields: [ProtoField] = []
        var index = 0
        while index < bytes.count {
            guard let tagResult = try ProtoVarint.decode(bytes, from: index) else { throw ProtoWireError.truncated }
            let tag = tagResult.value
            let number = tag >> 3
            guard number >= 1, number <= 536_870_911,
                  let type = ProtoWireType(rawValue: UInt8(tag & 0x7)) else { throw ProtoWireError.invalidTag(tag) }
            index = tagResult.next
            switch type {
            case .varint:
                guard let result = try ProtoVarint.decode(bytes, from: index) else { throw ProtoWireError.truncated }
                fields.append(ProtoField(number: Int(number), wireType: type, varint: result.value, payload: []))
                index = result.next
            case .lengthDelimited:
                guard let result = try ProtoVarint.decode(bytes, from: index) else { throw ProtoWireError.truncated }
                guard result.value <= UInt64(bytes.count - result.next) else { throw ProtoWireError.truncated }
                let end = result.next + Int(result.value)
                fields.append(ProtoField(number: Int(number), wireType: type, varint: 0,
                                         payload: Array(bytes[result.next..<end])))
                index = end
            case .fixed64, .fixed32:
                let width = type == .fixed64 ? 8 : 4
                guard bytes.count - index >= width else { throw ProtoWireError.truncated }
                fields.append(ProtoField(number: Int(number), wireType: type, varint: 0,
                                         payload: Array(bytes[index..<index + width])))
                index += width
            }
        }
        self.fields = fields
    }

    var fieldNumbers: [Int] { fields.map { $0.number } }

    func has(_ number: Int) -> Bool { fields.contains { $0.number == number } }

    private func last(_ number: Int, _ type: ProtoWireType) throws -> ProtoField? {
        guard let field = fields.last(where: { $0.number == number }) else { return nil }
        guard field.wireType == type else { throw ProtoWireError.unexpectedWireType(field: number) }
        return field
    }

    func uint(_ number: Int) throws -> UInt64? { try last(number, .varint)?.varint }

    func int32(_ number: Int) throws -> Int32? {
        try uint(number).map { Int32(truncatingIfNeeded: $0) }
    }

    func uint32(_ number: Int) throws -> UInt32? {
        try uint(number).map { UInt32(truncatingIfNeeded: $0) }
    }

    func bool(_ number: Int) throws -> Bool? { try uint(number).map { $0 != 0 } }

    func data(_ number: Int) throws -> [UInt8]? { try last(number, .lengthDelimited)?.payload }

    func string(_ number: Int) throws -> String? {
        guard let raw = try data(number) else { return nil }
        guard let text = String(bytes: raw, encoding: .utf8) else { throw ProtoWireError.invalidUTF8(field: number) }
        return text
    }

    func message(_ number: Int) throws -> ProtoMessage? {
        guard let raw = try data(number) else { return nil }
        return try ProtoMessage(raw)
    }

    func messages(_ number: Int) throws -> [ProtoMessage] {
        var out: [ProtoMessage] = []
        for field in fields where field.number == number {
            guard field.wireType == .lengthDelimited else { throw ProtoWireError.unexpectedWireType(field: number) }
            out.append(try ProtoMessage(field.payload))
        }
        return out
    }
}

/// Splits a TLS byte stream into varint-length-prefixed messages. Bytes may arrive in any split:
/// partial frames, several frames at once, or a split inside the length prefix. A frame longer than
/// `maxFrameLength` or a corrupt prefix is unrecoverable (the stream cannot resynchronise), so the
/// decoder clears its buffer and throws, and the caller closes the connection.
struct RemoteV2FrameDecoder {
    /// Generous for every message this app reads (the largest, RemoteConfigure, is under 200 bytes);
    /// voice payloads are never requested.
    static let defaultMaxFrameLength = 64 * 1024

    let maxFrameLength: Int
    private var buffer: [UInt8] = []

    init(maxFrameLength: Int = RemoteV2FrameDecoder.defaultMaxFrameLength) {
        self.maxFrameLength = maxFrameLength
    }

    var bufferedByteCount: Int { buffer.count }

    static func frame(_ body: [UInt8]) -> [UInt8] {
        ProtoVarint.encode(UInt64(body.count)) + body
    }

    /// Appends received bytes and returns every complete message body, in order.
    mutating func append(_ data: [UInt8]) throws -> [[UInt8]] {
        buffer += data
        var bodies: [[UInt8]] = []
        var start = 0
        while start < buffer.count {
            let decoded: (value: UInt64, next: Int)?
            do {
                decoded = try ProtoVarint.decode(buffer, from: start)
            } catch {
                buffer.removeAll()
                throw error
            }
            guard let prefix = decoded else {
                // An unfinished prefix longer than any legal length is corrupt, not partial.
                if buffer.count - start > 5 {
                    buffer.removeAll()
                    throw ProtoWireError.varintTooLong
                }
                break
            }
            guard prefix.value <= UInt64(maxFrameLength) else {
                buffer.removeAll()
                throw ProtoWireError.frameTooLarge(prefix.value > UInt64(Int.max) ? Int.max : Int(prefix.value))
            }
            let end = prefix.next + Int(prefix.value)
            guard end <= buffer.count else { break }
            bodies.append(Array(buffer[prefix.next..<end]))
            start = end
        }
        buffer.removeFirst(start)
        return bodies
    }

    mutating func reset() { buffer.removeAll() }
}
