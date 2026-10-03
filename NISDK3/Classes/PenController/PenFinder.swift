//
//  PenFinder.swift
//  NISDK3
//
//  Created by Aram Moon on 2017. 7. 3..
//  Copyright © 2017년 Aram Moon. All rights reserved.
//

import Foundation
import CoreBluetooth
#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit

#elseif os(macOS)
import AppKit
#else
#endif

/// Pen Search and Connect Helper Class
public class PenFinder: NSObject {
    
    /// Singleton instance
    public static let shared = PenFinder()
    
    /// State-restoration identifier for the SDK's CBCentralManager.
    /// Must be set before the first access to `PenFinder.shared` (ideally in
    /// `application(_:didFinishLaunchingWithOptions:)`), otherwise iOS cannot
    /// relaunch the app for BLE events after it was terminated in background.
    public static var restoreIdentifier: String?

    /// PenFinderDelegate
    /// Restored peripherals that arrived before a delegate was attached are
    /// delivered as soon as one is set.
    public var delegate: PenFinderDelegate? {
        didSet { deliverRestoredIfPossible() }
    }
    
    private var centralManager: CBCentralManager!

    /// The SDK-owned central. Exposed so apps can `retrievePeripherals`,
    /// `cancelPeripheralConnection` and read `state` without reflection.
    public var central: CBCentralManager { return centralManager }

    private let btQueue = DispatchQueue(label: "kr.neolab.penBT")
    private let restoreLock = NSLock()
    private var restoredPeripherals: [CBPeripheral] = []
    private var restoreReady = false
    
    private var timer: Timer?
    
    private var findlist: [(peripheral: CBPeripheral, penAd: PenAdvertisementStruct, rssi: Int)] = []
    
    /// Readonly Blutooth On flag
    public private(set) var bluetoothOn = false
    
    private override init(){
        super.init()
        initBluetooth()
    }
    
    //MARK: - Public Bluetooth -
    /// Scan for peripherals - specifically for our service's 128bit CBUUID
    /// if time = 0 not stop
    public func scan(_ second: CGFloat) {
//        N.Log("Scanning started")
        findlist.removeAll()
        centralManager.stopScan()
        centralManager.scanForPeripherals(withServices: [NEOLAB.PEN_SERVICE_UUID, NEOLAB.PEN_SERVICE_UUID_128], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if !second.isZero{
            startScanTimer(second)
        }
    }

    /// scan stop
    public func scanStop() {
        timer?.invalidate()
        timer = nil
        if centralManager.state == .poweredOn {
            centralManager.stopScan()
            self.delegate?.scanStop()
        }
    }
    
    /// disconnect
    public func disConnect(_ peripheral: CBPeripheral) {
        // Give some time to pen, before actual disconnect.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double((Int64)(500 * NSEC_PER_MSEC)) / Double(NSEC_PER_SEC), execute: {() -> Void in
            self.centralManager.cancelPeripheralConnection(peripheral)
        })
    }
    
    /**
     connect pen
     - Parameters:
        - peripheral: CBPeripheral
     - callback: PenFinderDelegate.connectpen
     */
    public func connectPeripheral(_ peripheral: CBPeripheral) {
        N.Log("Connecting to peripheral \(String(describing: peripheral))")
        centralManager.connect(peripheral, options: nil)
    }
    
    
    //MARK: - private Bluetooth -
    private func startScanTimer(_ duration: CGFloat) {
        if timer == nil {
            timer = Timer(timeInterval: TimeInterval(duration), target: self, selector: #selector(self.stopScanTimer), userInfo: nil, repeats: false)
            RunLoop.main.add(timer!, forMode: RunLoop.Mode.default)
        }
    }
    
    @objc private func stopScanTimer() {
        scanStop()
    }
    
}

extension PenFinder: CBCentralManagerDelegate {
    //MARK: - Ignore It -
    /// we start the connection process
    fileprivate func initBluetooth(){
        var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: true]
        if let identifier = PenFinder.restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = identifier
        }
        centralManager = CBCentralManager(delegate: self, queue: btQueue, options: options)
    }

    // State restoration: iOS relaunched the app for a BLE event and hands back the
    // peripherals the previous process had connected or was connecting to.
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        N.Log("centralManager willRestoreState peripherals: \(peripherals.count)")
        restoreLock.lock()
        restoredPeripherals.append(contentsOf: peripherals)
        restoreLock.unlock()
        if central.state == .poweredOn { markRestoreReady() }
    }

    // Commands to a restored peripheral are only valid once the central is powered on,
    // and the delegate must exist to receive the resulting PenController.
    private func markRestoreReady() {
        restoreLock.lock()
        restoreReady = true
        restoreLock.unlock()
        deliverRestoredIfPossible()
    }

    private func deliverRestoredIfPossible() {
        restoreLock.lock()
        guard restoreReady, let delegate = delegate, !restoredPeripherals.isEmpty else {
            restoreLock.unlock()
            return
        }
        let peripherals = restoredPeripherals
        restoredPeripherals.removeAll()
        restoreLock.unlock()
        let central = centralManager!
        btQueue.async {
            delegate.willRestore(peripherals)
            for peripheral in peripherals {
                switch peripheral.state {
                case .connected:
                    // Rebuild the PenController exactly like a fresh didConnect so the
                    // service discovery and pen handshake run again in this process.
                    self.centralManager(central, didConnect: peripheral)
                case .connecting:
                    break // the pending connect survives restoration; didConnect follows
                default:
                    central.connect(peripheral, options: nil)
                }
            }
        }
    }
        
    // Central Manager State Change
    /// :nodoc:
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if #available(iOS 10.0, *) {
            switch central.state{
            case CBManagerState.unauthorized:
                N.Log("This app is not authorised to use Bluetooth low energy")
            case CBManagerState.poweredOff:
                bluetoothOn = false
                self.delegate?.didDisconnect(centralManager, nil, nil)
                N.Log("Bluetooth is currently powered off.")
            case CBManagerState.poweredOn:
                bluetoothOn = true
                N.Log("Bluetooth is currently powered on and available to use.")
                markRestoreReady()
            default:break
            }
        } else {
            // Fallback on earlier versions
            switch central.state.rawValue {
            case 3: // CBCentralManagerState.unauthorized :
                N.Log("This app is not authorised to use Bluetooth low energy")
            case 4: // CBCentralManagerState.poweredOff:
                bluetoothOn = false
                self.delegate?.didDisconnect(centralManager, nil, nil)
                N.Log("Bluetooth is currently powered off.")
            case 5: //CBCentralManagerState.poweredOn:
                bluetoothOn = true
                N.Log("Bluetooth is currently powered on and available to use.")
            default:break
            }
        }
    }
    
    // Scanning... Discover Pen
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if Int(truncating: RSSI) > -15 {
            return
        }
        guard let serviceUUIDs = (advertisementData["kCBAdvDataServiceUUIDs"] as? [CBUUID]) else{
            return
        }

        //펜 3초간 눌렀을때 제공되는 UUID 19F0
        if serviceUUIDs.contains(NEOLAB.PEN_SERVICE_PAIRMODE_UUID) {
//            N.Log("found service 19F0 Pairing Mode")
        }
        else if (serviceUUIDs.contains(NEOLAB.PEN_SERVICE_UUID) || serviceUUIDs.contains(NEOLAB.PEN_SERVICE_UUID_128)) {
            //                N.Log("found service 19F1 return")
            // TODO: 페어링 아닐때도 연결 가능(retun 하면 페어링모드만)
//                return
            
        } else {
            return
        }
    
        let rssi = Int(truncating: RSSI)
        let penAdvertiseMent = PenAdvertisementStruct(advertisementData, peripheral)
//        N.Log(penAdvertiseMent)

        self.findlist.append((peripheral, penAdvertiseMent, rssi))
//        N.Log("Find Device", mac, subName, rssi)
        self.delegate?.discoverPen(peripheral, penAdvertiseMent, rssi)
    }
    
    // Connect Fail
    // Was `private ... throws`, which never matched the CBCentralManagerDelegate
    // selector, so connection failures were silently dropped.
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        N.Log("Failed to connect to \(peripheral). (\(String(describing: error?.localizedDescription)))")
        self.delegate?.didFailToConnect(peripheral, error)
    }
    
    // Step1: Connect -> Discover Service
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let pen = PenController(peripheral)
        if let scanPen = findlist.filter({$0.0 == peripheral}).first {
            pen.penAdvertisement = scanPen.penAd
            pen.macAddress = scanPen.penAd.mac
        }
        pen.centralManager = central
        self.delegate?.didConnect(pen)
    }
    /// Disconnect
    /// :nodoc:
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        N.Log("centralManager Peripheral Disconnected", error ?? "")
        self.delegate?.didDisconnect(central, peripheral, error)
    }
}
