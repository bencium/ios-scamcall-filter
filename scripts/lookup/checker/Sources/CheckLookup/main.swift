// Usage: CheckLookup <server-url> <token> <usecase> <number> [<number> ...]
//   e.g. CheckLookup https://scamblocker-lookup.fly.dev "$LOOKUP_TOKEN" \
//          uk.co.bencium.ScamBlocker.Lookup.block +448431234567 +447700900123
//
// Runs Apple's own test client (PIRServiceTesting) through a small local forwarder,
// because that client only talks to Hummingbird test connections. Every step iOS
// takes happens for real: config fetch, Privacy Pass tokens, key upload, encrypted query.
import Foundation
import HTTPTypes
import HomomorphicEncryption
import Hummingbird
import HummingbirdTesting
import NIOCore
import PIRServiceTesting
import PrivateInformationRetrieval

let arguments = CommandLine.arguments
guard arguments.count >= 5, let server = URL(string: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: CheckLookup <server-url> <token> <usecase> <number> [<number> ...]\n".utf8))
    exit(2)
}
let token = arguments[2]
let usecase = arguments[3]
let numbers = Array(arguments[4...])

let router = Router()
for method in [HTTPRequest.Method.get, .post] {
    router.on("**", method: method) { request, _ in try await forward(request, to: server) }
}
let app = Application(router: router)
try await app.test(.live) { connection in
    var client = PIRClient<MulPirClient<Bfv<UInt32>>>(connection: connection, userToken: token)
    // The first lookup also fetches the config and tokens and uploads a key, as iOS does once.
    let setup = try await timed { _ = try await client.request(keywords: [Array(numbers[0].utf8)], usecase: usecase) }
    // Restart test: pause here (keys and tokens already set up) until the file exists, so the
    // server can be restarted underneath; the lookups below must still work without new setup.
    if let waitFile = ProcessInfo.processInfo.environment["CHECK_WAIT_FILE"] {
        print("SETUP_DONE")
        fflush(stdout)
        while !FileManager.default.fileExists(atPath: waitFile) { try await Task.sleep(for: .milliseconds(200)) }
    }
    // iOS asks about one number per incoming call, so time a single lookup on its own.
    let single = try await timed { _ = try await client.request(keywords: [Array(numbers[numbers.count - 1].utf8)], usecase: usecase) }
    var values: [[UInt8]?] = []
    // Ten numbers per request: one big request can keep a small server busy past its health check.
    let batch = try await timed {
        for start in stride(from: 0, to: numbers.count, by: 10) {
            let chunk = numbers[start..<min(start + 10, numbers.count)]
            values += try await client.request(keywords: chunk.map { Array($0.utf8) }, usecase: usecase)
        }
    }
    for (number, value) in zip(numbers, values) {
        print("\(number)\t\(describe(value))")
    }
    print(String(format: "first lookup incl. one-time setup: %.0f ms", setup * 1000))
    print(String(format: "single lookup: %.0f ms", single * 1000))
    print(String(format: "batch of %d: %.0f ms per number", numbers.count, batch * 1000 / Double(numbers.count)))
}

@Sendable func timed(_ work: () async throws -> Void) async rethrows -> TimeInterval {
    let start = Date()
    try await work()
    return Date().timeIntervalSince(start)
}

@Sendable func describe(_ value: [UInt8]?) -> String {
    switch value {
    case nil: "not in database (not blocked)"
    case [1]?: "BLOCK"
    case [0]?: "listed, do not block"
    case let bytes?: "value of \(bytes.count) bytes"
    }
}

@Sendable func forward(_ request: Request, to server: URL) async throws -> Response {
    var outgoing = URLRequest(url: URL(string: server.absoluteString + request.uri.description)!)
    outgoing.httpMethod = request.method.rawValue
    for field in request.headers where !["host", "content-length"].contains(field.name.canonicalName) {
        outgoing.addValue(field.value, forHTTPHeaderField: field.name.canonicalName)
    }
    let body = try await request.body.collect(upTo: 64 << 20)
    if body.readableBytes > 0 { outgoing.httpBody = Data(body.readableBytesView) }
    let (data, response) = try await URLSession.shared.data(for: outgoing)
    let http = response as! HTTPURLResponse
    var headers = HTTPFields()
    if let type = http.value(forHTTPHeaderField: "Content-Type") { headers[.contentType] = type }
    return Response(status: .init(code: http.statusCode), headers: headers,
                    body: .init(byteBuffer: ByteBuffer(bytes: data)))
}
