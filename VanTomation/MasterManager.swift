//
//  MasterManager.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/2/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import CoreBluetooth

import BlueCapKit

enum AppError: Error {
    case invalidState
    case resetting
    case poweredOff
    case unsupported
    case unknown
}

public struct CommandCharacteristic: CharacteristicConfigurable {
    // CharacteristicConfigurable
    public static let uuid                                     = "12345679-1234-5678-1234-56789abc0010"
    public static let name                                     = "Command"
    public static let permissions: CBAttributePermissions      = [.readable, .writeable]
    public static let properties: CBCharacteristicProperties   = [.read, .notify]
    public static let initialValue                             = SerDe.serialize("")
}

public struct ConnectedDevicesCharacteristic: CharacteristicConfigurable {
    // CharacteristicConfigurable
    public static let uuid                                     = "1234567a-1234-5678-1234-56789abc0010"
    public static let name                                     = "Devices"
    public static let permissions: CBAttributePermissions      = [.readable, .writeable]
    public static let properties: CBCharacteristicProperties   = [.read, .write, .writeWithoutResponse]
    public static let initialValue                             = SerDe.serialize("")
}

class MasterManager {

    public static let shared = MasterManager()

    enum Constants {
        static let uuid = "12345678-1234-5678-1234-56789abc0010"
    }

    let manager = PeripheralManager(options: [CBPeripheralManagerOptionRestoreIdentifierKey: "us.gnos.BlueCap.peripheral-manager-example" as NSString])

    let commandService = MutableService(uuid: Constants.uuid)

    let commandCharacteristic = MutableCharacteristic(profile: StringCharacteristicProfile<CommandCharacteristic>())
    let devicesCharacteristic = MutableCharacteristic(profile: StringCharacteristicProfile<ConnectedDevicesCharacteristic>())

    var devicesClosure: ((String) -> Void)? = nil

    private init() {
        commandService.characteristics = [commandCharacteristic, devicesCharacteristic]
        startAdvertising()
    }

    func startAdvertising() {
        let uuid = CBUUID(string: Constants.uuid)

        let startAdvertiseFuture = manager.whenStateChanges().flatMap { [unowned self] state -> Future<Void> in
            switch state {
            case .poweredOn:
                self.manager.removeAllServices()
                return self.manager.add(self.commandService)
            case .poweredOff:
                throw AppError.poweredOff
            case .unauthorized:
                throw AppError.invalidState
            case .unsupported:
                throw AppError.unsupported
            case .resetting:
                throw AppError.resetting
            case .unknown:
                throw AppError.unknown
            }
        }.flatMap { [unowned self] _ -> Future<Void> in
            self.manager.startAdvertising("VanTomation", uuids: [uuid])
        }

        startAdvertiseFuture.onSuccess { _ in
        }

        startAdvertiseFuture.onFailure { [weak self] error in
            guard let `self` = self else { return }
            print("Error: \(error)")

            switch error {
            case AppError.unsupported,
                 AppError.unknown:
                break
            default:
                _ = self.manager.stopAdvertising()
                DispatchQueue.main.async {
                    self.manager.reset()
                }
            }
        }

        let devicesFuture = startAdvertiseFuture.flatMap { [unowned self] in
            self.devicesCharacteristic.startRespondingToWriteRequests()
        }
        devicesFuture.onSuccess { [unowned self] (request, _) in
            guard let value = request.value, value.count > 0 && value.count <= 16 else {
                self.devicesCharacteristic.respondToRequest(request, withResult:CBATTError.invalidAttributeValueLength)
                return
            }
            self.devicesCharacteristic.value = value
            self.devicesCharacteristic.respondToRequest(request, withResult:CBATTError.success)
            self.devicesClosure?(String(data: value, encoding: .ascii) ?? "!")
            print("Devices updated to \(value)")
        }
    }

    func send(command: String) {
        do {
            try self.commandCharacteristic.update(withData: command.data(using: .utf8)!)
        } catch let e {
            print("Exception \(e)")
        }
    }
}
