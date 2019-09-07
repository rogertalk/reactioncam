import Foundation

class Event<T> {
    fileprivate var invokers = [Invoker<T>]()

    /// Adds an event listener, notifying the provided method when the event is emitted.
    func addListener<Listener: AnyObject>(_ listener: Listener, method: @escaping (Listener) -> (T) -> ()) {
        self.invokers.append(Invoker(listener: listener, method: method))
    }

    /// Removes the object from the list of objects that get notified of the event.
    func removeListener(_ listener: AnyObject) {
        self.invokers = self.invokers.filter {
            guard let current = $0.listener else {
                return false
            }
            return current !== listener
        }
    }

    /// Publishes the specified data to all listeners via the main queue.
    func emit(_ data: T) {
        let queue = DispatchQueue.main
        for invoker in self.invokers {
            queue.async {
                // TODO: If this returns false, we should remove the invoker from the list.
                _ = invoker.closure(data)
            }
        }
    }
}

private class Invoker<T> {
    let closure: (T) -> Bool
    weak var listener: AnyObject?

    init(listener: AnyObject, closure: @escaping (T) -> Bool) {
        self.listener = listener
        self.closure = closure
    }

    convenience init<Listener: AnyObject>(listener: Listener, method: @escaping (Listener) -> (T) -> ()) {
        let closure: (T) -> Bool = {
            [weak listener] (data: T) in
            guard let listener = listener else {
                return false
            }
            method(listener)(data)
            return true
        }
        self.init(listener: listener, closure: closure)
    }
}

// MARK: - Specific implementations for events with zero arguments.

extension Event where T == Void {
    func addListener<Listener: AnyObject>(_ listener: Listener, method: @escaping (Listener) -> () -> ()) {
        self.invokers.append(Invoker(listener: listener, method: method))
    }

    func emit() {
        self.emit(())
    }
}

extension Invoker where T == Void {
    convenience init<Listener: AnyObject>(listener: Listener, method: @escaping (Listener) -> () -> ()) {
        let closure: () -> Bool = {
            [weak listener] in
            guard let listener = listener else {
                return false
            }
            method(listener)()
            return true
        }
        self.init(listener: listener, closure: closure)
    }
}

// MARK: - Specific implementations for events with two arguments.

class Event2<T, U> : Event<(T, U)> {
    override func addListener<Listener: AnyObject>(_ listener: Listener, method: @escaping (Listener) -> (T, U) -> ()) {
        self.invokers.append(Invoker2(listener: listener, method: method))
    }

    func emit(_ arg0 : T, _ arg1: U) {
        self.emit((arg0, arg1))
    }
}

private class Invoker2<T, U>: Invoker<(T, U)> {
    convenience init<Listener: AnyObject>(listener: Listener, method: @escaping (Listener) -> (T, U) -> ()) {
        let closure: ((T, U)) -> Bool = {
            [weak listener] (args: (T, U)) in
            guard let listener = listener else {
                return false
            }
            method(listener)(args.0, args.1)
            return true
        }
        self.init(listener: listener, closure: closure)
    }
}
