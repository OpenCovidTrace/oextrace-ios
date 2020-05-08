import UIKit
import Alamofire

class StatusViewController: IndicatorViewController {
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var statusButton: UIButton!
    
    @IBAction func statusChange(_ sender: Any) {
        if UserStatusManager.sick() {
            showInfo(R.string.localizable.new_statuses_disclaimer())
        } else {
            confirm(R.string.localizable.report_exposure_confirmation()) {
                self.updateUserStatus(UserStatusManager.exposed)
            }
        }
        
        refreshStatus()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        refreshStatus()
    }
    
    private func updateUserStatus(_ status: String) {
        UserStatusManager.status = status
        
        TracksManager.uploadNewTracks()
        KeysManager.uploadNewKeys(includeToday: true)
        
        refreshStatus()
    }
    
    private func refreshStatus() {
        let status: String
        if UserStatusManager.sick() {
            status = R.string.localizable.exposed()

            statusButton.setTitle(R.string.localizable.whats_next_button(), for: .normal)
            statusButton.backgroundColor = .systemGreen
        } else {
            status = R.string.localizable.healthy()
            
            statusButton.setTitle(R.string.localizable.exposed_button(), for: .normal)
            statusButton.backgroundColor = .systemRed
        }

        statusLabel.text = R.string.localizable.status_title(status)
    }
    
}
