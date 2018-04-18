import Foundation

/// Represents an source of series of event, which will occur in future.
/// Event is described as a value of type `T`.
///
/// Register handelr for event notifications by `subscribe(retainer:queue:handler:)`.
/// Notify subscribers with an event by `emit(value:)`.
public class Observable<T> {
    /// Event handler type.
    public typealias Handler = (T) -> Void

    /// Represents a registered event handler for `Observable`.
    ///
    /// MEMO: Deallocating `Subscription` does not affect on subscribed handler.
    public class Subscription {
        public private(set) weak var observable: Observable?
        public private(set) weak var retainer: AnyObject?
        public let queue: DispatchQueue?
        public let handler: Handler

        public init(observable: Observable,
                    retainer: AnyObject,
                    queue: DispatchQueue?,
                    handler: @escaping Handler) {
            self.observable = observable
            self.retainer = retainer
            self.queue = queue
            self.handler = handler
        }

        /// Cancels event subscription.
        public func cancel() {
            observable?.unsubscribe(self)
        }
    }

    private var lock = NSRecursiveLock()
    private var subscriptions = [ObjectIdentifier: Subscription]()

    /// Subscribe for future event notification with callback.
    ///
    /// - Parameters:
    ///   - retainer: This restricts subscription lifetyme by retainer's lifetime. when retainer is deallocated, subscription is cancelled.
    ///   - queue: `DispatchQueue` which `handler` is invoked on. if `nil`, `handler` is called synchronously.
    ///   - handler: Event handler callback function.
    /// - Returns: `Subscription`, which can be used to cancel subscription.
    @discardableResult
    open func subscribe(retainer: AnyObject? = nil,
                        on queue: DispatchQueue? = nil,
                        _ handler: @escaping Handler) -> Subscription {
        let subscription = Subscription(observable: self,
                                        retainer: retainer ?? self,
                                        queue: queue,
                                        handler: handler)

        lock.lock()
        subscriptions.updateValue(subscription, forKey: ObjectIdentifier(subscription))
        lock.unlock()

        return subscription
    }

    /// Cancels subscription.
    ///
    /// - Parameter subscription: `Subscription` to cancel.
    open func unsubscribe(_ subscription: Subscription) {
        lock.lock()
        subscriptions.removeValue(forKey: ObjectIdentifier(subscription))
        lock.unlock()
    }


    /// Composes observable method chain in closure, in order to prevent receiving events halfway.
    ///
    /// - Parameters:
    ///   - retainer: This restricts subscription lifetyme by retainer's lifetime. when retainer is deallocated, subscription is cancelled.
    ///   - queue: `DispatchQueue` which `handler` is invoked on. if `nil`, `handler` is called synchronously.
    ///   - composer: Closure to build observable method chain from `self`.
    /// - Returns: `composer` return value and `Subscription`.
    open func compose<Result>(retainer: AnyObject? = nil,
                              on queue: DispatchQueue? = nil,
                              _ composer: @escaping (Observable) -> Result) -> (Result, Subscription) {
        let obs = Observable()
        let result = composer(obs)
        let subscription = subscribe(retainer: retainer,
                                     on: queue) { value in
            obs.emit(value)
        }
        return (result, subscription)
    }

    /// Notifies subscribers an event.
    ///
    /// - Parameter value: Event value as type `T`
    open func emit(_ value: T) {
        lock.lock()
        for (id, subscription) in subscriptions {
            // cancel subscription if retainer is deallocated
            guard subscription.retainer != nil else {
                subscriptions.removeValue(forKey: id)
                continue
            }
            // call handler
            if let queue = subscription.queue {
                queue.async { subscription.handler(value) }
            } else {
                subscription.handler(value)
            }
        }
        lock.unlock()
    }

    /// Cancels all subscription.
    ///
    /// MEMO: There is no need to explicitly dispose observable.
    open func dispose() {
        lock.lock()
        subscriptions.removeAll()
        lock.unlock()
    }
}

/// `ObservableValue` は現在値と, 値の変更を通知するAPIを提供する
public class ObservableValue<T> : Observable<T> {
    /// `Property` の現在値を取得または設定する. 値を設定した場合, 購読者に変更を通知する.
    open var value: T {
        didSet {
            emit(value)
        }
    }

    /// `Property` を初期値を与えて初期化する.
    ///
    /// - Parameter value: 初期値.
    public init(_ initialValue: T) {
        self.value = initialValue
    }

    /// プロパティの値の変更に関する通知を受け取るコールバック関数を登録する.
    ///
    /// 登録時に現在値の通知が発生する.
    ///
    /// - Parameters:
    ///   - retainer: 購読の生存期間を決定するオブジェクト. `Observable` は `retainer` への弱参照を保持し, `retainer` もしくは `Observable` が開放されたときに購読を解除する. `nil` のとき生存期間は `Observable` と同じ.
    ///   - queue: コールバック関数の実行される `DispatchQueue`. `nil` のとき関数はイベント発生源のスレッドで同期的に実行される.
    ///   - handler: イベント発生を受信するためのコールバック関数.
    /// - Returns: 購読をキャンセルするための `Subscription` オブジェクト. `Subscription` の `deinit` 時には何も起こらないため, 手動で生存期間の管理を行わない場合は `Subscription` を保存する必要はない.
    @discardableResult
    open override func subscribe(retainer object: AnyObject? = nil,
                                 on queue: DispatchQueue? = nil,
                                 _ handler: @escaping (T) -> Void) -> Subscription {
        let subscription = super.subscribe(retainer: object, on: queue, handler)
        handler(value)
        return subscription
    }
}

// Reactive ExtensionライクなAPIを提供する.
// (Rx系APIの使用を推奨するわけではない)
public extension Observable {
    func filter(_ isIncluded: @escaping (T) -> Bool) -> Observable {
        let obs = Observable()
        subscribe { value in
            if isIncluded(value) {
                obs.emit(value)
            }
        }
        return obs
    }

    func map<U>(_ transform: @escaping (T) -> U) -> Observable<U> {
        let obs = Observable<U>()
        subscribe { value in
            obs.emit(transform(value))
        }
        return obs
    }

    func compactMap<U>(_ transform: @escaping (T) -> U?) -> Observable<U> {
        let obs = Observable<U>()
        subscribe { value in
            if let transformed = transform(value) {
                obs.emit(transformed)
            }
        }
        return obs
    }

    func reduce<U>(initialValue: U,
                   _ reducer: @escaping (U, T) -> U) -> Observable<U> {
        let obs = Observable<U>()
        var acc = initialValue
        subscribe { value in
            acc = reducer(acc, value)
            obs.emit(acc)
        }
        return obs
    }

    func forEach(_ handler: @escaping (T) -> Void) -> Self {
        subscribe(handler)
        return self
    }

    func async(on queue: DispatchQueue) -> Observable {
        let obs = Observable()
        subscribe { value in
            queue.async {
                obs.emit(value)
            }
        }
        return obs
    }

    func retain(with object: AnyObject?) -> Observable {
        let obs = Observable()
        subscribe(retainer: object) { value in
            obs.emit(value)
        }
        return obs
    }

    func finally(_ handler: @escaping () -> Void) -> Self {
        let `guard` = DeinitGuard(handler)
        subscribe { _ in
            `guard`.noop()
        }
        return self
    }

    func once() -> Observable {
        let obs = Observable()

        let group = DispatchGroup()
        group.enter()

        var subscription: Subscription!
        subscription = subscribe { value in
            obs.emit(value)
            group.wait()
            subscription.cancel()
        }

        group.leave()

        return obs
    }
}

internal class DeinitGuard {
    let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    deinit {
        closure()
    }

    func noop() {
    }
}
