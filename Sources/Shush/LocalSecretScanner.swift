import Foundation

enum LocalSecretScanner {
    private struct Detector {
        let name: String
        let regex: NSRegularExpression
        let valueGroup: Int

        init(_ name: String, _ pattern: String, valueGroup: Int = 0) {
            self.name = name
            self.regex = try! NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
            self.valueGroup = valueGroup
        }
    }

    private static let detectors: [Detector] = [
        Detector("AWS access key", #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#),
        Detector("GitHub token", #"\b(?:gh[pousr]_[A-Za-z0-9]{30,255}|github_pat_[A-Za-z0-9_]{30,255})\b"#),
        Detector("Slack token", #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#),
        Detector("Stripe secret key", #"\bsk_(?:live|test)_[A-Za-z0-9]{16,}\b"#),
        Detector("Google API key", #"\bAIza[A-Za-z0-9_-]{30,}\b"#),
        Detector("OpenAI-style key", #"\bsk-[A-Za-z0-9_-]{20,}\b"#),
        Detector("Private key", #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#)
    ]

    private static let allowedExtensions: Set<String> = [
        "", "env", "json", "yaml", "yml", "tfvars", "txt", "md", "pem", "key",
        "conf", "config", "ini", "properties", "sh", "zsh", "bash", "py", "rb",
        "js", "jsx", "ts", "tsx", "swift", "go", "rs", "java", "xml"
    ]

    private static let skippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", "target", "Pods", "DerivedData"
    ]

    static func scan(urls: [URL]) -> [SecretFinding] {
        var findings: [SecretFinding] = []
        var seen = Set<String>()

        for root in urls {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if skippedDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }

                guard let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                ),
                values.isRegularFile == true,
                (values.fileSize ?? 0) <= 2_000_000,
                allowedExtensions.contains(fileURL.pathExtension.lowercased()),
                let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                let text = String(data: data, encoding: .utf8) else {
                    continue
                }

                let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
                for detector in detectors {
                    for match in detector.regex.matches(in: text, range: fullRange) {
                        let range = match.range(at: detector.valueGroup)
                        guard range.location != NSNotFound,
                              let swiftRange = Range(range, in: text) else { continue }
                        let value = String(text[swiftRange])
                        let fingerprint = "\(fileURL.path)|\(value)"
                        guard seen.insert(fingerprint).inserted else { continue }
                        let prefix = text[..<swiftRange.lowerBound]
                        let line = prefix.reduce(into: 1) { count, character in
                            if character == "\n" { count += 1 }
                        }
                        findings.append(
                            SecretFinding(
                                kind: detector.name,
                                value: value,
                                fileURL: fileURL,
                                line: line
                            )
                        )
                        if findings.count >= 500 { return findings }
                    }
                }
            }
        }
        return findings
    }
}
