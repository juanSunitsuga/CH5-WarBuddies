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
        }
        .modelContainer(container)
    }
}
