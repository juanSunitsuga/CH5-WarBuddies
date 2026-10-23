/// The Indonesian labels the thesis's result tables group by.
///
/// Kept here, beside `PipelineMetrics`, rather than on each type's own
/// declaration. These strings are a reporting vocabulary, not part of the
/// rules engine, and a table heading that drifts should not mean editing
/// `LegalityValidator`.
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
            return "Bukan giliran/prioritas pemain"
        case .unitAlreadyExhausted:
            return "Unit sudah Exhausted"
        case .unitNotFound:
            return "Unit tidak ditemukan di papan"
        case .destinationOccupiedByTwoOtherControllers:
            return "Battlefield sudah dikuasai dua pemain lain"
        case .moveOriginsMismatch:
            return "Asal Move tidak konsisten"
        case .cardNotInHand:
            return "Kartu tidak ada di Hand"
        case .invalidPlayDestination:
            return "Tujuan Play tidak sah"
        case .insufficientEnergy:
            return "Energy tidak cukup"
        case .insufficientPower:
            return "Power tidak cukup"
        case .exhaustedRuneCountMismatch:
            return "Jumlah Rune yang di-Exhaust tidak cocok"
        case .reactionRequired:
            return "Perlu kartu Reaction (Chain terbuka)"
        case .actionOrReactionRequired:
            return "Perlu kartu Action atau Reaction (Showdown)"
        case .limitedActionNotAuthorized:
            return "Limited Action tanpa otorisasi"
        case .notActionPhase:
            return "Bukan Action Phase"
        case .illegalMoveDestination:
            return "Tujuan Move tidak diizinkan"
        case .noRuneOfDomainAvailable:
            return "Tidak ada Rune dari Domain tersebut"
        case .gameAlreadyWon:
            return "Permainan sudah berakhir"
        case .notImplemented:
            return "Aturan belum diimplementasikan"
        }
    }
}
