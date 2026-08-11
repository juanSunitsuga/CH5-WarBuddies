//
//  File.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Foundation
import CoreML

/// SPM Core ML Runtime Wrapper for MiniLMEmbedder
public final class MiniLMEmbedder {
    public let model: MLModel

    public init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        // Find model in Bundle.module (.mlmodelc compiled or .mlpackage source)
        guard let resourceURL = Bundle.module.url(forResource: "MiniLMEmbedder", withExtension: "mlmodelc") ??
                                Bundle.module.url(forResource: "MiniLMEmbedder", withExtension: "mlpackage") else {
            throw NSError(
                domain: "MiniLMEmbedder",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "MiniLMEmbedder model not found in Bundle.module"]
            )
        }

        // Compile .mlpackage at runtime if needed
        let compiledURL: URL
        if resourceURL.pathExtension == "mlpackage" {
            compiledURL = try MLModel.compileModel(at: resourceURL)
        } else {
            compiledURL = resourceURL
        }

        self.model = try MLModel(contentsOf: compiledURL, configuration: configuration)
    }

    public struct Output {
        public let embedding: MLMultiArray
    }

    public func prediction(input_ids: MLMultiArray, attention_mask: MLMultiArray) throws -> Output {
        let inputs: [String: Any] = [
            "input_ids": input_ids,
            "attention_mask": attention_mask
        ]
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: inputs)
        let prediction = try model.prediction(from: featureProvider)

        guard let embedding = prediction.featureValue(for: "embedding")?.multiArrayValue else {
            throw NSError(
                domain: "MiniLMEmbedder",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract 'embedding' feature from model prediction"]
            )
        }

        return Output(embedding: embedding)
    }
}
