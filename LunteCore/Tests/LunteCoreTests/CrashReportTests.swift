import XCTest
@testable import LunteCore

/// A crash report cut down to what's sent: the version, the exception and the crashed thread's functions, never its
/// message, which is free text.
final class CrashReportTests: XCTestCase {
    func testSummary() throws {
        let ips = """
        {"app_name":"Lunte","app_version":"0.4.1","build_version":"202610271557","os_version":"macOS 26.5.1 (25F80)"}
        {"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"asi":{"libswiftCore.dylib":["Fatal error: 'try!' failed on 'my secret prompt'"]},\
        "faultingThread":1,"usedImages":[{"name":"SwiftUICore"},{"name":"Lunte"}],"threads":[{"frames":[{"imageIndex":1,"symbol":"idle"}]},\
        {"frames":[{"imageIndex":0,"symbol":"MatchedGeometryScope.sourceViewIndex(frameIndex:)"},{"imageIndex":1,"symbol":"closure in /Users/sam/Lunte"},{"imageIndex":9}]}]}
        """
        let text = try XCTUnwrap(CrashReport.summary(ips, home: "/Users/sam"))
        XCTAssertEqual(text, """
        Lunte 0.4.1 (202610271557), macOS 26.5.1 (25F80)
        EXC_BREAKPOINT SIGTRAP
        crashed:
          SwiftUICore  MatchedGeometryScope.sourceViewIndex(frameIndex:)
          Lunte  closure in ~/Lunte
          ?  ?
        """)
        XCTAssertNil(CrashReport.summary("not a report"))
    }
}
