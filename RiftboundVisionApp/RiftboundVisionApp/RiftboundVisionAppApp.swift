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
        do {
            container = try ModelContainer(for: PersistentTrackedCard.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext)
        }
        .modelContainer(container)
    }
}
