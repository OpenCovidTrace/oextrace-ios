import UIKit
import CoreLocation
import Firebase
import AlamofireNetworkActivityIndicator

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static let appName = "OExTrace"
    
    static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium
        
        return dateFormatter
    }()
    
    static var deviceTokenEncoded: String?
    
    private static let makeContactCategory = "MAKE_CONTACT"
    private static let tagApp = "APP"
    private static let tagSys = "SYS"
    
    var window: UIWindow?
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        /*
         * Firebase
         */
        
        FirebaseApp.configure()
        
        
        /*
         * Network indicator
         */
        
        NetworkActivityIndicatorManager.shared.isEnabled = true
        
        
        /*
         * Notifications setup
         */
        
        let makeContactMessageCategory = UNNotificationCategory(identifier: AppDelegate.makeContactCategory,
                                                                actions: [],
                                                                intentIdentifiers: [],
                                                                options: .customDismissAction)
        
        let center = UNUserNotificationCenter.current()
        
        center.setNotificationCategories([makeContactMessageCategory])
        center.delegate = self
        
        application.registerForRemoteNotifications()
        
        
        /*
         * Power state notifications
         */
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.logPowerState),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        
        logPowerState()

        
        /*
         * Locaction updates
         */
        
        LocationManager.initialize(self)
        
        
        /*
         * BLE services
         */
        
        if OnboardingManager.isComplete() {
            BtAdvertisingManager.shared.setup()
            BtScanningManager.shared.setup()
            
            logApp("App did finish launching")
        }
        
        
        return true
    }
    
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            guard let url = userActivity.webpageURL else {
                return true
            }
            
            /*
             Existing scheme:
             https://HOST/.well-known/apple-app-site-association
             */
            if url.pathComponents.count == 3 && url.pathComponents[2] == "contact" {
                if let rpi = url.valueOf("r"),
                    let key = url.valueOf("k"),
                    let token = url.valueOf("d"),
                    let platform = url.valueOf("p"),
                    let tst = url.valueOf("t") {
                    self.withRootController { rootViewController in
                        rootViewController.makeContact(
                            rpi: rpi,
                            key: key,
                            token: token,
                            platform: platform,
                            tst: Int64(tst)!
                        )
                    }
                }
            }
        }
        
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Transforming to format acceptable by backend
        AppDelegate.deviceTokenEncoded = deviceToken.reduce("", { $0 + String(format: "%02X", $1) })
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // This is called in order for viewWillDisappear to be executed
        self.window?.rootViewController?.beginAppearanceTransition(false, animated: false)
        self.window?.rootViewController?.endAppearanceTransition()
        
        LocationManager.updateAccuracy(foreground: false)
        
        print("App did enter background")
        logApp("App did enter background")
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("App will enter foreground")
        logApp("App will enter foreground")
        
        LocationManager.updateAccuracy(foreground: true)
        
        // This is called in order for viewWillAppear to be executed
        self.window?.rootViewController?.beginAppearanceTransition(true, animated: false)
        self.window?.rootViewController?.endAppearanceTransition()
    }
    
    @objc private func logPowerState() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            logSys("Low power mode is ON")
        } else {
            logSys("Low power mode is OFF")
        }
    }
    
    private func logApp(_ text: String) {
        BtLogsManager.append(tag: AppDelegate.tagApp, text: text)
    }
    
    private func logSys(_ text: String) {
        DispatchQueue.main.async {
            BtLogsManager.append(tag: AppDelegate.tagSys, text: text)
        }
    }
    
    static func logEvent(_ message: String, _ parameters: [String: Any]? = nil) {
        #if DEBUG
        #else
        Analytics.logEvent(message, parameters: parameters)
        #endif
    }
    
}

extension AppDelegate: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            LocationManager.updateLocation(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            LocationManager.startUpdatingLocation()
        }
    }
    
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if response.notification.request.content.categoryIdentifier == AppDelegate.makeContactCategory {
            let secret = userInfo["secret"] as! String
            let tst = userInfo["tst"] as! Int64
            
            if let key = EncryptionKeysManager.encryptionKeys[tst] {
                let secretData = Data(base64Encoded: secret)!
                
                let rollingId = CryptoUtil.decodeAES(secretData.prefix(CryptoUtil.keyLength), with: key)
                let meta = CryptoUtil.decodeAES(secretData.suffix(CryptoUtil.keyLength), with: key)
                
                let contact = QrContact(rollingId.base64EncodedString(), meta)
                
                QrContactsManager.addContact(contact)
                
                if let qrLinkViewController = QrLinkViewController.instance {
                    qrLinkViewController.dismiss(animated: true, completion: nil)
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Swift.Void) {
        completionHandler([.alert, .sound])
    }
    
    private func withRootController(_ handler: (RootViewController) -> Void) {
        if let navigationController = self.window?.rootViewController as? UINavigationController {
            _ = navigationController.popToRootViewController(animated: false)
            let rootViewController = navigationController.topViewController as! RootViewController
            
            handler(rootViewController)
        }
    }
    
}
