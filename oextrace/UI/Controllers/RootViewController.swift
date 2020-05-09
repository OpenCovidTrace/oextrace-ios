import Alamofire
import UIKit
import CoreLocation

class RootViewController: UITabBarController {
    
    static var instance: RootViewController?
    
    var mapViewController: MapViewController!
    var statusViewController: StatusViewController!
    
    var indicator: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        indicator = addActivityIndicator()
        
        mapViewController = viewControllers?[0] as? MapViewController
        mapViewController.rootViewController = self
        
        statusViewController = viewControllers?[1] as? StatusViewController
        
        // preload all tabs
        viewControllers?.forEach { _ = $0.view }
        
        if OnboardingManager.isComplete() {
            LocationManager.requestLocationUpdates(self)
            
            BtAdvertisingManager.shared.setup()
            BtScanningManager.shared.setup()
        } else {
            navigationController?.pushViewController(
                OnboardingViewController.instanciate(),
                animated: false
            )
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
        if OnboardingManager.isComplete() {
            print("Cleaning old data...")
            
            QrContactsManager.removeOldContacts()
            TracksManager.removeOldTracks()
            TrackingManager.removeOldPoints()
            LocationBordersManager.removeOldLocationBorders()
            EncryptionKeysManager.removeOldKeys()
            BtLogsManager.removeOldItems()
            
            print("Cleaning old data complete!.")
            
            mapViewController.updateUserTracks()

            LocationManager.registerCallback { location in
                self.loadTracks(location)
                self.loadDiagnosticKeys(location)
            }
            
            if UserStatusManager.sick() {
                KeysManager.uploadNewKeys()
            }
            
            if BtScanningManager.shared.state == .poweredOff {
                showBluetoothOffWarning()
            }
        }
        
        RootViewController.instance = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        RootViewController.instance = nil
    }
    
    func showBluetoothOffWarning() {
        showInfo(R.string.localizable.bluetooth_turn_on_request())
    }
    
    func makeContact(rpi: String, key: String, token: String, platform: String, tst: Int64) {
        if abs(Int(Date.timestamp() - tst)) > 60000 {
            // QR contact should be valid for 1 minute only
            showError(R.string.localizable.contact_code_expired_error())
            
            return
        }
        
        let (rollingId, meta) = CryptoUtil.getCurrentRollingIdAndMeta()
        
        let keyData = Data(base64Encoded: key)!
        var secretData = CryptoUtil.encodeAES(rollingId, with: keyData)
        secretData.append(CryptoUtil.encodeAES(meta, with: keyData))
        
        let contactRequest = ContactRequest(token: token,
                                            platform: platform,
                                            secret: secretData.base64EncodedString(),
                                            tst: tst)
        
        indicator.show()
        
        AF.request(NetworkUtil.contactEndpoint("makeContact"),
                   method: .post,
                   parameters: contactRequest,
                   encoder: JSONParameterEncoder.default).response { response in
                    self.indicator.hide()
                    
                    let statusCode: Int = response.response?.statusCode ?? 0
                    if statusCode == 200 {
                        let contact = QrContact(rpi)
                        
                        QrContactsManager.addContact(contact)
                        
                        self.showInfo(R.string.localizable.contact_recoreded_info())
                    } else {
                        self.showError(R.string.localizable.status_code_error(statusCode))
                    }
        }
    }
    
    private func loadTracks(_ location: CLLocation) {
        indicator.show()
        
        let index = LocationIndex(location)
        let lastUpdateTimestamp = LocationIndexManager.keysIndex[index] ?? 0
        let border = LocationBorder(index)
        
        AF.request(
            NetworkUtil.storageEndpoint("tracks"),
            parameters: [
                "lastUpdateTimestamp": lastUpdateTimestamp,
                "minLat": border.minLat,
                "maxLat": border.maxLat,
                "minLng": border.minLng,
                "maxLng": border.maxLng
            ]
        ).responseDecodable(of: TracksData.self) { response in
            self.indicator.hide()
            
            if let data = response.value {
                LocationIndexManager.updateTracksIndex(index)
                
                if data.tracks.isEmpty {
                    return
                }
                
                let latestSecretDailyKeys = CryptoUtil.getLatestSecretDailyKeys()
                
                let tracksFiltered = data.tracks.filter { track in
                    !latestSecretDailyKeys.contains(track.key)
                }
                
                print("Got \(tracksFiltered.count) new tracks since \(lastUpdateTimestamp) for \(border).")
                
                if tracksFiltered.isEmpty {
                    return
                }
                
                TracksManager.addTracks(tracksFiltered)
                self.mapViewController.updateExtTracks()
            } else {
                response.reportError("GET /tracks")
            }
        }
    }
    
    private func loadDiagnosticKeys(_ location: CLLocation) {
        let index = LocationIndex(location)
        let lastUpdateTimestamp = LocationIndexManager.keysIndex[index] ?? 0
        let border = LocationBorder(index)
        
        AF.request(
            NetworkUtil.storageEndpoint("keys"),
            parameters: [
                "lastUpdateTimestamp": lastUpdateTimestamp,
                "minLat": border.minLat,
                "maxLat": border.maxLat,
                "minLng": border.minLng,
                "maxLng": border.maxLng
            ]
        ).responseDecodable(of: KeysData.self) { response in
            if let data = response.value {
                print("Got \(data.keys.count) new keys since \(lastUpdateTimestamp) for \(border).")
                
                LocationIndexManager.updateKeysIndex(index)
                
                if data.keys.isEmpty {
                    return
                }
                
                let (hasQrExposure, lastQrExposedCoord) = QrContactsManager.matchContacts(data)
                
                let (hasBtExposure, lastBtExposedCoord) = BtContactsManager.matchContacts(data)
                
                if hasQrExposure || hasBtExposure {
                    self.showExposedNotification()
                }
                
                if let coord = lastQrExposedCoord {
                    self.mapViewController.goToContact(coord)
                    self.mapViewController.updateContacts()
                } else if let coord = lastBtExposedCoord {
                    self.mapViewController.goToContact(coord)
                    self.mapViewController.updateContacts()
                }
            } else {
                response.reportError("GET /keys")
            }
        }
    }
    
    private func showExposedNotification() {
        showInfo(R.string.localizable.exposed_contact_message())
    }
    
}


struct ContactRequest: Codable {
    let token: String
    let platform: String
    let secret: String
    let tst: Int64
}
