// This file is added by Mnemo to satisfy the vendored upstream test target path.
import XCTest
@testable import FSRS
final class MnemoVendorSmoke: XCTestCase {
    func testVersionSixDefaults() { XCTAssertEqual(FSRSDefaults.defaultWv6.count, 21) }
}
