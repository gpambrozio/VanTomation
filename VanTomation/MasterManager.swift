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

    private var pastData = ""
    let statusStream = PublishSubject<String>()
    let commandsStream = PublishSubject<String>()
    let connectedStream = PublishSubject<Bool>()

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
                        self.connectedStream.onNext(true)
                        self.centrals.append(central)
                        print("connected: \(central)")
                    })
                    .disposed(by: self.disposeBag)

                self.peripheralManager.observeOnUnsubscribe()
                    .subscribe(onNext: { [weak self] (central, characteristic) in
                        guard let self = self else { return }
                        self.connectedStream.onNext(false)
                        self.centrals.removeAll(where: { (otherCentral) -> Bool in
                            central.identifier == otherCentral.identifier
                        })
                        print("disconnected: \(central)")
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

                                self.pastData += command
                                let lines = self.pastData.split(separator: "\n", omittingEmptySubsequences: false)
                                self.pastData = "\(lines.last ?? "")"
                                for line in lines.dropLast() {
                                    print("Line received '\(line)'")
                                    self.commandsStream.onNext("\(line)")
                                }
                            }
                        }
                    })
                    .disposed(by: self.disposeBag)

                self.peripheralManager.observeIsReadyToUpdateSubscribers()
                    .subscribe(onNext: { Void in
                        self.sendPendingPackets()
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

    private var pendingDataToSend = Data()
    private func sendPendingPackets() {
        objc_sync_enter(pendingDataToSend)
        defer { objc_sync_exit(pendingDataToSend) }
        if pendingDataToSend.isEmpty {
            return
        }

        let subData = pendingDataToSend.subdata(in: pendingDataToSend.startIndex..<pendingDataToSend.index(pendingDataToSend.startIndex, offsetBy: min(20, pendingDataToSend.count)))

        if peripheralManager.updateValue(subData,
                                         for: sendCharacterictic,
                                         onSubscribedCentrals: nil) {

            if pendingDataToSend.count > 20 {
                pendingDataToSend = pendingDataToSend.subdata(in: pendingDataToSend.index(after: 19)..<pendingDataToSend.endIndex)
            } else {
                pendingDataToSend = Data()
            }
            DispatchQueue.global().async { [weak self] in
                self?.sendPendingPackets()
            }
        }
    }

    func send(command: String) {
        print("Sending command \(command)")
        let data = "\(command)\n".data(using: .utf8)!
        objc_sync_enter(pendingDataToSend)
        pendingDataToSend += data
        objc_sync_exit(pendingDataToSend)
        self.sendPendingPackets()
    }
}
