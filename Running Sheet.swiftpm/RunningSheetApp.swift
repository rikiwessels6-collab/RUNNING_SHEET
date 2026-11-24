import SwiftUI

/// WBBL Running Sheet – wraps the offline running sheet (Resources/running-sheet.html)
/// in a native iPad app: own icon, full screen, no internet needed, match data saved
/// inside the app, and working Share / Print / PDF buttons.
@main
struct RunningSheetApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var model = SheetModel()

    var body: some Scene {
        WindowGroup {
            SheetView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
        .onChange(of: phase) { _, newPhase in
            // Keep the screen awake while the sheet is open; save straight away when leaving the app.
            UIApplication.shared.isIdleTimerDisabled = (newPhase == .active)
            if newPhase != .active { model.flush() }
        }
    }
}
