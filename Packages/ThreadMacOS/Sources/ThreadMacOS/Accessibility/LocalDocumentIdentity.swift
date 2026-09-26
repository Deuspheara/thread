import Foundation
import ThreadDomain

/// Accepts only local document URL metadata without reading document contents.
struct LocalDocumentIdentity {
    func file(_ raw: String?) -> FileIdentity? {
        guard let raw, raw.utf8.count <= 8192, let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "file", components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.host == nil || components.host == "" || components.host == "localhost",
              let decoded = components.percentEncodedPath.removingPercentEncoding, !decoded.utf8.contains(0),
              let url = components.url, url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0) else { return nil }
        return FileIdentity(path: url.standardizedFileURL.path)
    }
}
