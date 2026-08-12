//
//  File.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Testing
@testable import RiftboundTextProcessing

@Suite("Card Type Classifier Service Tests")
struct CardTypeClassifierServiceTests {

    let classifier = CardTypeClassifierService()
    let embedder = MiniLMEmbedderService()

    @Test("Classify card type with valid 384d embedding vector")
    func classificationWithValidEmbedding() async {
        let text = "Give two friendly units each +2 Might this turn."
        guard let vector384 = await embedder.embed(text: text) else {
            Issue.record("Failed to generate test embedding vector.")
            return
        }
        
        let result = classifier.classify(embedding: vector384)
        
        #expect(result != nil)
        if let confidence = result?.confidence {
            #expect(confidence > 0.0)
            #expect(confidence <= 1.0) // Bounded by Softmax (0.0 to 1.0)
        }
    }

    @Test("Classifier fails gracefully on invalid array dimensions")
    func classifierRejectsInvalidDimension() {
        let invalidVector = [Float](repeating: 0.5, count: 128) // Expected 384
        let result = classifier.classify(embedding: invalidVector)
        
        #expect(result == nil)
    }
}
