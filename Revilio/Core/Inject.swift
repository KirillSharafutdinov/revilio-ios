//
//  Inject.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/**
 A minimal, **very** lightweight service locator used exclusively by the
 `@Inject` property wrapper.
 
 Dependencies must be registered up-front – typically from a
 `DependencyContainer` – and are resolved lazily on first access.
 
 - Warning: This helper is intentionally simple and _not_ a replacement for
   a fully-featured dependency-injection framework. Use only for small
   projects or prototypes.
 */

// MARK: - Dependency Injection Errors

enum DependencyInjectionError: Error, LocalizedError {
    case dependencyNotRegistered(String)
    
    var errorDescription: String? {
        switch self {
        case .dependencyNotRegistered(let key):
            return "No registered dependency for \(key)"
        }
    }
}

public enum Resolver {
    private static var registry: [String: Any] = [:]
    /// Registers a concrete instance that should be returned for the inferred
    /// type `T` when it is later requested via `resolve(_:)`.
    public static func register<T>(_ value: T) {
        let key = String(describing: T.self)
        registry[key] = value
    }
    /// Resolves a dependency of the given type `T`. The method throws an error
    /// if no matching instance has been registered.
    public static func resolve<T>(_ type: T.Type) throws -> T {
        let key = String(describing: T.self)
        guard let value = registry[key] as? T else {
            throw DependencyInjectionError.dependencyNotRegistered(key)
        }
        return value
    }
    
    /// Safe resolve that returns nil instead of throwing
    public static func safeResolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return registry[key] as? T
    }
}

/// Property-wrapper that performs on-demand dependency resolution through the
/// global `Resolver`.
///
/// Usage example:
/// ```swift
/// @Inject var searchService: SearchService
/// ```
/// The wrapped value is looked up the first time **searchService** is
/// accessed; hence the dependency must have been previously registered via
/// `Resolver.register(_:)`.
@propertyWrapper public struct Inject<T> {
    /// Provides the lazily-resolved dependency instance of type `T`.
    public var wrappedValue: T {
        do {
            return try Resolver.resolve(T.self)
        } catch {
            // Log the error and provide a meaningful error message
            print("CRITICAL ERROR: Failed to resolve dependency \(T.self): \(error.localizedDescription)")
            print("This indicates a missing dependency registration. Please check your DependencyContainer setup.")
            
            // Use assertionFailure which can be disabled in release builds
            // This provides a clear error message in debug builds
            assertionFailure("Dependency injection failed for \(T.self): \(error.localizedDescription)")
            
            // Create a dummy instance or throw an error
            // Since we can't create a generic T, we'll use a runtime exception
            let errorMessage = "Dependency injection failed for \(T.self): \(error.localizedDescription)"
            NSException(name: NSExceptionName("DependencyInjectionError"), reason: errorMessage, userInfo: nil).raise()
            
            // This should never be reached, but provides a compile-time fallback
            // The NSException above will terminate the app with a clear error message
            return unsafeBitCast(0, to: T.self)
        }
    }
    public init() {}
} 
