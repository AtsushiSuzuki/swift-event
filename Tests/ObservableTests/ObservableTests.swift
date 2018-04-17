import XCTest
@testable import Observable

class ObservableTests: XCTestCase {
    func testObservable() {
        var sum = 0

        let obs = Observable<Int>()
        obs.subscribe { sum += $0 }

        obs.emit(1)
        obs.emit(2)

        XCTAssertEqual(3, sum)
    }

    func testObservableShouldDeinitHandler() {
        var deinited = false

        do {
            let `guard` = DeinitGuard { deinited = true }
            let obs = Observable<Void>()
            obs.subscribe { `guard`.noop() }
        }

        XCTAssertEqual(true, deinited)
    }

    func testObservableShouldUnsubscribeWithRetainer() {
        var called = 0

        let obs = Observable<Void>()
        do {
            let value = DeinitGuard { print("deinit guard") }
            obs.subscribe(retainer: value) { _ in called += 1 }
            obs.emit(())
        }
        obs.emit(())

        XCTAssertEqual(1, called)
    }

    func testProperty() {
        var sum = 0

        let prop = Property<Int>(1)
        XCTAssertEqual(1, prop.value)

        prop.subscribe { sum += $0 }

        prop.value = 2
        prop.value = 3

        XCTAssertEqual(3, prop.value)
        XCTAssertEqual(6, sum)
    }

    static var allTests = [
        ("testObservable", testObservable),
        ("testObservableShouldDeinitHandler", testObservableShouldDeinitHandler),
        ("testObservableShouldUnsubscribeWithRetainer", testObservableShouldUnsubscribeWithRetainer),
        ("testProperty", testProperty),
    ]
}
