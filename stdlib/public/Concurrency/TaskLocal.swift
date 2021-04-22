//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Swift
@_implementationOnly import _SwiftConcurrencyShims

/// This type must be a `class` so it has a stable identity, that is used as key
/// value for lookups in the task local storage.
@propertyWrapper
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
public final class TaskLocal<Value: Sendable>: CustomStringConvertible {
  // only reason this is ! is to store the wrapper `self` in Access so we
  // can use its identity as the key for lookups.
  private var access: Access!

  public init(default defaultValue: Value) {
    self.access = Access(key: self, defaultValue: defaultValue)
  }


  public struct Access: CustomStringConvertible {
     let key: Builtin.RawPointer
    let defaultValue: Value

    init(key: TaskLocal<Value>, defaultValue: Value) {
      self.key = unsafeBitCast(key, to: Builtin.RawPointer.self)
      self.defaultValue = defaultValue
    }

    public func get() -> Value {
      withUnsafeCurrentTask { task in
        guard let task = task else {
          return self.defaultValue
        }

        let value = _taskLocalValueGet(task._task, key: key)

        guard let rawValue = value else {
          return self.defaultValue
        }

        // Take the value; The type should be correct by construction
        let storagePtr =
            rawValue.bindMemory(to: Value.self, capacity: 1)
        return UnsafeMutablePointer<Value>(mutating: storagePtr).pointee
      }
    }

    /// Execute the `body` closure
    @discardableResult
    public func withValue<R>(_ valueDuringBody: Value, do body: () async throws -> R,
                             file: String = #file, line: UInt = #line) async rethrows -> R {
      // check if we're not trying to bind a value from an illegal context; this may crash
      _checkIllegalTaskLocalBindingWithinWithTaskGroup(file: file, line: line)

      // we need to escape the `_task` since the withUnsafeCurrentTask closure is not `async`.
      // this is safe, since we know the task will remain alive because we are running inside of it.
      let _task = withUnsafeCurrentTask { task in
        task!._task // !-safe, guaranteed to have task available inside async function
      }

      _taskLocalValuePush(_task, key: key, value: valueDuringBody)
      defer { _taskLocalValuePop(_task) }

      return try await body()
    }

    public var description: String {
      "TaskLocal<\(Value.self)>.Access"
    }
  }

  public var wrappedValue: TaskLocal<Value>.Access {
    get {
      self.access
    }

    @available(*, unavailable, message: "use 'myTaskLocal.withValue(_:do:)' instead")
    set {
      fatalError("Illegal attempt to set a \(Self.self) value, use `withValue(...) { ... }` instead.")
    }
  }

  public var description: String {
    "\(Self.self)(defaultValue: \(self.access.defaultValue))"
  }

}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
extension TaskLocal {
  public convenience init<V>() where Value == Optional<V> {
    self.init(default: nil)
  }
}

// ==== ------------------------------------------------------------------------

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
@_silgen_name("swift_task_localValuePush")
public func _taskLocalValuePush<Value>(
  _ task: Builtin.NativeObject,
  key: Builtin.RawPointer/*: Key*/,
  value: __owned Value
) // where Key: TaskLocal

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
@_silgen_name("swift_task_localValuePop")
public func _taskLocalValuePop(
  _ task: Builtin.NativeObject
)

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
@_silgen_name("swift_task_localValueGet")
public func _taskLocalValueGet(
  _ task: Builtin.NativeObject,
  key: Builtin.RawPointer/*Key*/
) -> UnsafeMutableRawPointer? // where Key: TaskLocal

// ==== Checks -----------------------------------------------------------------

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
@usableFromInline
func _checkIllegalTaskLocalBindingWithinWithTaskGroup(file: String, line: UInt) {
  if _taskHasTaskGroupStatusRecord() {
    file.withCString { _fileStart in
      _reportIllegalTaskLocalBindingWithinWithTaskGroup(
          _fileStart, file.count, true, line)
    }
  }
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
@usableFromInline
@_silgen_name("swift_task_reportIllegalTaskLocalBindingWithinWithTaskGroup")
func _reportIllegalTaskLocalBindingWithinWithTaskGroup(
  _ _filenameStart: UnsafePointer<Int8>,
  _ _filenameLength: Int,
  _ _filenameIsASCII: Bool,
  _ _line: UInt)
