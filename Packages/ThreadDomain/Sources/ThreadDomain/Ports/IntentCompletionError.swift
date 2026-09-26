/// An interrupted command may have taken effect before its acknowledgement was lost.
public enum IntentCompletionError: Error, Sendable { case unknown }
