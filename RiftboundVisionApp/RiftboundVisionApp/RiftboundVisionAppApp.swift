import SwiftUI
import SwiftData

@main
struct RiftboundVisionAppApp: App {
    /// Durable store for on-board tracked cards. Built once here so the
    /// same context is shared by the whole app; `CameraPipelineController`
    /// upserts into it every detection poll and deletes from it on
    /// trash-zone entry.
    let container: ModelContainer

    init() {
        // Sora has to be registered before any view builds, or the first
        // frame renders in the system fallback and only snaps to the real
        // face on the next redraw. `ATSApplicationFontsPath` in Info.plist
        // handles the built app; this covers previews and any context
        // where the bundle layout isn't the app's.
        RiftboundFontLoader.registerBundledFonts()

        // A store left behind by an older/incompatible schema can't be
        // opened, and SwiftData surfaces that as a throw from deep inside a
        // fault later on — a crash in board-state code that reads nothing
        // like a storage problem. Since every row here is re-derivable from
        // the camera on the next poll, a store that won't open is discarded
        // and rebuilt rather than taking the app down at launch.
        if let container = try? ModelContainer(for: PersistentTrackedCard.self) {
            self.container = container
        } else {
            container = Self.rebuildStore()
        }
    }

    /// Deletes the unreadable store and tries once more, falling back to an
    /// in-memory container so the app still runs (board state simply won't
    /// persist across launches).
    private static func rebuildStore() -> ModelContainer {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: storeURL.path() + suffix))
        }
        if let container = try? ModelContainer(for: PersistentTrackedCard.self) {
            print("⚠️ Board-state store was unreadable and has been rebuilt.")
            return container
        }
        print("⚠️ Board-state store unavailable — running without persistence this session.")
        // Force-try is safe here in a way the disk-backed attempt isn't: an
        // in-memory container has no file to fail on.
        return try! ModelContainer(
            for: PersistentTrackedCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext)
                // The window's own background shows through behind the
                // toolbar and around the content during a live resize.
                // Left as the system default it flashed grey against the
                // navy layout on every drag.
                .background(RiftboundPalette.mainBackground)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        // The reference is a fixed composition — a unified toolbar keeps
        // the title bar from adding a second, differently-coloured band
        // above the header bar.
        .windowStyle(.hiddenTitleBar)
    }
}
