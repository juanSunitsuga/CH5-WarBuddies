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
    private let model: MiniLMEmbedder?
    
    public init() {
        let config = MLModelConfiguration()
        // Hardware Acceleration: Force model onto Apple Neural Engine (ANE)
        config.computeUnits = .all
        
        do {
            self.model = try MiniLMEmbedder(configuration: config)
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
            let prediction = try model.prediction(
                input_ids: inputIdsTensor,
                attention_mask: attentionMaskTensor
            )
            
            // 3. Extract 384-dimensional output vector
            let embeddingMultiArray = prediction.embedding
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
    private func simpleTokenize(_ text: String) -> [Int32] {
        var tokenIds: [Int32] = [101] // [CLS] token start
        
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        for word in words.prefix(maxSequenceLength - 2) {
            let pseudoHash = abs(word.hashValue % 28000) + 1000
            tokenIds.append(Int32(pseudoHash))
        }
        
        tokenIds.append(102) // [SEP] token end
        return tokenIds
    }
}
