import UIKit

class ContactsViewController: UIViewController {
    
    static var instance: ContactsViewController?
    
    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateStyle = .medium
        
        return dateFormatter
    }()
    
    var rootViewController: RootViewController!
    
    private var cells = [ContactCell]()
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var noContactsLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(R.nib.contactTableViewCell)
        
        refresh()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        ContactsViewController.instance = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        ContactsViewController.instance = nil
    }
    
    func refresh() {
        cells.removeAll()
        
        cells.append(contentsOf: BtContactsManager.contacts.values.map { $0.toCell() })
        cells.append(contentsOf: QrContactsManager.contacts.map { $0.toCell() })
        
        cells.sort { first, second in
            if first.day() == second.day() {
                if let firstMetaData = first.metaData(),
                    let secondMetaData = second.metaData() {
                    return firstMetaData.date > secondMetaData.date
                } else if first.metaData() != nil {
                    return true
                }
                
                return false
            } else {
                return first.day() > second.day()
            }
        }
        
        noContactsLabel.isHidden = !cells.isEmpty
        
        tableView.reloadData()
    }
    
}

extension ContactsViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return cells.count
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 64
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let contact = cells[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.contactCell, for: indexPath)!
        
        if let btContact = contact.btContact {
            cell.typeLabel.text = R.string.localizable.bt_contact()
            
            if let firstMetaData = btContact.encounters.first?.metaData,
                let lastMetaData = btContact.encounters.last?.metaData {
                if btContact.encounters.count == 1 {
                    cell.timeLabel.text = AppDelegate.dateFormatter.string(from: firstMetaData.date)
                } else {
                    cell.timeLabel.text = AppDelegate.dateFormatter.string(from: firstMetaData.date) +
                        " - " + AppDelegate.dateFormatter.string(from: lastMetaData.date)
                }
                
                cell.locationImage.isHidden = firstMetaData.coord == nil
            } else {
                cell.timeLabel.text = ContactsViewController.dateFormatter.string(
                    from: CryptoUtil.getDate(dayNumber: btContact.day)
                )
                
                cell.locationImage.isHidden = true
            }
            
            cell.encountersLabel.text = R.string.localizable.encounters(btContact.encounters.count)
            cell.encountersLabel.isHidden = false
        } else if let qrContact = contact.qrContact {
            cell.typeLabel.text = R.string.localizable.qr_contact()
            
            if let metaData = qrContact.metaData {
                cell.timeLabel.text = AppDelegate.dateFormatter.string(from: metaData.date)
                
                cell.locationImage.isHidden = metaData.coord == nil
            } else {
                cell.timeLabel.text = ContactsViewController.dateFormatter.string(
                    from: CryptoUtil.getDate(dayNumber: qrContact.day)
                )
                
                cell.locationImage.isHidden = true
            }
            
            cell.encountersLabel.isHidden = true
        }
        
        return cell
    }
    
}

extension ContactsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let contact = cells[indexPath.row]
        
        if let metaData = contact.metaData(),
            let coord = metaData.coord {
            rootViewController.showMap()
            rootViewController.mapViewController.goToContact(coord)
        }
    }
    
}



struct ContactCell {
    let btContact: BtContact?
    let qrContact: QrContact?
    
    func day() -> Int {
        if let btCon = btContact {
            return btCon.day
        } else {
            return qrContact!.day
        }
    }
    
    func metaData() -> ContactMetaData? {
        if let btCon = btContact {
            return btCon.encounters.first!.metaData
        } else {
            return qrContact!.metaData
        }
    }
}
