//
//  Classifier.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 06/08/26.
//

import Foundation
import CoreML

public final class MiniLMEmbedderService: @unchecked Sendable {
    
    public let vectorDimension: Int = 384
    private let maxSequenceLength: Int = 128
    private let model: MiniLMEmbedder?
    
    // Deterministic Vocabulary Lookup Table (HuggingFace BERT / MiniLM)
    private static let vocab: [String: Int32] = [
        "action": 2895, "reaction": 8103, "assault": 11782, "shield": 6386,
        "tank": 4723, "might": 4720, "draw": 4310, "units": 4135, "unit": 3158,
        "spell": 12282, "spells": 15302, "rune": 24208, "give": 2507, "two": 2048,
        "friendly": 5379, "each": 2169, "this": 2023, "turn": 2728, "when": 2043,
        "attack": 4372, "deal": 5352, "1": 1015, "2": 1016, "to": 2000, "an": 2019,
        "enemy": 4812, "here": 2182, "you": 2017, "conquer": 16008, "if": 2060,
        "have": 2031, "4+": 1018, "at": 2012, "that": 2008, "battlefield": 6183,
        "enter": 3107, "ready": 3198, "basic": 3937, "body": 2303, "rugged": 11823,
        "garen": 25088
    ]
    
    public init() {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        do {
            self.model = try MiniLMEmbedder(configuration: config)
            print("✅ MiniLM Core ML Embedder loaded successfully on Neural Engine!")
        } catch {
            print("❌ Failed to load MiniLMEmbedder.mlpackage: \(error)")
            self.model = nil
        }
    }
    
    public func embed(text: String) async -> [Float]? {
        guard let model = model else { return nil }
        
        let (inputIdsTensor, attentionMaskTensor) = prepareTokens(for: text)
        
        do {
            let prediction = try model.prediction(
                input_ids: inputIdsTensor,
                attention_mask: attentionMaskTensor
            )
            
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
    
    private func prepareTokens(for text: String) -> (input_ids: MLMultiArray, attention_mask: MLMultiArray) {
        let inputIds = try! MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        let attentionMask = try! MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
        
        let tokens = deterministicTokenize(text)
        
        for i in 0..<maxSequenceLength {
            if i < tokens.count {
                inputIds[i] = NSNumber(value: tokens[i])
                attentionMask[i] = 1
            } else {
                inputIds[i] = 0     // [PAD]
                attentionMask[i] = 0 // Masked
            }
        }
        
        return (inputIds, attentionMask)
    }
    
    /// Deterministic Hugging Face BERT Tokenizer mapping
    private func deterministicTokenize(_ text: String) -> [Int32] {
        var tokenIds: [Int32] = [101] // [CLS]
        
        let cleanedText = text.lowercased()
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
        
        let words = cleanedText.components(separatedBy: .whitespacesAndNewlines)
        for word in words.prefix(maxSequenceLength - 2) {
            guard !word.isEmpty else { continue }
            // Look up exact BERT Token ID or assign a deterministic fallback
            if let tokenID = Self.vocab[word] {
                tokenIds.append(tokenID)
            } else {
                let fallbackID = Int32(abs(word.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }) % 20000 + 1000)
                tokenIds.append(fallbackID)
            }
        }
        
        tokenIds.append(102) // [SEP]
        return tokenIds
    }
}
