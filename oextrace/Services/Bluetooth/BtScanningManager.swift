import Foundation
import CoreBluetooth
import UIKit

class BtScanningManager: NSObject {
    
    static let shared = BtScanningManager()
    
    private static let tag = "SCAN"
    
    var state: CBManagerState?
    
    private var manager: CBCentralManager!
    
    private var peripherals: [CBPeripheral: PeripheralData] = [:]

    func setup() {
        manager = CBCentralManager(delegate: self,
                                   queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "oextraceBleScan"])
    }
    
    private func log(_ text: String) {
        BtLogsManager.append(tag: BtScanningManager.tag, text: text)
    }
}

extension BtScanningManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log(central.state.name())
        
        state = central.state
        
        if state == .poweredOn {
            manager.scanForPeripherals(withServices: [BtServiceDefinition.bleServiceUuid])
            
            log("Scanning has started")
        } else if state == .poweredOff {
            peripherals.removeAll()
            if let rootViewController = RootViewController.instance {
                rootViewController.showBluetoothOffWarning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        if let peripheralData = peripherals[peripheral],
            Date.timeIntervalSinceReferenceDate - peripheralData.date.timeIntervalSinceReferenceDate < 5 {
            return
        }
        
        peripherals[peripheral] = PeripheralData(rssi: RSSI.intValue, date: Date())
        peripheral.delegate = self
        
        NSLog("Connecting to \(peripheral.identifier.uuidString), RSSI \(RSSI.intValue)")
        
        connect(to: peripheral)
    }
    
    // MARK: - Connect to peripheral
    
    private func connect(to peripheral: CBPeripheral) {
        manager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BtServiceDefinition.bleServiceUuid])
        
        log("Device connected: \(peripheral.identifier.uuidString)")
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Failed to connect to: \(peripheral.identifier.uuidString)")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Device disconnected: \(peripheral.identifier.uuidString) error \(error?.localizedDescription ?? "NONE")")
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        log("Did restore state: \(dict)")
    }
    
}

extension BtScanningManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let errorValue = error {
            log("Error discovering services: \(errorValue.localizedDescription)")
            
            return
        }
        
        let bleService = peripheral.services?.first(where: { $0.uuid == BtServiceDefinition.bleServiceUuid })
        guard let unwrappedBleService = bleService else { return }
        
        peripheral.discoverCharacteristics([BtServiceDefinition.bleCharacteristicUuid], for: unwrappedBleService)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let errorValue = error {
            log("Error discovering services: \(errorValue.localizedDescription)")
            
            return
        }
        
        if let char = service.characteristics?.first(where: { $0.uuid == BtServiceDefinition.bleCharacteristicUuid }) {
            let data = CryptoUtil.getCurrentRpi()
            
            peripheral.writeValue(data, for: char, type: .withResponse)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        if data.count != CryptoUtil.keyLength * 2 {
            log("Received unexpected data length: \(data.count)")
        } else {
            let rollingId = data.subdata(in: 0..<CryptoUtil.keyLength).base64EncodedString()
            let meta = data.subdata(in: CryptoUtil.keyLength..<(CryptoUtil.keyLength * 2))

            if let peripheralData = peripherals[peripheral] {
                let day = CryptoUtil.currentDayNumber()
                let encounter = BtEncounter(rssi: peripheralData.rssi, meta: meta)
                BtContactsManager.addContact(rollingId, day, encounter)
                
                log("Received RPI from \(peripheral.identifier.uuidString) RSSI \(peripheralData.rssi)")
                
                AppDelegate.logEvent("received_rpi_scan")
            } else {
                log("Failed to record contact: no peripheral data")
            }
        }

        manager.cancelPeripheralConnection(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let errorValue = error {
            log("Error changing notification state: \(errorValue.localizedDescription)")

            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            if let errorDescription = error?.localizedDescription {
                log("Error write value for characteristic: \(errorDescription)")
            }
            
            return
        }
        
        log("Sent RPI to \(peripheral.identifier.uuidString)")
        
        AppDelegate.logEvent("sent_rpi_scan")
        
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        
    }

}


struct PeripheralData {
    let rssi: Int
    let date: Date
}
