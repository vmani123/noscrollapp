import SwiftUI

@main
struct LockedBlocksApp: App {
    @StateObject private var model = BlockModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .onChange(of: phase) { _, value in if value == .active { model.refresh() } }
        }
    }
}
