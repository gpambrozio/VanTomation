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

    var isAdvertising = false

    public static let shared = MasterManager()

    enum Constants {
        static let uuid = "12345678-1234-5678-1234-56789abc0010"
        static let name = "Vantomation"
    }

    private let manager = PeripheralManager(options: [CBPeripheralManagerOptionRestoreIdentifierKey: "br.eng.gustavo.vantomation-controller" as NSString])

    private let commandService = MutableService(uuid: Constants.uuid)

    private let commandCharacteristic = MutableCharacteristic(profile: StringCharacteristicProfile<CommandCharacteristic>())
    private let devicesCharacteristic = MutableCharacteristic(profile: StringCharacteristicProfile<ConnectedDevicesCharacteristic>())

    var commandsClosure: ((String) -> Void)? = nil
    var statusClosure: ((String) -> Void)? = nil

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
            case .unauthorized, .unknown:
                throw AppError.invalidState
            case .unsupported:
                throw AppError.unsupported
            case .resetting:
                throw AppError.resetting
            }
        }.flatMap { [unowned self] _ -> Future<Void> in
            self.manager.startAdvertising(Constants.name, uuids: [uuid])
        }

        startAdvertiseFuture.onSuccess { [unowned self] in
            self.changeStatus("Is Advertising")
            self.isAdvertising = true
        }

        startAdvertiseFuture.onFailure { [unowned self] error in
            switch error {
            case AppError.poweredOff:
                self.changeStatus("PeripheralManager powered off") {
                    self.isAdvertising = false
                    _ = self.manager.stopAdvertising()
                    self.manager.reset()
                }
            case AppError.resetting:
                let message = "PeripheralManager state \"\(self.manager.state)\". The connection with the system bluetooth service was momentarily lost.\n Restart advertising."
                self.changeStatus(message) {
                    _ = self.manager.stopAdvertising()
                    self.manager.reset()
                }
            case AppError.unsupported:
                self.changeStatus("Bluetooth not supported") {
                    self.isAdvertising = false
                }
            case PeripheralManagerError.isAdvertising:
                self.changeStatus("Bluetooth not supported") {
                    self.isAdvertising = false
                    _ = self.manager.stopAdvertising()
                    self.manager.reset()
                }
            default:
                self.changeStatus("Error: \(String(describing: error))") {
                    _ = self.manager.stopAdvertising()
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
            guard let command = String(data: value, encoding: .ascii) else {
                return
            }
            self.commandsClosure?(command)
            print("Command received \(command)")
        }
    }

    private func changeStatus(_ message: String, handler: @escaping (() -> Void) = {}) {
        print("Something happened: \(message)")
        statusClosure?(message)
        DispatchQueue.main.async(execute: handler)
    }

    func send(command: String) {
        print("Sending command \(command)")
        do {
            try self.commandCharacteristic.update(withData: command.data(using: .utf8)!)
        } catch let e {
            print("Exception \(e)")
        }
    }
}
