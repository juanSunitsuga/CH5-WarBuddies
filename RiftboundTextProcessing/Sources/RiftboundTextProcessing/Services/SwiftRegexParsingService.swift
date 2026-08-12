//
//  Regex.swift
//  TextClassifier
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 07/08/26.
//

import Foundation

public struct ParsedOCRMechanics {
    public let energyCost: Int
    public let extractedTags: String
    public let categories: [String]
}

public final class SwiftRegexParser {

    /// The comprehensive categorized regex pattern dictionary — permission/
    /// timing keywords, then passive combat keywords, then mechanical
    /// commands/stat modifiers, in that display order. `(?i)` is added
    /// where the printed text can plausibly start a sentence ("Deal 6...",
    /// "Ready another unit...") and so appear capitalized; the bracketed
    /// `[Keyword]` tags and `+N Might`-style patterns always print in a
    /// fixed casing on the card itself, so they're left case-sensitive.
    private static let patterns: [(tag: String, pattern: String)] = [
        // Permissions & Timing Keywords
        ("TAG_ACTION", #"\[Action\]"#),
        ("TAG_REACTION", #"\[Reaction\]"#),

        // Passive Combat Keywords
        ("TAG_ASSAULT", #"\[Assault(?:\s+\d+)?\]"#),
        ("TAG_SHIELD", #"\[Shield(?:\s+\d+)?\]"#),
        ("TAG_TANK", #"\[Tank\]"#),
        ("TAG_GANKING", #"\[Ganking\]"#),
        ("TAG_ACCELERATE", #"\[Accelerate\]"#),
        ("TAG_DEFLECT", #"\[Deflect(?:\s+\d+)?\]"#),

        // Mechanical Commands & Stat Modifiers
        ("CMD_STAT_BOOST", #"\+\d+\s*(?::rb_might:|\[S\]|Might)"#),
        ("CMD_DRAW", #"(?i)draw\s+\d+"#),
        ("CMD_DAMAGE", #"(?i)deal\s+\d+(?:\s+damage)?"#),
        ("CMD_READY", #"(?i)ready\s+(?:another\s+)?unit"#),
        ("CMD_SPAWN_TOKEN", #"(?i)play\s+(?:a|four)?\s*\d*\s*.*token"#),
        ("CMD_CONQUER", #"(?i)when\s+you\s+conquer"#)
    ]

    /// Parses raw OCR text dynamically on the fly when SQLite database
    /// lookup misses. Walks `patterns` in order, so `extractedTags`/
    /// `categories` always come out in the same category order regardless
    /// of where a match falls in the source text.
    public static func parse(ocrText: String) -> ParsedOCRMechanics {
        var tags: [String] = []
        var categories: [String] = []

        for (tag, pattern) in patterns {
            guard let match = firstMatch(pattern: pattern, in: ocrText) else { continue }
            tags.append("<\(tag)>\(match)</\(tag)>")
            categories.append(tag)
        }

        let tagsString = "[" + tags.joined(separator: ", ") + "]"
        return ParsedOCRMechanics(energyCost: 0, extractedTags: tagsString, categories: categories)
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
