import Alamofire
import UIKit
import CoreLocation
import MapKit

class RootViewController: IndicatorViewController {
    
    static var instance: RootViewController?
    
    private static let myLocationDistanceMeters = 3000
    
    private static let annotationIdentifier = "InfectedContactAnnotation"
    
    private var mkContactPoints: [MKPointAnnotation] = []
    private var mkUserPolylines: [MKPolyline] = []
    private var mkSickPolylines: [MKPolyline] = []
    
    private var tracks: [TrackingPoint] = []
    
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var myLocationButton: UIButton!
    @IBOutlet weak var contactButton: UIButton!
    @IBOutlet weak var accuracyLabel: UILabel!
    
    @IBAction func zoomIn(_ sender: Any) {
        mapView.zoomLevel += 1
    }
    
    @IBAction func zoomOut(_ sender: Any) {
        mapView.zoomLevel -= 2
    }
    
    @IBAction func goToMyLocation(_ sender: Any) {
        guard let location = LocationManager.lastLocation else {
            return
        }
        
        goToLocation(location)
    }
    
    @IBAction func openSettings(_ sender: Any) {
        let settingsViewController = SettingsViewController(nib: R.nib.settingsViewController)
        
        navigationController?.present(settingsViewController, animated: true)
    }
    
    @IBAction func openBtLog(_ sender: Any) {
        let logsController = BtLogsViewController(nib: R.nib.btLogsViewController)
        
        navigationController?.present(logsController, animated: true)
    }
    
    @IBAction func openContacts(_ sender: Any) {
        let contactsViewController = ContactsViewController(nib: R.nib.contactsViewController)
        
        contactsViewController.rootViewController = self
        
        navigationController?.present(contactsViewController, animated: true)
    }
    
    @IBAction func makeContact(_ sender: Any) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .denied:
                    self.showSettings(R.string.localizable.notifications_disabled())
                    
                case .notDetermined:
                    self.confirm(R.string.localizable.notifications_disabled()) {
                        UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _  in
                        }
                    }
                    
                default:
                    let linkController = QrLinkViewController(nib: R.nib.qrLinkViewController)
                    
                    self.navigationController?.present(linkController, animated: true)
                }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        
        mapView.delegate = self
        mapView.showsUserLocation = true
        
        goToMyLocation()
        
        updateExtTracks()
        updateContacts()
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
            
            updateUserTracks()

            LocationManager.registerCallback { location in
                self.loadTracks(location)
                self.loadDiagnosticKeys(location)
            }
            
            if UserSettingsManager.sick() {
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
    
    
    func updateUserTracks() {
        print("Updating user tracks...")
        
        let polylines = makePolylines(TrackingManager.trackingData)
        
        print("Got \(polylines.count) user polylines.")
        
        mkUserPolylines.forEach(mapView.removeOverlay)
        mkUserPolylines = polylines.map { MKPolyline(coordinates: $0, count: $0.count) }
        mkUserPolylines.forEach(mapView.addOverlay)
    }
    
    func updateExtTracks() {
        print("Updating external tracks...")
        
        var sickPolylines: [[CLLocationCoordinate2D]] = []
        
        TracksManager.tracks.forEach { track in
            let trackPolylines = makePolylines(track.points)
            sickPolylines.append(contentsOf: trackPolylines)
        }
        
        print("Got \(sickPolylines.count) sick polylines.")
        
        let now = Date.timeIntervalSinceReferenceDate
        
        mkSickPolylines.forEach(mapView.removeOverlay)
        mkSickPolylines = sickPolylines.map { MKPolyline(coordinates: $0, count: $0.count) }
        mkSickPolylines.forEach(mapView.addOverlay)
        
        let renderTime = Int(Date.timeIntervalSinceReferenceDate - now)
        
        print("Rendered \(sickPolylines.count) sick polylines in \(renderTime) seconds.")
        
        // So that user tracks are always above
        updateUserTracks()
    }
    
    private func makePolylines(_ points: [TrackingPoint]) -> [[CLLocationCoordinate2D]] {
        var polylines: [[CLLocationCoordinate2D]] = []
        var lastPolyline: [CLLocationCoordinate2D] = []
        var lastTimestamp: Int64 = 0
        
        func addPolyline() {
            if lastPolyline.count == 1 {
                // Each polyline should have at least 2 points
                lastPolyline.append(lastPolyline.first!)
            }
            
            polylines.append(lastPolyline)
        }
        
        points.forEach { point in
            let timestamp = point.tst
            let coordinate = point.coordinate()
            
            if lastTimestamp == 0 {
                lastPolyline = [coordinate]
            } else if timestamp - lastTimestamp > TrackingManager.trackingIntervalMs * 2 {
                addPolyline()
                
                lastPolyline = [coordinate]
            } else {
                lastPolyline.append(coordinate)
            }
            
            lastTimestamp = timestamp
        }
        
        addPolyline()
        
        return polylines
    }
    
    private func goToMyLocation() {
        LocationManager.registerCallback { location in
            self.goToLocation(location)
            
            let distance = RootViewController.myLocationDistanceMeters
            
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: CLLocationDistance(exactly: distance)!,
                longitudinalMeters: CLLocationDistance(exactly: distance)!
            )
            
            self.mapView.setRegion(self.mapView.regionThatFits(region), animated: true)
            
            self.myLocationButton.isEnabled = true
        }
    }
    
    func updateContacts() {
        mkContactPoints.forEach(mapView.removeAnnotation)
        mkContactPoints.removeAll()
        
        func addContactPoint(_ metaData: ContactMetaData, _ coord: ContactCoord) {
            let annotation = MKPointAnnotation()
            
            annotation.coordinate = coord.coordinate()
            let date = AppDelegate.dateFormatter.string(from: metaData.date)
            annotation.title = R.string.localizable.contact_at_date(date)
            
            mkContactPoints.append(annotation)
        }
        
        BtContactsManager.contacts.values.forEach { contact in
            contact.encounters.forEach { encounter in
                if let metaData = encounter.metaData,
                    let coord = metaData.coord {
                    addContactPoint(metaData, coord)
                }
            }
        }
        
        QrContactsManager.contacts.forEach { contact in
            if let metaData = contact.metaData,
                let coord = metaData.coord {
                addContactPoint(metaData, coord)
            }
        }
        
        mkContactPoints.forEach(mapView.addAnnotation)
    }
    
    func goToContact(_ coord: ContactCoord) {
        goToLocation(CLLocation(latitude: coord.lat, longitude: coord.lng))
    }
    
    private func goToLocation(_ location: CLLocation) {
        mapView.setCenter(location.coordinate, animated: true)
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
                self.updateExtTracks()
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
                    self.goToContact(coord)
                    self.updateContacts()
                } else if let coord = lastBtExposedCoord {
                    self.goToContact(coord)
                    self.updateContacts()
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

extension RootViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer()
        }
        
        let renderer = MKPolylineRenderer(polyline: polyline)
        
        renderer.lineWidth = 3.0
        
        if mkUserPolylines.contains(polyline) {
            renderer.strokeColor = UIColor.systemBlue
        } else if mkSickPolylines.contains(polyline) {
            renderer.strokeColor = UIColor.systemRed
        }
        
        return renderer
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        
        var annotationView: MKAnnotationView?
            
        annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: RootViewController.annotationIdentifier)
        
        if annotationView == nil {
            let pinAnnotationView = MKPinAnnotationView(
                annotation: annotation,
                reuseIdentifier: RootViewController.annotationIdentifier
            )
            pinAnnotationView.pinTintColor = UIColor.systemRed
            annotationView = pinAnnotationView
            annotationView!.canShowCallout = true
        } else {
            annotationView!.annotation = annotation
        }
        
        return annotationView
    }
    
}


extension MKMapView {
    
    var zoomLevel: Int {
        get {
            return Int(log2(360 * (Double(frame.size.width/256) / region.span.longitudeDelta)) + 1)
        }
        
        set (newZoomLevel) {
            setCenterCoordinate(coordinate: centerCoordinate, zoomLevel: newZoomLevel, animated: false)
        }
    }
    
    private func setCenterCoordinate(coordinate: CLLocationCoordinate2D, zoomLevel: Int, animated: Bool) {
        let span = MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 360 / pow(2, Double(zoomLevel)) *
            Double(self.frame.size.width) / 256)
        setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: animated)
    }
    
}


struct ContactRequest: Codable {
    let token: String
    let platform: String
    let secret: String
    let tst: Int64
}
