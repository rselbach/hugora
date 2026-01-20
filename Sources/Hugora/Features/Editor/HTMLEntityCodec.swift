import Foundation

private let htmlEntityPattern = try! NSRegularExpression(pattern: "&#(\\d+);|&#x([0-9A-Fa-f]+);|&([a-zA-Z]+);")

private let namedEntities: [String: String] = [
    "quot": "\"", "amp": "&", "apos": "'", "lt": "<", "gt": ">",
    "nbsp": "\u{00A0}", "iexcl": "\u{00A1}", "cent": "\u{00A2}", "pound": "\u{00A3}", "curren": "\u{00A4}",
    "yen": "\u{00A5}", "brvbar": "\u{00A6}", "sect": "\u{00A7}", "uml": "\u{00A8}", "copy": "\u{00A9}",
    "ordf": "\u{00AA}", "laquo": "\u{00AB}", "not": "\u{00AC}", "shy": "\u{00AD}", "reg": "\u{00AE}",
    "macr": "\u{00AF}", "deg": "\u{00B0}", "plusmn": "\u{00B1}", "sup2": "\u{00B2}", "sup3": "\u{00B3}",
    "acute": "\u{00B4}", "micro": "\u{00B5}", "para": "\u{00B6}", "middot": "\u{00B7}", "cedil": "\u{00B8}",
    "sup1": "\u{00B9}", "ordm": "\u{00BA}", "raquo": "\u{00BB}", "frac14": "\u{00BC}", "frac12": "\u{00BD}",
    "frac34": "\u{00BE}", "iquest": "\u{00BF}", "times": "\u{00D7}", "divide": "\u{00F7}",
    "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "'", "rsquo": "'", "sbquo": "\u{201A}",
    "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}", "dagger": "\u{2020}", "Dagger": "\u{2021}",
    "bull": "\u{2022}", "hellip": "\u{2026}", "permil": "\u{2030}", "prime": "\u{2032}", "Prime": "\u{2033}",
    "lsaquo": "\u{2039}", "rsaquo": "\u{203A}", "oline": "\u{203E}", "frasl": "\u{2044}", "euro": "\u{20AC}",
    "trade": "\u{2122}", "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}",
    "harr": "\u{2194}", "spades": "\u{2660}", "clubs": "\u{2663}", "hearts": "\u{2665}", "diams": "\u{2666}"
]

struct HTMLEntityMapping: Equatable {
    let decodedRange: NSRange
    let encodedText: String
    let decodedText: String
}

enum HTMLEntityCodec {
    static func decode(_ string: String) -> (decoded: String, mappings: [HTMLEntityMapping]) {
        let range = NSRange(string.startIndex..., in: string)
        let matches = htmlEntityPattern.matches(in: string, range: range)

        guard !matches.isEmpty else { return (string, []) }

        var decoded = ""
        var mappings: [HTMLEntityMapping] = []
        var cursor = string.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: string) else { continue }

            decoded.append(contentsOf: string[cursor..<matchRange.lowerBound])
            let encodedText = String(string[matchRange])

            guard let replacement = replacement(for: match, in: string) else {
                decoded.append(encodedText)
                cursor = matchRange.upperBound
                continue
            }

            let decodedStart = decoded.utf16.count
            decoded.append(contentsOf: replacement)
            let decodedRange = NSRange(location: decodedStart, length: replacement.utf16.count)
            mappings.append(HTMLEntityMapping(decodedRange: decodedRange, encodedText: encodedText, decodedText: replacement))

            cursor = matchRange.upperBound
        }

        decoded.append(contentsOf: string[cursor...])
        return (decoded, mappings)
    }

    static func encode(_ decoded: String, mappings: [HTMLEntityMapping]) -> String {
        guard !mappings.isEmpty else { return decoded }

        let nsDecoded = decoded as NSString
        let sortedMappings = mappings.sorted { $0.decodedRange.location < $1.decodedRange.location }
        var result = ""
        var cursor = 0

        for mapping in sortedMappings {
            let range = mapping.decodedRange
            guard range.location >= cursor else { continue }
            guard NSMaxRange(range) <= nsDecoded.length else { continue }

            let prefixRange = NSRange(location: cursor, length: range.location - cursor)
            result.append(nsDecoded.substring(with: prefixRange))

            let currentDecoded = nsDecoded.substring(with: range)
            if currentDecoded == mapping.decodedText {
                result.append(mapping.encodedText)
            }
            if currentDecoded != mapping.decodedText {
                result.append(currentDecoded)
            }

            cursor = NSMaxRange(range)
        }

        if cursor < nsDecoded.length {
            result.append(nsDecoded.substring(from: cursor))
        }

        return result
    }

    private static func replacement(for match: NSTextCheckingResult, in string: String) -> String? {
        if let decRange = Range(match.range(at: 1), in: string),
           let codePoint = UInt32(string[decRange]),
           let scalar = Unicode.Scalar(codePoint) {
            return String(Character(scalar))
        }

        if let hexRange = Range(match.range(at: 2), in: string),
           let codePoint = UInt32(string[hexRange], radix: 16),
           let scalar = Unicode.Scalar(codePoint) {
            return String(Character(scalar))
        }

        if let nameRange = Range(match.range(at: 3), in: string) {
            return namedEntities[String(string[nameRange])]
        }

        return nil
    }
}
