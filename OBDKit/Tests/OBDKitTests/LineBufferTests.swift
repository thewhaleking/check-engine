import Testing
@testable import OBDKit

@Suite struct LineBufferTests {
    @Test func splitsOnCRAndPrompt() {
        var b = LineBuffer()
        b.append(Array("41 0C 1A F8\r\n\r\n>".utf8))
        #expect(b.nextLine() == "41 0C 1A F8")
        #expect(b.nextLine() == "")
        #expect(b.nextLine() == ">")
        #expect(b.nextLine() == nil)
    }
    @Test func waitsForTerminator() {
        var b = LineBuffer()
        b.append(Array("41 0C".utf8))
        #expect(b.nextLine() == nil)
        b.append(Array(" 1A F8\r".utf8))
        #expect(b.nextLine() == "41 0C 1A F8")
    }
}
