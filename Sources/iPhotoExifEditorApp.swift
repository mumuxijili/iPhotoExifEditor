import SwiftUI

@main
struct iPhotoExifEditorApp: App {
    @StateObject private var photoLibrary = PhotoLibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(photoLibrary)
        }
    }
}
