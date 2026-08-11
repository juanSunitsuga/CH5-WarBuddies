//
//  File.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Foundation
import CoreML

/// SPM Core ML Runtime Wrapper for RiftboundCardTypeClassifier
public final class RiftboundCardTypeClassifier {
    public let model: MLModel

    public init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        guard let resourceURL = Bundle.module.url(forResource: "RiftboundCardTypeClassifier", withExtension: "mlmodelc") ??
                                Bundle.module.url(forResource: "RiftboundCardTypeClassifier", withExtension: "mlpackage") else {
            throw NSError(
                domain: "RiftboundCardTypeClassifier",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "RiftboundCardTypeClassifier model not found in Bundle.module"]
            )
        }

        let compiledURL: URL
        if resourceURL.pathExtension == "mlpackage" {
            compiledURL = try MLModel.compileModel(at: resourceURL)
        } else {
            compiledURL = resourceURL
        }

        self.model = try MLModel(contentsOf: compiledURL, configuration: configuration)
    }

    public struct Output {
        public let classLabel: String
        public let classLabel_probs: [String: Double]
    }

    public func prediction(plain_text_embedding: MLMultiArray) throws -> Output {
        let inputs: [String: Any] = [
            "plain_text_embedding": plain_text_embedding
        ]
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: inputs)
        let prediction = try model.prediction(from: featureProvider)

        let label = prediction.featureValue(for: "classLabel")?.stringValue ?? "Unknown"

        var probsDict: [String: Double] = [:]
        if let probsValue = prediction.featureValue(for: "classLabel_probs")?.dictionaryValue {
            for (key, val) in probsValue {
                if let k = key as? String, let v = val as? Double {
                    probsDict[k] = v
                }
            }
        }

        return Output(classLabel: label, classLabel_probs: probsDict)
    }
}
