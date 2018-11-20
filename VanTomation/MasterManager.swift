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

    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abc0010")
    private let commandCharacteristicUUID = CBUUID(string: "12345679-1234-5678-1234-56789abc0010")
    private let devicesCharacteristicUUID = CBUUID(string: "1234567a-1234-5678-1234-56789abc0010")
    private let commandCharacterictic: CBMutableCharacteristic
    private let devicesCharacterictic: CBMutableCharacteristic
    private let service: CBMutableService

    private var centrals = [CBCentral]()

    private let disposeBag = DisposeBag()

    let statusStream = PublishSubject<String>()
    let commandsStream = PublishSubject<String>()

    private init() {
        service = CBMutableService(type: serviceUUID, primary: true)
        commandCharacterictic = CBMutableCharacteristic(type: commandCharacteristicUUID,
                                                        properties: [.read, .notify],
                                                        value: nil,
                                                        permissions: [.readable, .writeable])
        devicesCharacterictic = CBMutableCharacteristic(type: devicesCharacteristicUUID,
                                                        properties: [.read, .write, .writeWithoutResponse],
                                                        value: nil,
                                                        permissions: [.readable, .writeable])
        service.characteristics = [commandCharacterictic, devicesCharacterictic]

        startAdvertising()
    }

    func startAdvertising() {
        peripheralManager.observeState()
            .startWith(peripheralManager.state)
            .filter { $0 == .poweredOn }
            .take(1)
            .flatMap { _ in self.peripheralManager.add(self.service) }
            .flatMap { [serviceUUID, peripheralManager, disposeBag] _ -> Observable<StartAdvertisingResult> in
                peripheralManager.observeOnSubscribe()
                    .subscribe(onNext: { [weak self] (central, characteristic) in
                        guard let self = self else { return }
                        self.centrals.append(central)
                        print("central: \(central), char: \(characteristic)")
                    })
                    .disposed(by: disposeBag)

                peripheralManager.observeOnUnsubscribe()
                    .subscribe(onNext: { [weak self] (central, characteristic) in
                        guard let self = self else { return }
                        self.centrals.removeAll(where: { (otherCentral) -> Bool in
                            central.identifier == otherCentral.identifier
                        })
                        print("central: \(central), char: \(characteristic)")
                    })
                    .disposed(by: disposeBag)

                peripheralManager.observeDidReceiveRead()
                    .subscribe(onNext: { [peripheralManager] (request) in
                        print("Read: \(request)")
                        peripheralManager.respond(to: request, withResult: .success)
                    })
                    .disposed(by: disposeBag)

                peripheralManager.observeDidReceiveWrite()
                    .subscribe(onNext: { [weak self] (requests) in
                        guard let self = self else { return }
                        print("Write: \(requests)")
                        for request in requests {
                            self.peripheralManager.respond(to: request, withResult: .success)
                            if request.characteristic == self.devicesCharacterictic {
                                guard let value = request.value, let command = String(data: value, encoding: .ascii) else {
                                    return
                                }
                                self.commandsStream.onNext(command)
                                print("Command received \(command)")
                            }
                        }
                    })
                    .disposed(by: disposeBag)

                return peripheralManager.startAdvertising(
                    [
                        CBAdvertisementDataLocalNameKey: "Van",
                        CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                        ]
                )
            }
            .subscribe { (event) in
                print("\(event)")
            }
            .disposed(by: disposeBag)
    }

    private func present(_ vc: UIAlertController) {
        UIApplication.shared.keyWindow?.rootViewController?.present(vc, animated: true, completion: nil)
    }

    private func changeStatus(_ message: String, handler: @escaping (() -> Void) = {}) {
        print("Something happened: \(message)")
        statusStream.onNext(message)
        DispatchQueue.main.async(execute: handler)
    }

    func send(command: String) {
        print("Sending command \(command)")
        _ = peripheralManager.updateValue(command.data(using: .utf8)!,
                                          for: commandCharacterictic,
                                          onSubscribedCentrals: centrals)
    }
}
