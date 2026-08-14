//
//  IOUSBConfigurationDescriptorPtr+UVC.swift
//  CameraController
//
//  Created by Itay Brenner on 7/20/20.
//  Copyright © 2020 Itaysoft. All rights reserved.
//

import Foundation
import IOKit
import UVCHeaders

extension IOUSBConfigurationDescriptorPtr {
    func proccessDescriptor() -> UVCDescriptor {
        var processingUnitID = -1
        var cameraTerminalID = -1
        var interfaceID = -1

        let totalLength = Int(UInt16(littleEndian: self.pointee.wTotalLength))
        let base = UnsafeMutablePointer<UInt8>(OpaquePointer(self))
        var offset = Int(self.pointee.bLength)
        var isVideoControlInterface = false

        // Walk every descriptor by its own bLength. Kiyo is a composite USB
        // device, so non-video interfaces can appear before the UVC interface.
        // Every iteration is bounded to prevent malformed descriptors from
        // advancing outside the configuration buffer or looping forever.
        while offset + 3 <= totalLength {
            let descriptor = base.advanced(by: offset)
            let length = Int(descriptor[0])
            let type = descriptor[1]

            if ProcessInfo.processInfo.environment["OBS_CAMERA_DOCK_DEBUG"] == "1" {
                fputs("USB descriptor offset=\(offset) length=\(length) type=0x\(String(format: "%02X", type))\n", stderr)
            }

            guard length >= 3, offset + length <= totalLength else { break }

            if type == UInt8(kUSBInterfaceDesc), length >= MemoryLayout<IOUSBInterfaceDescriptor>.size {
                let interface = UnsafeMutablePointer<IOUSBInterfaceDescriptor>(OpaquePointer(descriptor))
                isVideoControlInterface = UInt16(interface.pointee.bInterfaceClass) == UVCConstants.classVideo
                    && UInt16(interface.pointee.bInterfaceSubClass) == UVCConstants.subclassVideoControl
                interfaceID = isVideoControlInterface ? Int(interface.pointee.bInterfaceNumber) : -1
                if ProcessInfo.processInfo.environment["OBS_CAMERA_DOCK_DEBUG"] == "1" {
                    fputs(
                        "USB interface number=\(interface.pointee.bInterfaceNumber) class=\(interface.pointee.bInterfaceClass) subclass=\(interface.pointee.bInterfaceSubClass) videoControl=\(isVideoControlInterface)\n",
                        stderr
                    )
                }
            } else if type == UInt8(UVCConstants.descriptorTypeInterface), isVideoControlInterface {
                let subtype = UVCConstants.DescriptorSubtype(rawValue: descriptor[2])
                if ProcessInfo.processInfo.environment["OBS_CAMERA_DOCK_DEBUG"] == "1" {
                    fputs("UVC class descriptor subtype=0x\(String(format: "%02X", descriptor[2]))\n", stderr)
                }
                switch subtype {
                case .inputTerminal:
                    if length >= 4 { cameraTerminalID = Int(descriptor[3]) }
                case .processingUnit:
                    if length >= 4 { processingUnitID = Int(descriptor[3]) }
                default:
                    break
                }

                if interfaceID >= 0, processingUnitID >= 0, cameraTerminalID >= 0 {
                    break
                }
            }

            offset += length
        }

        if ProcessInfo.processInfo.environment["OBS_CAMERA_DOCK_DEBUG"] == "1" {
            fputs(
                "UVC descriptor result interface=\(interfaceID) cameraTerminal=\(cameraTerminalID) processingUnit=\(processingUnitID) totalLength=\(totalLength)\n",
                stderr
            )
        }

        return UVCDescriptor(processingUnitID: processingUnitID,
                             cameraTerminalID: cameraTerminalID,
                             interfaceID: interfaceID)
    }
}
