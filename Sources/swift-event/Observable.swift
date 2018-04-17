import Foundation

// MARK: Observable

/// `Observable<T>` は時系列順に発生する一連のイベントの発生源を表す.
/// イベントは `T` 型の値として表される。
///
/// `subscribe(retainer:handler:)` メソッドによりイベントハンドラを登録し、将来のイベントの通知を受け取ることができる.
/// `emit(value:)` メソッドによりイベントを発生させる.

// 設計上のノート:
// `Observable<T>` は購読用API (`subscribe`, `unsubscribe`) と通知用API (`emit`, `dispose`) を分離しない.
// 分離により得られる利点 (意図しない通知用APIの使用) より欠点 (API・実装の複雑化) のほうが大きいと判断したため.
public class Observable<T> {
    /// イベント通知を購読するためのコールバック関数の型
    public typealias Handler = (T) -> Void

    /// 購読をキャンセルするための識別子
    public class Subscription {
        public weak var observable: Observable?
        public weak var retainer: AnyObject?
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

        /// `Subscription` が示す購読をキャンセルする.
        public func dispose() {
            observable?.unsubscribe(self)
        }
    }

    private var lock = NSRecursiveLock()
    private var subscriptions = [ObjectIdentifier: Subscription]()

    /// `subscribe(retainer:_:)` メソッドにより `Observable` が発行するイベントを受け取るためのにコールバック関数を登録する.
    ///
    /// - Parameters:
    ///   - retainer: 購読の生存期間を決定するオブジェクト. `Observable` は `retainer` への弱参照を保持し, `retainer` もしくは `Observable` が開放されたときに購読を解除する. `nil` のとき生存期間は `Observable` と同じ.
    ///   - queue: コールバック関数の実行される `DispatchQueue`. `nil` のとき関数はイベント発生源のスレッドで同期的に実行される.
    ///   - handler: イベント発生を受信するためのコールバック関数.
    /// - Returns: 購読をキャンセルするための `Subscription` オブジェクト. `Subscription` の `deinit` 時には何も起こらないため, 手動で生存期間の管理を行わない場合は `Subscription` を保存する必要はない.
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

    /// `unsubscribe(subscription:)` は `Subscription` で表現される購読を解除する.
    ///
    /// - Parameter subscription: 解除する購読を表す `Subscription`
    open func unsubscribe(_ subscription: Subscription) {
        lock.lock()
        subscriptions.removeValue(forKey: ObjectIdentifier(subscription))
        lock.unlock()
    }

    /// `emit(value:)` は `Observable` 上でイベントを発生させ、購読者に通知を送信する.
    ///
    /// - Parameter value: イベントを表す `T` 型の値
    open func emit(_ value: T) {
        lock.lock()
        for (id, subscription) in subscriptions {
            // retainerが開放された場合は購読解除する
            guard subscription.retainer != nil else {
                subscriptions.removeValue(forKey: id)
                continue
            }
            // handlerを呼ぶ
            if let queue = subscription.queue {
                queue.async { subscription.handler(value) }
            } else {
                subscription.handler(value)
            }
        }
        lock.unlock()
    }

    /// `dispose()` はすべての購読を解除する
    open func dispose() {
        lock.lock()
        subscriptions.removeAll()
        lock.unlock()
    }
}

// MARK: ObservableExtension

// Reactive ExtensionライクなAPIを提供する.
// (Rx系APIの使用を推奨するわけではない)
public extension Observable {
    func filter(_ isIncluded: @escaping (T) -> Bool) -> Observable<T> {
        let obs = Observable<T>()
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
            subscription.dispose()
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


// MARK: Property

/// `Property` は現在値と, 値の変更を通知するAPIを提供する
public class Property<T> {
    private let observable = Observable<T>()

    /// `Property` の現在値を取得または設定する. 値を設定した場合, 購読者に変更を通知する.
    open var value: T {
        didSet {
            observable.emit(value)
        }
    }

    /// `Property` を初期値を与えて初期化する.
    ///
    /// - Parameter value: 初期値.
    init(_ value: T) {
        self.value = value
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
    open func subscribe(retainer object: AnyObject? = nil,
                        on queue: DispatchQueue? = nil,
                        _ handler: @escaping (T) -> Void) -> Observable<T>.Subscription {
        let subscription = observable.subscribe(retainer: object, on: queue, handler)
        handler(value)
        return subscription
    }

    /// プロパティの値の変更に関する通知を受け取るコールバック関数を登録する.
    ///
    /// 登録時に現在値の通知が発生する.
    ///
    /// - Parameters:
    ///   - retainer: 購読の生存期間を決定するオブジェクト. `Observable` は `retainer` への弱参照を保持し, `retainer` もしくは `Observable` が開放されたときに購読を解除する. `nil` のとき生存期間は `Observable` と同じ.
    ///   - queue: コールバック関数の実行される `DispatchQueue`. `nil` のとき関数はイベント発生源のスレッドで同期的に実行される.
    ///   - build: `Observable` に対する処理グラフを構築するためのコールバック関数.
    /// - Returns: 購読をキャンセルするための `Subscription` オブジェクト. `Subscription` の `deinit` 時には何も起こらないため, 手動で生存期間の管理を行わない場合は `Subscription` を保存する必要はない.
    @discardableResult
    open func observe(retainer object: AnyObject? = nil,
                      on queue: DispatchQueue? = nil,
                      _ build: (Observable<T>) -> Void) -> Observable<T>.Subscription {
        let obs = Observable<T>()
        build(obs)
        let subscription = observable.subscribe(retainer: object, on: queue) { value in
            obs.emit(value)
        }
        obs.emit(value)
        return subscription
    }

    /// `unsubscribe(subscription:)` は `Subscription` で表現される購読を解除する.
    ///
    /// - Parameter subscription: 解除する購読を表す `Subscription`
    open func unsubscribe(_ subscription: Observable<T>.Subscription) {
        observable.unsubscribe(subscription)
    }

    /// `dispose()` はすべての購読を解除する
    open func dispose() {
        observable.dispose()
    }
}
