import SwiftUI

@main
struct AnamorphicApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 980, minHeight: 660)
                #endif
        }
    }
}
