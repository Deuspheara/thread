import Foundation
import Security

/// Derives a validated peer requirement from the installed signed bundle, never caller metadata.
public enum AgentSigningRequirement {
    public static func string(for bundle: URL) throws -> String {
        let flags = SecCSFlags(rawValue: 0)
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, flags, &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw AgentProbeError.signatureUnavailable
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, flags, &requirement) == errSecSuccess, let requirement else {
            throw AgentProbeError.signatureUnavailable
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, flags, &text) == errSecSuccess, let text else {
            throw AgentProbeError.signatureUnavailable
        }
        return text as String
    }
}
