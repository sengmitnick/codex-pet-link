@preconcurrency import CoreBluetooth
import Foundation

public final class CodexBLEPeripheral: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "codex.pet.link.ble")
    private lazy var manager = CBPeripheralManager(delegate: self, queue: queue)
    private var statusCharacteristic: CBMutableCharacteristic?
    private var latest = CodexStatusSnapshot(
        state: .idle,
        progress: nil,
        sequence: 0,
        updatedAt: Date()
    )
    private var heartbeatTimer: DispatchSourceTimer?

    public override init() {
        super.init()
        _ = manager
    }

    public func publish(_ snapshot: CodexStatusSnapshot) {
        queue.async {
            self.latest = snapshot
            self.notifySubscribers()
        }
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            peripheral.stopAdvertising()
            stopHeartbeat()
            return
        }

        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: BLEContract.statusUUID),
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let service = CBMutableService(
            type: CBUUID(string: BLEContract.serviceUUID),
            primary: true
        )
        service.characteristics = [characteristic]
        statusCharacteristic = characteristic
        peripheral.removeAllServices()
        peripheral.add(service)
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if let error {
            Self.writeError("failed to publish GATT service: \(error)")
            return
        }

        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Codex Pet Link",
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLEContract.serviceUUID)],
        ])
        startHeartbeat()
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didStartAdvertising error: Error?
    ) {
        if let error {
            Self.writeError("failed to advertise GATT service: \(error)")
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        guard request.characteristic.uuid == CBUUID(string: BLEContract.statusUUID) else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        let packet = BLEPacket.encode(latest)
        guard request.offset <= packet.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = packet.subdata(in: request.offset..<packet.count)
        peripheral.respond(to: request, withResult: .success)
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        notifySubscribers()
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: BLEContract.heartbeat)
        timer.setEventHandler { [weak self] in
            self?.notifySubscribers()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func notifySubscribers() {
        guard manager.state == .poweredOn,
              let statusCharacteristic
        else {
            return
        }
        _ = manager.updateValue(
            BLEPacket.encode(latest),
            for: statusCharacteristic,
            onSubscribedCentrals: nil
        )
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("codex-pet-link: \(message)\n".utf8))
    }
}
