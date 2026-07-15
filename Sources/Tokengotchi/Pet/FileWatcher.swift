import Foundation
import Combine

class FileWatcher: NSObject, ObservableObject, NSFilePresenter {
    @Published var parsedPet: TGPetFile?
    @Published var error: Error?
    
    var presentedItemURL: URL?
    var presentedItemOperationQueue: OperationQueue = .main
    
    deinit {
        stopWatching()
    }
    
    func watch(url: URL) {
        stopWatching()
        presentedItemURL = url
        NSFileCoordinator.addFilePresenter(self)
        reloadFile()
    }
    
    func stopWatching() {
        if presentedItemURL != nil {
            NSFileCoordinator.removeFilePresenter(self)
            presentedItemURL = nil
        }
    }
    
    func presentedItemDidChange() {
        // Called when the file changes
        DispatchQueue.main.async {
            self.reloadFile()
        }
    }
    
    private func reloadFile() {
        guard let url = presentedItemURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let pet = try TGPetFile.parse(data)
            DispatchQueue.main.async {
                self.parsedPet = pet
                self.error = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
                print("FileWatcher Error decoding: \(error)")
            }
        }
    }
}
