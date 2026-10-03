//
//  PenFinderDelegate.swift
//  NISDK3
//
//  Created by Aram Moon on 2018. 3. 5..
//  Copyright © 2018년 Aram Moon. All rights reserved.
//
//  Modified 2026-10-03 by MFA-Project-Development (NISDK3-solbridge 1.1.5-sb.1):
//  state restoration, public central, working didFailToConnect. See README.

import Foundation
import CoreBluetooth

/// Pen Finder Callback Protocol
public protocol PenFinderDelegate {
    /// discover pen Callback
    func discoverPen(_ peripheral: CBPeripheral, _ pen: PenAdvertisementStruct, _ rssi: Int)
    /// scanEnd Callback
    func scanStop()
    /// connected Callback
    func didConnect(_ pencontroller: PenController)
    /// connected fail with peripheral
    func didFailToConnect(_ peripheral: CBPeripheral,_ error: Error?)
    /// dis connected
    func didDisconnect(_ central: CBCentralManager, _ peripheral: CBPeripheral?,_ error: Error?)
    /// State restoration: called on the SDK queue before restored peripherals are
    /// reconnected (`didConnect` follows for each one that is or becomes connected).
    func willRestore(_ peripherals: [CBPeripheral])
}

public extension PenFinderDelegate {
    func willRestore(_ peripherals: [CBPeripheral]) {}
}
