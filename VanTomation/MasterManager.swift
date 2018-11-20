//
//  MasterManager.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/2/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import CoreBluetooth

import RxBluetoothKit
import RxSwift

class MasterManager {

    var isAdvertising = false

    public static let shared = MasterManager()

    private let peripheralManager = PeripheralManager()

    private enum Constants {
        static let serviceUUID = "12345678-1234-5678-1234-56789abc0010"
        static let sendCharacteristicUUID = "12345679-1234-5678-1234-56789abc0010"
        static let receiveCharacteristicUUID = "1234567a-1234-5678-1234-56789abc0010"
    }

    // Even though it looks like we can use one characterictic, for some reason we don't
    // get subscription callbacks if the characteristic has .notify AND .write properties
    private let sendCharacterictic: CBMutableCharacteristic
    private let receiveCharacterictic: CBMutableCharacteristic
    private let service: CBMutableService

    private var centrals = [CBCentral]()

    private let disposeBag = DisposeBag()

    let statusStream = PublishSubject<String>()
    let commandsStream = PublishSubject<String>()

    private init() {
        service = CBMutableService(type: CBUUID(string: Constants.serviceUUID), primary: true)
        sendCharacterictic = CBMutableCharacteristic(type: CBUUID(string: Constants.sendCharacteristicUUID),
                                                     properties: [.read, .notify],
                                                     value: nil,
                                                     permissions: [.readable, .writeable])
        receiveCharacterictic = CBMutableCharacteristic(type: CBUUID(string: Constants.receiveCharacteristicUUID),
                                                        properties: [.read, .write, .writeWithoutResponse],
                                                        value: nil,
                                                        permissions: [.readable, .writeable])
        service.characteristics = [sendCharacterictic, receiveCharacterictic]

        startAdvertising()
    }

    func startAdvertising() {
        peripheralManager.observeState()
            .startWith(peripheralManager.state)
            .filter { $0 == .poweredOn }
            .take(1)
            .flatMap { _ in self.peripheralManager.add(self.service) }
            .flatMap { [weak self] _ -> Observable<StartAdvertisingResult> in
                guard let self = self else { return Observable.error(BluetoothError.destroyed) }
                self.peripheralManager.observeOnSubscribe()
                    .subscribe(onNext: { [weak self] (central, characteristic) in
                        guard let self = self else { return }
                        self.changeStatus("Connected")
                        self.centrals.append(central)
                        print("central: \(central), char: \(characteristic)")
                    })
                    .disposed(by: self.disposeBag)

                self.peripheralManager.observeOnUnsubscribe()
                    .subscribe(onNext: { [weak self] (central, characteristic) in
                        guard let self = self else { return }
                        self.changeStatus("Disconnected")
                        self.centrals.removeAll(where: { (otherCentral) -> Bool in
                            central.identifier == otherCentral.identifier
                        })
                        print("central: \(central), char: \(characteristic)")
                    })
                    .disposed(by: self.disposeBag)

                self.peripheralManager.observeDidReceiveRead()
                    .subscribe(onNext: { [weak self] (request) in
                        self?.peripheralManager.respond(to: request, withResult: .success)
                    })
                    .disposed(by: self.disposeBag)

                self.peripheralManager.observeDidReceiveWrite()
                    .subscribe(onNext: { [weak self] (requests) in
                        guard let self = self else { return }
                        for request in requests {
                            self.peripheralManager.respond(to: request, withResult: .success)
                            if request.characteristic == self.receiveCharacterictic {
                                guard let value = request.value, let command = String(data: value, encoding: .ascii) else {
                                    return
                                }
                                print("Command received \(command)")
                                self.commandsStream.onNext(command)
                            }
                        }
                    })
                    .disposed(by: self.disposeBag)

                return self.peripheralManager.startAdvertising(
                    [
                        CBAdvertisementDataLocalNameKey: "Van",
                        CBAdvertisementDataServiceUUIDsKey: [self.service.uuid],
                    ]
                )
            }
            .subscribe { (event) in
                self.changeStatus("Advertising")
                print("\(event)")
            }
            .disposed(by: disposeBag)
    }

    private func changeStatus(_ message: String, handler: @escaping (() -> Void) = {}) {
        print("Something happened: \(message)")
        statusStream.onNext(message)
        DispatchQueue.main.async(execute: handler)
    }

    func send(command: String) {
        print("Sending command \(command)")
        _ = peripheralManager.updateValue(command.data(using: .utf8)!,
                                          for: sendCharacterictic,
                                          onSubscribedCentrals: centrals)
    }
}
