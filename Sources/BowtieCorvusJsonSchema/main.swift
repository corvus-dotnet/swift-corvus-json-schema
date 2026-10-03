// A Bowtie (https://github.com/bowtie-json-schema/bowtie) harness for the CorvusJsonSchema Swift package.
//
// It speaks IHOP (one JSON request per line on standard input, one response per line on standard output):
// - `start` reports the implementation and its dialects;
// - `dialect` sets the dialect for schemas without `$schema`;
// - `run` compiles the case's schema with the case's `registry` as the document resolver and validates each instance
//   (for `annotations` output, through a verbose collector, reporting each annotation with its instance location and
//   `#…` keyword location);
// - `stop` exits.
//
// Requests are read with a small JSON scanner that keeps each value's text as Bowtie wrote it, so schemas and
// instances reach the library unchanged (numbers included).
import CorvusJsonSchema
import Foundation

let dialects: [(String, Dialect)] = [
    ("https://json-schema.org/draft/2020-12/schema", .draft202012),
    ("https://json-schema.org/draft/2019-09/schema", .draft201909),
    ("http://json-schema.org/draft-07/schema#", .draft7),
    ("http://json-schema.org/draft-06/schema#", .draft6),
    ("http://json-schema.org/draft-04/schema#", .draft4),
]

/// A JSON value's text, scanned in place.
struct JSONText {
    let bytes: [UInt8]

    init(_ text: String) { bytes = Array(text.utf8) }
    init(_ bytes: ArraySlice<UInt8>) { self.bytes = Array(bytes) }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// The members of an object (names unescaped), or the elements of an array (names nil), as their text.
    func items() -> [(String?, JSONText)] {
        var i = 0
        var out: [(String?, JSONText)] = []
        skipSpace(&i)
        guard i < bytes.count, bytes[i] == UInt8(ascii: "{") || bytes[i] == UInt8(ascii: "[") else { return out }
        let object = bytes[i] == UInt8(ascii: "{")
        let close = object ? UInt8(ascii: "}") : UInt8(ascii: "]")
        i += 1
        skipSpace(&i)
        if i < bytes.count, bytes[i] == close { return out }
        while i < bytes.count {
            var name: String?
            if object {
                let start = i
                skipValue(&i)
                name = JSONText(bytes[start..<i]).string
                skipSpace(&i)
                i += 1  // ':'
            }
            skipSpace(&i)
            let start = i
            skipValue(&i)
            out.append((name, JSONText(bytes[start..<i])))
            skipSpace(&i)
            if i < bytes.count, bytes[i] == UInt8(ascii: ",") {
                i += 1
                skipSpace(&i)
            } else {
                break
            }
        }
        return out
    }

    /// The member of an object with this name.
    subscript(name: String) -> JSONText? {
        items().first { $0.0 == name }?.1
    }

    /// The text of a string value (unescaped), or nil for another value.
    var string: String? {
        guard bytes.first == UInt8(ascii: "\"") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(bytes), options: .fragmentsAllowed)) as? String
    }

    private func skipSpace(_ i: inout Int) {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    private func skipValue(_ i: inout Int) {
        skipSpace(&i)
        guard i < bytes.count else { return }
        switch bytes[i] {
        case UInt8(ascii: "\""):
            i += 1
            while i < bytes.count, bytes[i] != UInt8(ascii: "\"") { i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1 }
            i += 1
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            let close = bytes[i] == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
            let object = close == UInt8(ascii: "}")
            i += 1
            skipSpace(&i)
            if i < bytes.count, bytes[i] == close {
                i += 1
                return
            }
            while i < bytes.count {
                if object {
                    skipValue(&i)
                    skipSpace(&i)
                    i += 1  // ':'
                }
                skipValue(&i)
                skipSpace(&i)
                guard i < bytes.count else { return }
                let c = bytes[i]
                i += 1
                if c == close { return }
                skipSpace(&i)
            }
        default:
            while i < bytes.count, ![0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }
    }
}

/// A JSON string literal for text.
func quote(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

func errored(_ error: Error) -> String {
    "\"errored\":true,\"context\":{\"message\":\(quote(String(describing: error)))}"
}

func stripFragment(_ uri: String) -> String {
    String(uri.prefix { $0 != "#" })
}

/// Percent-encodes text as a URI fragment does (upper-case hex, UTF-8), keeping the characters a fragment allows.
func percentEncode(_ text: String) -> String {
    let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?".utf8)
    return text.utf8.map { safe.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()
}

/// The annotations a verbose collector grouped (instance location, then keyword as a JSON-pointer token, then schema
/// location as a `#…` fragment; the same in every Corvus implementation) as Bowtie lists them: each with its keyword
/// unescaped, and its keyword location the schema location's fragment followed by `/` and the keyword token,
/// percent-encoded as the fragment is.
func annotations(_ grouped: JSONText) -> String {
    var found: [String] = []
    for (instanceLocation, keywords) in grouped.items() {
        for (token, locations) in keywords.items() {
            let token = token ?? ""
            let keyword = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            for (schemaLocation, value) in locations.items() {
                found.append(
                    "{\"keyword\":\(quote(keyword)),\"instanceLocation\":\(quote(instanceLocation ?? "")),"
                        + "\"keywordLocation\":\(quote((schemaLocation ?? "") + "/" + percentEncode(token))),"
                        + "\"annotation\":\(value.text)}")
            }
        }
    }
    return "[" + found.joined(separator: ",") + "]"
}

func run(_ request: JSONText, dialect: Dialect) -> String {
    let seq = request["seq"]?.text ?? "null"
    guard let testCase = request["case"], let schema = testCase["schema"] else {
        return "{\"seq\":\(seq),\"errored\":true,\"context\":{\"message\":\"the case has no schema\"}}"
    }
    var registry: [String: String] = [:]
    for (uri, document) in testCase["registry"]?.items() ?? [] {
        registry[stripFragment(uri ?? "")] = document.text
    }
    let byURI = registry
    let validator: Validator
    do {
        validator = try Validator(
            schema: schema.text,
            options: Options(defaultDialect: dialect, resolver: { byURI[stripFragment($0)] }))
    } catch {
        return "{\"seq\":\(seq),\(errored(error))}"
    }
    let wantsAnnotations = request["output"]?.string == "annotations"
    let results = (testCase["tests"]?.items() ?? []).map { (_, test) -> String in
        guard let instance = test["instance"] else { return "{\"errored\":true,\"context\":{\"message\":\"no instance\"}}" }
        do {  // an error for one instance does not stop the others
            if wantsAnnotations {
                let collector = Collector(level: .verbose)
                let valid = try validator.evaluate(json: instance.text, collector: collector)
                return "{\"valid\":\(valid),\"annotations\":\(annotations(JSONText(try collector.annotationsJSON())))}"
            }
            return "{\"valid\":\(try validator.isValid(json: instance.text))}"
        } catch {
            return "{\(errored(error))}"
        }
    }
    return "{\"seq\":\(seq),\"results\":[\(results.joined(separator: ","))]}"
}

func start() -> String {
    #if os(Linux)
    let os = "Linux"
    #else
    let os = "macOS"
    #endif
    let uris = dialects.map { quote($0.0) }.joined(separator: ",")
    return "{\"version\":1,\"implementation\":{\"language\":\"swift\",\"name\":\"corvus-json-schema\","
        + "\"version\":\(quote(packageVersion)),"
        + "\"homepage\":\"https://github.com/corvus-dotnet/Corvus.JsonSchema\","
        + "\"documentation\":\"https://github.com/corvus-dotnet/corvus-json-schema-swift\","
        + "\"issues\":\"https://github.com/corvus-dotnet/Corvus.JsonSchema/issues\","
        + "\"source\":\"https://github.com/corvus-dotnet/corvus-json-schema-swift\","
        + "\"dialects\":[\(uris)],\"os\":\(quote(os)),"
        + "\"os_version\":\(quote(ProcessInfo.processInfo.operatingSystemVersionString)),"
        + "\"language_version\":\(quote(swiftVersion))}}"
}

var started = false
var dialect = Dialect.draft202012
while let line = readLine() {
    if line.allSatisfy(\.isWhitespace) { continue }
    let request = JSONText(line)
    let response: String
    switch request["cmd"]?.string {
    case "start":
        guard request["version"]?.text == "1" else { fatalError("Unsupported IHOP version") }
        started = true
        response = start()
    case "dialect":
        guard started else { fatalError("Not started") }
        if let match = dialects.first(where: { $0.0 == request["dialect"]?.string }) {
            dialect = match.1
            response = "{\"ok\":true}"
        } else {
            response = "{\"ok\":false}"
        }
    case "run":
        guard started else { fatalError("Not started") }
        response = run(request, dialect: dialect)
    case "stop":
        guard started else { fatalError("Not started") }
        exit(0)
    default:
        fatalError("Unknown command")
    }
    print(response)
    fflush(stdout)
}
