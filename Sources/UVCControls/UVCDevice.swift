//
//  UCDevice.swift
//  CameraController
//
//  Created by Itay Brenner on 7/19/20.
//  Copyright © 2020 Itaysoft. All rights reserved.
//

import Foundation
import AVFoundation
import IOKit.usb

typealias USBInterfacePointer = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface190>>

public final class UVCDevice {
    let interface: USBInterfacePointer
    let processingUnitID: Int
    let cameraTerminalID: Int
    public let properties: UVCDeviceProperties

    public init(device: AVCaptureDevice) throws {
        let deviceInfo = try device.usbDevice()

        interface = deviceInfo.interface
        processingUnitID = deviceInfo.descriptor.processingUnitID
        cameraTerminalID = deviceInfo.descriptor.cameraTerminalID
        properties = UVCDeviceProperties(deviceInfo)
    }

    public init(vendorId: Int, productId: Int) throws {
        let dictionary: NSMutableDictionary = IOServiceMatching("IOUSBDevice") as NSMutableDictionary
        dictionary["idVendor"] = vendorId
        dictionary["idProduct"] = productId
        let service = IOServiceGetMatchingService(kIOMainPortDefault, dictionary)
        guard service != 0 else { throw NSError(domain: "UVCDevice", code: 1) }
        defer { IOObjectRelease(service) }

        var interfaceRef: USBInterfacePointer?
        var descriptor: UVCDescriptor?
        try service.ioCreatePluginInterfaceFor(service: kIOUSBDeviceUserClientTypeID) {
            let deviceInterface: DeviceInterfacePointer = try $0.getInterface(uuid: kIOUSBDeviceInterfaceID)
            defer { _ = deviceInterface.pointee.pointee.Release(deviceInterface) }

            let request = IOUSBFindInterfaceRequest(
                bInterfaceClass: UVCConstants.classVideo,
                bInterfaceSubClass: UVCConstants.subclassVideoControl,
                bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
                bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
            )
            try deviceInterface.iterate(interfaceRequest: request) {
                if interfaceRef == nil {
                    interfaceRef = try $0.getInterface(uuid: kIOUSBInterfaceInterfaceID)
                }
            }

            var configurationCount: UInt8 = 0
            guard deviceInterface.pointee.pointee.GetNumberOfConfigurations(
                deviceInterface, &configurationCount
            ) == kIOReturnSuccess, configurationCount > 0 else {
                throw UVCError.requestError
            }
            var configDescriptor: IOUSBConfigurationDescriptorPtr?
            guard deviceInterface.pointee.pointee.GetConfigurationDescriptorPtr(
                deviceInterface, 0, &configDescriptor
            ) == kIOReturnSuccess else {
                throw UVCError.requestError
            }
            descriptor = configDescriptor?.proccessDescriptor()
        }

        guard let interfaceRef, let descriptor else { throw UVCError.requestError }
        let deviceInfo = USBDevice(interface: interfaceRef, descriptor: descriptor)
        interface = interfaceRef
        processingUnitID = descriptor.processingUnitID
        cameraTerminalID = descriptor.cameraTerminalID
        properties = UVCDeviceProperties(deviceInfo)
    }

    deinit { _ = interface.pointee.pointee.Release(interface) }
}
