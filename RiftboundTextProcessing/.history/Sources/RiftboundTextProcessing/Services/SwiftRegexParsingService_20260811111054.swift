import Foundation

public struct ParsedOCRMechanics {
    public let energyCost: Int
    public let extractedTags: String
    public let categories: [String]
}

public final class SwiftRegexParsingService {
    
    // Regex patterns matching TCG rules
    private static let actionPattern = "\\[Action\\]"
    private static let reactionPattern = "\\[Reaction\\]"
    private static let assaultPattern = "\\[Assault(\\s+\\d+)?\\]"
    private static let shieldPattern = "\\[Shield(\\s+\\d+)?\\]"
    private static let tankPattern = "\\[Tank\\]"
    private static let drawPattern = "(?i)draw\\s+\\d+"
    private static let statBoostPattern = "\\+\\d+\\s*(Might|\\[S\\]|:rb_might:)"
    
    /// Parses raw OCR text dynamically on the fly when SQLite database lookup misses
    public static func parse(ocrText: String) -> ParsedOCRMechanics {
        var tags: [String] = []
        var categories: [String] = []
        
        // 1. Check Permissions & Keywords
        if matches(pattern: actionPattern, in: ocrText) {
            tags.append("<TAG_ACTION>[Action]</TAG_ACTION>")
            categories.append("TAG_ACTION")
        }
        if matches(pattern: reactionPattern, in: ocrText) {
            tags.append("<TAG_REACTION>[Reaction]</TAG_REACTION>")
            categories.append("TAG_REACTION")
        }
        if let match = firstMatch(pattern: assaultPattern, in: ocrText) {
            tags.append("<TAG_ASSAULT>\(match)</TAG_ASSAULT>")
            categories.append("TAG_ASSAULT")
        }
        if let match = firstMatch(pattern: shieldPattern, in: ocrText) {
            tags.append("<TAG_SHIELD>\(match)</TAG_SHIELD>")
            categories.append("TAG_SHIELD")
        }
        if matches(pattern: tankPattern, in: ocrText) {
            tags.append("<TAG_TANK>[Tank]</TAG_TANK>")
            categories.append("TAG_TANK")
        }
        
        // 2. Check Commands & Stat Buffs
        if let match = firstMatch(pattern: drawPattern, in: ocrText) {
            tags.append("<CMD_DRAW>\(match)</CMD_DRAW>")
            categories.append("CMD_DRAW")
        }
        if let match = firstMatch(pattern: statBoostPattern, in: ocrText) {
            tags.append("<CMD_STAT_BOOST>\(match)</CMD_STAT_BOOST>")
            categories.append("CMD_STAT_BOOST")
        }
        
        let tagsString = "[" + tags.joined(separator: ", ") + "]"
        return ParsedOCRMechanics(energyCost: 0, extractedTags: tagsString, categories: categories)
    }
    
    private static func matches(pattern: String, in text: String) -> Bool {
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    
    private static func firstMatch(pattern: String, in text: String) -> String? {
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }
}