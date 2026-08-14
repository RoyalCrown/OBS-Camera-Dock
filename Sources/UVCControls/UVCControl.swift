//
//  UVCControl.swift
//  CameraController
//
//  Created by Itay Brenner on 7/20/20.
//  Copyright © 2020 Itaysoft. All rights reserved.
//

import Foundation

protocol Selector {
    func raw() -> Int
}

public class UVCControl {
    let interface: USBInterfacePointer
    let uvcSize: Int
    let uvcSelector: Int
    let uvcUnit: Int
    let uvcInterface: Int

    public var isCapable: Bool = false

    init(_ interface: USBInterfacePointer, _ uvcSize: Int, _ uvcSelector: Selector,
         _ uvcUnit: Int, _ uvcInterface: Int) {
        self.interface = interface
        self.uvcSize = uvcSize
        self.uvcSelector = uvcSelector.raw()
        self.uvcUnit = uvcUnit
        self.uvcInterface = uvcInterface
    }

    func getDataFor(type: UVCRequestCodes, length: Int) -> Int {
        let requestType = USBmakebmRequestType(direction: kUSBIn, type: kUSBClass, recipient: kUSBInterface)

        do {
            return try performRequest(type: type,
                                      length: length,
                                      requestType: requestType)
        } catch {
            // Should not return 0, but working on improving this
            return 0
        }
    }

    func setData(value: Int, length: Int) -> Bool {
        let requestType = USBmakebmRequestType(direction: kUSBOut, type: kUSBClass, recipient: kUSBInterface)

        do {
            _ = try performRequest(type: UVCRequestCodes.setCurrent,
                                   length: length,
                                   requestType: requestType,
                                   value: value)
            return true
        } catch {
            return false
        }
    }

    func updateIsCapable() {
        isCapable = getDataFor(type: UVCRequestCodes.getInfo, length: 1) != 0
    }

    private func performRequest(type: UVCRequestCodes,
                                length: Int,
                                requestType: UInt8,
                                value: Int = 0) throws -> Int {
        guard uvcUnit >= 0 else {
            throw UVCError.invalidUnitId
        }

        var value = value

        try withUnsafeMutablePointer(to: &value, { value in
            var request = IOUSBDevRequest(bmRequestType: requestType,
                                          bRequest: UInt8(type.rawValue),
                                          wValue: UInt16(uvcSelector<<8),
                                          wIndex: UInt16(uvcUnit<<8) | UInt16(uvcInterface),
                                          wLength: UInt16(length),
                                          pData: value,
                                          wLenDone: 0)
            let directResult = interface.pointee.pointee.ControlRequest(interface, 0, &request)
            log(result: directResult, phase: "direct", request: type)
            if directResult == kIOReturnSuccess { return }

            // Some UVC devices on newer macOS releases still require the legacy
            // interface open/close sequence. Try it only when the direct request
            // fails so cameras that work through IOUSBHost keep the fast path.
            let openResult = interface.pointee.pointee.USBInterfaceOpenSeize(interface)
            log(result: openResult, phase: "open", request: type)
            guard openResult == kIOReturnSuccess else { throw UVCError.requestError }
            defer { _ = interface.pointee.pointee.USBInterfaceClose(interface) }

            let retryResult = interface.pointee.pointee.ControlRequest(interface, 0, &request)
            log(result: retryResult, phase: "retry", request: type)
            guard retryResult == kIOReturnSuccess else {
                throw UVCError.requestError
            }
        })
        return value
    }

    private func log(result: kern_return_t, phase: String, request: UVCRequestCodes) {
        guard ProcessInfo.processInfo.environment["OBS_CAMERA_DOCK_DEBUG"] == "1" else { return }
        let code = String(format: "0x%08X", UInt32(bitPattern: result))
        fputs(
            "UVC \(phase) selector=\(uvcSelector) unit=\(uvcUnit) interface=\(uvcInterface) request=\(request.rawValue) result=\(code)\n",
            stderr
        )
    }

    private func USBmakebmRequestType(direction: Int, type: Int, recipient: Int) -> UInt8 {
        return UInt8((direction & kUSBRqDirnMask) << kUSBRqDirnShift) |
            UInt8((type & kUSBRqTypeMask) << kUSBRqTypeShift)|UInt8(recipient & kUSBRqRecipientMask)

    }
}
