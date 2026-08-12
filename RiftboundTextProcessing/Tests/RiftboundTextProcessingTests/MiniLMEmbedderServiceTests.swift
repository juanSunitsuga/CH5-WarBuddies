//
//  File.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 11/08/26.
//

import Testing
@testable import RiftboundTextProcessing

@Suite("MiniLM Embedder Service Tests")
struct MiniLMEmbedderServiceTests {

    @Test("Generate 384-dimensional Float vector from text")
    func embedderGeneratesValid384dVector() async {
        let embedder = MiniLMEmbedderService()
        let sampleText = "Units you play this turn enter ready. Draw 1."
        
        let vector = await embedder.embed(text: sampleText)
        
        #expect(vector != nil)
        #expect(vector?.count == 384)
        
        if let vector = vector {
            #expect(!vector.contains(where: { $0.isNaN || $0.isInfinite }))
        }
    }
}
