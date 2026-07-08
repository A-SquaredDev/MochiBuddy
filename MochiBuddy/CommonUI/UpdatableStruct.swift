//
//  UpdatableStruct.swift
//  MochiBuddy
//
//  CommonUI — ergonomic chained mutations for UIState structs.
//

import Foundation

protocol UpdatableStruct {}

extension UpdatableStruct {
    func updating<Value>(_ keyPath: WritableKeyPath<Self, Value>, to value: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}
