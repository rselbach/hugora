import Testing
@testable import Hugora

@Suite("HTMLEntityCodec Tests")
struct HTMLEntityCodecTests {
    @Test("Decode and encode preserves original entities")
    func decodeEncodeRoundTrip() {
        let raw = "Fish &amp; Chips"
        let decoded = HTMLEntityCodec.decode(raw)

        #expect(decoded.decoded == "Fish & Chips")
        #expect(decoded.mappings.count == 1)

        let reencoded = HTMLEntityCodec.encode(decoded.decoded, mappings: decoded.mappings)
        #expect(reencoded == raw)
    }

    @Test("Unknown entities remain untouched")
    func unknownEntityPreserved() {
        let raw = "Hello &notarealentity; there"
        let decoded = HTMLEntityCodec.decode(raw)

        #expect(decoded.decoded == raw)
        #expect(decoded.mappings.isEmpty)
    }
}
