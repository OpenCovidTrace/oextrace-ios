import Foundation

class UserStatusManager {
    
    private static let kUserStatus = "kUserStatus"
    
    static let normal = "normal"
    static let exposed = "exposed"
    
    private init() {
    }

    static var status: String {
        get {
            UserDefaults.standard.string(forKey: kUserStatus) ?? normal
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: kUserStatus)
        }
    }
    
    static func sick() -> Bool {
        return status == exposed
    }
    
}
