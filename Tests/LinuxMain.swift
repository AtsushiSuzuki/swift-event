import XCTest

import ObservableTests

var tests = [XCTestCaseEntry]()
tests += ObservableTests.allTests()
XCTMain(tests)