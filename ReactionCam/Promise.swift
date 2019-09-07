import Foundation

fileprivate let promiseQueue = DispatchQueue(label: "Promise", qos: .userInitiated, attributes: .concurrent)

open class Promise<T> {
    class func all<S : Sequence>(_ promises: S) -> Promise<[T]> where S.Iterator.Element == Promise {
        let promise = Promise<[T]>()
        let group = DispatchGroup()
        // Keep a list of the provided promises in the original order.
        let pending = promises.map { (p: Promise) -> Promise in
            group.enter()
            p.then({ _ in group.leave() }, { promise.reject($0); group.leave() })
            return p
        }
        // Run this callback when all promises have settled.
        group.notify(queue: promiseQueue) {
            guard case .pending = promise.state else {
                // We know that the joined promise has been rejected.
                return
            }
            // At this point we know that all sub-promises succeeded.
            // Fulfill the joined promise with resolved values in the
            // same order as the passed in promises.
            promise.resolve(pending.map {
                guard case let .fulfilled(value) = $0.state else {
                    preconditionFailure("this code should only run on success")
                }
                return value
            })
        }
        return promise
    }

    // Returns a tuple with the resolve/reject functions exposed. Only use this if
    // absolutely necessary; otherwise, use the constructor form as it's safer.
    class func exposed() -> (Promise<T>, (T) -> (), (Error) -> ()) {
        let promise = Promise()
        return (promise, promise.resolve, promise.reject)
    }

    class func reject(_ error: Error) -> Promise<T> {
        return Promise(state: .rejected(error: error))
    }

    class func resolve(_ value: T) -> Promise<T> {
        return Promise(state: .fulfilled(value: value))
    }

    convenience init(executor: (_ resolve: @escaping (T) -> (), _ reject: @escaping (Error) -> ()) throws -> ()) {
        self.init()
        do {
            try executor(self.resolve, self.reject)
        } catch let e {
            self.reject(e)
        }
    }

    @discardableResult
    func `catch`(_ onRejected: @escaping (Error) throws -> T) -> Promise<T> {
        return self.then({ $0 }, onRejected)
    }

    @discardableResult
    func then<U>(_ onFulfilled: @escaping (T) throws -> U) -> Promise<U> {
        return self.then(onFulfilled, { throw $0 })
    }

    @discardableResult
    func then<U>(_ onFulfilled: @escaping (T) throws -> U, _ onRejected: @escaping (Error) throws -> U) -> Promise<U> {
        pthread_mutex_lock(&self.mutex)
        defer { pthread_mutex_unlock(&self.mutex) }
        let promise = Promise<U>()
        let resolveReaction = { (value: T) in
            do {
                promise.resolve(try onFulfilled(value))
            } catch let e {
                promise.reject(e)
            }
        }
        let rejectReaction = { (error: Error) in
            do {
                promise.resolve(try onRejected(error))
            } catch let e {
                promise.reject(e)
            }
        }
        switch self.state {
        case .pending:
            self.fulfillReactions.append(resolveReaction)
            self.rejectReactions.append(rejectReaction)
        case let .fulfilled(value):
            promiseQueue.async { resolveReaction(value) }
        case let .rejected(error):
            promiseQueue.async { rejectReaction(error) }
        }
        return promise
    }

    private var fulfillReactions = [(T) -> ()]()
    private var mutex = pthread_mutex_t()
    private var rejectReactions = [(Error) -> ()]()
    private var state: PromiseState<T>

    private init(state: PromiseState<T> = .pending) {
        pthread_mutex_init(&self.mutex, nil)
        self.state = state
    }

    deinit {
        pthread_mutex_destroy(&self.mutex)
    }

    private func reject(_ error: Error) {
        self.set(state: .rejected(error: error))
    }

    private func resolve(_ value: T) {
        self.set(state: .fulfilled(value: value))
    }

    private func set(state: PromiseState<T>) {
        pthread_mutex_lock(&self.mutex)
        defer { pthread_mutex_unlock(&self.mutex) }
        guard case .pending = self.state else {
            return
        }
        self.state = state
        switch state {
        case let .fulfilled(value):
            for r in self.fulfillReactions { promiseQueue.async { r(value) } }
        case let .rejected(error):
            for r in self.rejectReactions { promiseQueue.async { r(error) } }
        default:
            preconditionFailure("unexpected state")
        }
        self.fulfillReactions.removeAll()
        self.rejectReactions.removeAll()
    }
}

enum PromiseState<T> {
    case pending, fulfilled(value: T), rejected(error: Error)
}
