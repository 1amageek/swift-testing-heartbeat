/// Helper to generate stable test identifiers from call-site information.
public enum TestID {

    /// Return the explicit ID if provided, otherwise build one from the call site.
    public static func make(
        _ explicit: String? = nil,
        function: String = #function,
        fileID: String = #fileID,
        line: UInt = #line
    ) -> String {
        if let explicit { return explicit }
        return "\(fileID)::\(function)::L\(line)"
    }
}
