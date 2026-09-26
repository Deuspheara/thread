import Foundation
import ThreadDomain

/// Encodes typed metadata and stable natural identity keys for the relational graph.
enum GraphRecordCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
    static func key(_ id: ResourceID) throws -> String { String(decoding: try encode(id), as: UTF8.self) }

    static func validate(_ state: ThreadGraphState) throws {
        do { try ThreadGraphValidation.validate(state) }
        catch { throw HistoryStorageError.invalidState }
    }
}
