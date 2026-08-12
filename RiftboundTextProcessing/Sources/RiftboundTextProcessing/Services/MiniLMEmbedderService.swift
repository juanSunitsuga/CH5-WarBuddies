//
//  Classifier.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 06/08/26.
//

import Foundation
import CoreML

/// On-Device Sentence Transformer Service (Option A: 384-dimensional vector)
public final class MiniLMEmbedderService {

    public let vectorDimension: Int = 384
    private let maxSequenceLength: Int = 128
    private let model: MLModel?

    public init() {
        let config = MLModelConfiguration()
        // Hardware Acceleration: Force model onto Apple Neural Engine (ANE)
        config.computeUnits = .all

        do {
            // `MiniLMEmbedder.mlpackage` is bundled via `.copy` (not
            // `.process` - see `Package.swift`'s doc comment on why), so
            // there's no auto-generated `MiniLMEmbedder` wrapper type;
            // compile and load it directly instead.
            guard let packageURL = Bundle.module.url(forResource: "MiniLMEmbedder", withExtension: "mlpackage") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let compiledURL = try MLModel.compileModel(at: packageURL)
            self.model = try MLModel(contentsOf: compiledURL, configuration: config)
            print("✅ MiniLM Core ML Embedder loaded successfully on Neural Engine!")
        } catch {
            print("❌ Failed to load MiniLMEmbedder.mlpackage: \(error)")
            self.model = nil
        }
    }

    /// Generates a normalized 384-dimensional Float array from input OCR text string
    /// - Parameter text: Raw OCR text extracted from physical card frame
    /// - Returns: Array of 384 Float values ready for classification or vector search
    public func embed(text: String) async -> [Float]? {
        guard let model = model else { return nil }

        // 1. Prepare numerical input_ids and attention_mask tensors [1, 64]
        let (inputIdsTensor, attentionMaskTensor) = prepareTokens(for: text)

        do {
            // 2. Perform on-device inference
            let inputs = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": inputIdsTensor,
                "attention_mask": attentionMaskTensor
            ])
            let prediction = try await model.prediction(from: inputs)

            // 3. Extract 384-dimensional output vector
            guard let embeddingMultiArray = prediction.featureValue(for: "embedding")?.multiArrayValue else {
                print("❌ MiniLM Core ML Inference Error: no 'embedding' output feature")
                return nil
            }
            var floatVector = [Float](repeating: 0.0, count: vectorDimension)

            for i in 0..<vectorDimension {
                floatVector[i] = embeddingMultiArray[i].floatValue
            }

            return floatVector

        } catch {
            print("❌ MiniLM Core ML Inference Error: \(error)")
            return nil
        }
    }
    
    // MARK: - Tokenizer Helpers
    
    /// Prepares MLMultiArray tensors [1, 64] for HuggingFace input_ids & attention_mask
    private func prepareTokens(for text: String) -> (input_ids: MLMultiArray, attention_mask: MLMultiArray) {
        let inputIds = try! MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        let attentionMask = try! MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        
        let tokens = simpleTokenize(text)
        
        for i in 0..<maxSequenceLength {
            if i < tokens.count {
                inputIds[i] = NSNumber(value: tokens[i])
                attentionMask[i] = 1 // Active token
            } else {
                inputIds[i] = 0     // [PAD] token
                attentionMask[i] = 0 // Masked token
            }
        }
        
        return (inputIds, attentionMask)
    }
    
    /// Basic tokenization helper (For exact WordPiece tokenization, use `swift-transformers` SPM package)
    ///
    /// KNOWN LIMITATION: these are pseudo-token IDs, not this model's real
    /// WordPiece vocabulary, so the embeddings are only self-consistent —
    /// they don't carry the semantic structure the classifier was trained
    /// on. That's why classification currently hovers near chance. Fixing
    /// it properly means shipping the model's actual vocab file and a real
    /// WordPiece tokenizer, not tuning this hash.
    ///
    /// What this hash MUST be, regardless of the above, is deterministic.
    /// It previously used `word.hashValue`, which Swift seeds randomly per
    /// process — so the same card text produced a different embedding on
    /// every launch, and the same input classified differently run to run
    /// (measured: 52.7% / 46.4% / 53.2% confidence for one fixed string).
    /// FNV-1a is stable across processes and platforms.
    private func simpleTokenize(_ text: String) -> [Int32] {
        var tokenIds: [Int32] = [101] // [CLS] token start

        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        for word in words.prefix(maxSequenceLength - 2) {
            let pseudoHash = Int(Self.fnv1a(word) % 28000) + 1000
            tokenIds.append(Int32(pseudoHash))
        }

        tokenIds.append(102) // [SEP] token end
        return tokenIds
    }

    /// FNV-1a, 64-bit. Chosen for being trivially implementable and
    /// deterministic across processes — not for hash quality.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
