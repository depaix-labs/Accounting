import Dispatch
import Foundation

private enum LSPProtocolFixtureError: Error {
    case missing_executable
    case malformed_frame
    case missing_response
    case missing_data
    case process_failed(Int32)
    case timed_out
}

enum ECLSPProtocolFixture {
    static func fullSemanticTokens() throws -> [Int] {
        let executable = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/eclsp")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LSPProtocolFixtureError.missing_executable
        }

        let uri = "file:///tmp/agentic-ec-semantic-tokens.ec"
        let source = "\"\u{1F600}\" café // outside\r\n42"
        let messages: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]],
            ["jsonrpc": "2.0", "method": "textDocument/didOpen", "params": [
                "textDocument": ["uri": uri, "languageId": "ec", "version": 1, "text": source]
            ]],
            ["jsonrpc": "2.0", "id": 2, "method": "textDocument/semanticTokens/full", "params": [
                "textDocument": ["uri": uri]
            ]],
            ["jsonrpc": "2.0", "id": 3, "method": "shutdown", "params": [:]]
        ]
        var input = Data()
        for message in messages {
            let body = try JSONSerialization.data(withJSONObject: message)
            input.append(Data("Content-Length: \(body.count)\r\n\r\n".utf8))
            input.append(body)
        }

        let process = Process()
        process.executableURL = executable
        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        standardInput.fileHandleForWriting.write(input)
        try standardInput.fileHandleForWriting.close()
        guard completion.wait(timeout: .now() + .seconds(10)) == .success else {
            process.terminate()
            process.waitUntilExit()
            throw LSPProtocolFixtureError.timed_out
        }
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw LSPProtocolFixtureError.process_failed(process.terminationStatus)
        }

        let separator = Data("\r\n\r\n".utf8)
        var offset = 0
        while offset < output.count {
            guard let headerRange = output.range(of: separator, in: offset..<output.count) else {
                throw LSPProtocolFixtureError.malformed_frame
            }
            let header = String(decoding: output[offset..<headerRange.lowerBound], as: UTF8.self)
            guard let lengthLine = header.components(separatedBy: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("content-length:") }),
                  let length = Int(lengthLine.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)) else {
                throw LSPProtocolFixtureError.malformed_frame
            }
            let start = headerRange.upperBound
            let end = start + length
            guard end <= output.count,
                  let json = try JSONSerialization.jsonObject(with: output.subdata(in: start..<end))
                    as? [String: Any] else {
                throw LSPProtocolFixtureError.malformed_frame
            }
            if json["id"] as? Int == 2 {
                guard let result = json["result"] as? [String: Any],
                      let data = result["data"] as? [Int] else {
                    throw LSPProtocolFixtureError.missing_data
                }
                return data
            }
            offset = end
        }
        throw LSPProtocolFixtureError.missing_response
    }
}
