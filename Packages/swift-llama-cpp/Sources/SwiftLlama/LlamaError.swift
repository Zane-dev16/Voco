//
//  LlamaError.swift
//  swift-llama-cpp
//
//  Created by Piotr Gorzelany on 30/07/2025.
//

import Foundation

public enum LlamaError: Error, LocalizedError {
    case couldNotInitializeContext
    case contextSizeLimitExeeded
    case decodingError
    case emptyMessageArray

    public var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext:
            return "Not enough memory to load the model. Close other apps and try again."
        case .contextSizeLimitExeeded:
            return "Input text is too long for the model to process."
        case .decodingError:
            return "The model encountered an error during generation. Try again."
        case .emptyMessageArray:
            return "No input provided to the model."
        }
    }
}
