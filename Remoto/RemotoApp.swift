import SwiftUI

@main
struct RemotoApp: App {
    @State private var model = RemoteViewModel()

    var body: some Scene {
        WindowGroup {
            RemoteHomeView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
