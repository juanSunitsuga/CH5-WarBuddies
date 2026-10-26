/// The labels the result tables group by, and their Indonesian forms.
///
/// Kept here, beside `PipelineMetrics`, rather than on each type's own
/// declaration. These strings are a reporting vocabulary, not part of the
/// rules engine, and a table heading that drifts should not mean editing
/// `LegalityValidator`.
///
/// English is what the code records and the app shows; Indonesian is
/// produced only by `PipelineMetrics.csvReport`, which is the one thing
/// read by someone who needs it in Indonesian.
extension LegalityValidator.Failure {

    /// A stable grouping label for 4.4.4, deliberately dropping the
    /// associated values.
    ///
    /// `insufficientEnergy(required: 3, available: 2)` and
    /// `insufficientEnergy(required: 5, available: 1)` are the same kind of
    /// violation, and a table that counted them separately would have one
    /// row per occurrence instead of one row per rule — which is not a
    /// summary of anything.
    public var category: String {
        switch self {
        case .notPlayersPriority:
            return "Not this player's priority"
        case .unitAlreadyExhausted:
            return "Unit already exhausted"
        case .unitNotFound:
            return "Unit not on the board"
        case .destinationOccupiedByTwoOtherControllers:
            return "Battlefield already held by two other players"
        case .moveOriginsMismatch:
            return "Move origins don't match"
        case .cardNotInHand:
            return "Card not in hand"
        case .invalidPlayDestination:
            return "Invalid play destination"
        case .insufficientEnergy:
            return "Not enough Energy"
        case .insufficientPower:
            return "Not enough Power"
        case .exhaustedRuneCountMismatch:
            return "Exhausted Rune count doesn't match"
        case .reactionRequired:
            return "Reaction required (chain open)"
        case .actionOrReactionRequired:
            return "Action or Reaction required (showdown)"
        case .limitedActionNotAuthorized:
            return "Limited Action not authorized"
        case .notActionPhase:
            return "Not the Action Phase"
        case .illegalMoveDestination:
            return "Move destination not allowed"
        case .noRuneOfDomainAvailable:
            return "No Rune of that Domain"
        case .gameAlreadyWon:
            return "Game already over"
        case .notImplemented:
            return "Rule not implemented yet"
        }
    }
}

extension PipelineMetrics {

    /// Reasons the engine never produced an action, for 4.4.3.
    ///
    /// Named constants rather than literals at the call sites, because each
    /// one is a dictionary key here *and* a translation key below: a typo
    /// in one place would silently split one table row into two, or leave a
    /// row untranslated in the export.
    public enum Reason {
        public static let nlpStageOff = "NLP stage switched off"
        public static let noMatchingAction = "No matching action"
    }

    /// Why an event could not be placed in a zone, for 4.4.5.
    public enum UnknownZoneCause {
        public static let noZoneOnEvent = "Event carried no zone"
        public static let ownerNotCalibrated = "Card's owner not calibrated"
        public static let battlefieldSlotNotCalibrated = "Battlefield slot not calibrated"
        public static let outsideCalibratedZones = "Card outside the calibrated zones"
    }

    /// The Indonesian form of one recorded label, for the CSV export.
    ///
    /// Anything unrecognized is returned unchanged. That is deliberate and
    /// not a gap: the translator's own notes reach `reasons(for:)` as free
    /// text, so there is no fixed set to translate them against, and
    /// passing them through is better than dropping a row the thesis needs.
    public static func indonesian(for label: String) -> String {
        switch label {
        // 4.4.3
        case Reason.nlpStageOff:                return "Tahap NLP dimatikan"
        case Reason.noMatchingAction:           return "Tidak ada aksi yang cocok"

        // 4.4.4
        case "Not this player's priority":      return "Bukan giliran/prioritas pemain"
        case "Unit already exhausted":          return "Unit sudah Exhausted"
        case "Unit not on the board":           return "Unit tidak ditemukan di papan"
        case "Battlefield already held by two other players":
            return "Battlefield sudah dikuasai dua pemain lain"
        case "Move origins don't match":        return "Asal Move tidak konsisten"
        case "Card not in hand":                return "Kartu tidak ada di Hand"
        case "Invalid play destination":        return "Tujuan Play tidak sah"
        case "Not enough Energy":               return "Energy tidak cukup"
        case "Not enough Power":                return "Power tidak cukup"
        case "Exhausted Rune count doesn't match":
            return "Jumlah Rune yang di-Exhaust tidak cocok"
        case "Reaction required (chain open)":  return "Perlu kartu Reaction (Chain terbuka)"
        case "Action or Reaction required (showdown)":
            return "Perlu kartu Action atau Reaction (Showdown)"
        case "Limited Action not authorized":   return "Limited Action tanpa otorisasi"
        case "Not the Action Phase":            return "Bukan Action Phase"
        case "Move destination not allowed":    return "Tujuan Move tidak diizinkan"
        case "No Rune of that Domain":          return "Tidak ada Rune dari Domain tersebut"
        case "Game already over":               return "Permainan sudah berakhir"
        case "Rule not implemented yet":        return "Aturan belum diimplementasikan"

        // 4.4.5
        case UnknownZoneCause.noZoneOnEvent:    return "Tidak ada zona pada kejadian"
        case UnknownZoneCause.ownerNotCalibrated:
            return "Pemilik kartu tidak terkalibrasi"
        case UnknownZoneCause.battlefieldSlotNotCalibrated:
            return "Battlefield tanpa slot terkalibrasi"
        case UnknownZoneCause.outsideCalibratedZones:
            return "Kartu di luar zona terkalibrasi"

        default:                                return label
        }
    }
}
