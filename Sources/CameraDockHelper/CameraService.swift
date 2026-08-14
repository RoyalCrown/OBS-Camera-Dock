import AVFoundation
import Foundation
import UVCControls

struct ControlDescriptor: Encodable {
    let id: String
    let label: String
    let kind: String
    let value: Int?
    let enabled: Bool?
    let minimum: Int?
    let maximum: Int?
    let step: Int?
    let unit: String?
    let dependsOn: String?
}

struct CameraState: Encodable {
    let connected: Bool
    let cameraName: String?
    let message: String
    let controls: [ControlDescriptor]
}

struct ControlUpdate: Decodable {
    let id: String
    let value: Int?
    let enabled: Bool?
}

enum CameraServiceError: LocalizedError {
    case noCamera
    case unsupportedControl(String)
    case missingValue

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "Kamera Razer Kiyo V2 X není připojena."
        case let .unsupportedControl(id):
            return "Ovladač \(id) kamera nepodporuje."
        case .missingValue:
            return "Požadavek neobsahuje hodnotu."
        }
    }
}

final class CameraService {
    private let preferredName = "Razer Kiyo V2 X"
    private(set) var device: AVCaptureDevice?
    private(set) var uvcDevice: UVCDevice?
    private(set) var lastError: String?

    init() {
        rescan()
    }

    func rescan() {
        uvcDevice = nil
        device = nil
        lastError = nil

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        let cameras = session.devices
        guard let selected = cameras.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains(preferredName)
                || $0.localizedName.localizedCaseInsensitiveContains("Kiyo V2 X")
        }) else {
            lastError = "Kamera Razer Kiyo V2 X nebyla nalezena."
            return
        }

        device = selected
        do {
            uvcDevice = try UVCDevice(device: selected)
        } catch {
            lastError = "Kameru \(selected.localizedName) se nepodařilo otevřít přes UVC: \(error.localizedDescription)"
        }
    }

    func state() -> CameraState {
        guard let device, let properties = uvcDevice?.properties else {
            return CameraState(
                connected: false,
                cameraName: device?.localizedName,
                message: lastError ?? "Kamera není připravena.",
                controls: []
            )
        }

        var controls: [ControlDescriptor] = []
        appendToggle(
            &controls,
            id: "exposureAuto",
            label: "Automatická expozice",
            control: properties.exposureMode,
            enabled: properties.exposureMode.current != .manual
        )
        appendSlider(
            &controls,
            id: "exposureTime",
            label: "Čas expozice",
            control: properties.exposureTime,
            unit: "UVC",
            dependsOn: "!exposureAuto"
        )
        appendSlider(
            &controls,
            id: "gain",
            label: "Gain / ISO",
            control: properties.gain,
            unit: nil,
            dependsOn: nil
        )
        appendToggle(
            &controls,
            id: "focusAuto",
            label: "Automatické ostření",
            control: properties.focusAuto,
            enabled: properties.focusAuto.isEnabled
        )
        appendSlider(
            &controls,
            id: "focus",
            label: "Manuální ostření",
            control: properties.focusAbsolute,
            unit: nil,
            dependsOn: "!focusAuto"
        )
        appendToggle(
            &controls,
            id: "whiteBalanceAuto",
            label: "Automatické vyvážení bílé",
            control: properties.whiteBalanceAuto,
            enabled: properties.whiteBalanceAuto.isEnabled
        )
        appendSlider(
            &controls,
            id: "whiteBalance",
            label: "Teplota bílé",
            control: properties.whiteBalance,
            unit: "K",
            dependsOn: "!whiteBalanceAuto"
        )
        appendSlider(&controls, id: "brightness", label: "Jas", control: properties.brightness)
        appendSlider(&controls, id: "contrast", label: "Kontrast", control: properties.contrast)
        appendSlider(&controls, id: "saturation", label: "Saturace", control: properties.saturation)
        appendSlider(&controls, id: "sharpness", label: "Ostrost obrazu", control: properties.sharpness)
        appendSlider(&controls, id: "zoom", label: "Zoom", control: properties.zoomAbsolute)

        return CameraState(
            connected: true,
            cameraName: device.localizedName,
            message: controls.isEmpty
                ? "Kamera je připojena, ale nehlásí žádné podporované UVC ovladače."
                : "Připojeno",
            controls: controls
        )
    }

    func apply(_ update: ControlUpdate) throws {
        guard let properties = uvcDevice?.properties else { throw CameraServiceError.noCamera }

        switch update.id {
        case "exposureAuto":
            guard properties.exposureMode.isCapable else { throw CameraServiceError.unsupportedControl(update.id) }
            guard let enabled = update.enabled else { throw CameraServiceError.missingValue }
            properties.exposureMode.current = enabled ? .aperturePriority : .manual
        case "exposureTime":
            try set(properties.exposureTime, update)
        case "gain":
            try set(properties.gain, update)
        case "focusAuto":
            try set(properties.focusAuto, update)
        case "focus":
            try set(properties.focusAbsolute, update)
        case "whiteBalanceAuto":
            try set(properties.whiteBalanceAuto, update)
        case "whiteBalance":
            try set(properties.whiteBalance, update)
        case "brightness":
            try set(properties.brightness, update)
        case "contrast":
            try set(properties.contrast, update)
        case "saturation":
            try set(properties.saturation, update)
        case "sharpness":
            try set(properties.sharpness, update)
        case "zoom":
            try set(properties.zoomAbsolute, update)
        default:
            throw CameraServiceError.unsupportedControl(update.id)
        }
    }

    func reset() throws {
        guard let p = uvcDevice?.properties else { throw CameraServiceError.noCamera }
        reset(p.exposureTime)
        reset(p.gain)
        if p.exposureMode.isCapable { p.exposureMode.current = p.exposureMode.defaultValue }
        reset(p.focusAbsolute)
        if p.focusAuto.isCapable { p.focusAuto.isEnabled = p.focusAuto.defaultValue }
        reset(p.whiteBalance)
        if p.whiteBalanceAuto.isCapable { p.whiteBalanceAuto.isEnabled = p.whiteBalanceAuto.defaultValue }
        reset(p.brightness)
        reset(p.contrast)
        reset(p.saturation)
        reset(p.sharpness)
        reset(p.zoomAbsolute)
    }

    private func appendSlider(
        _ controls: inout [ControlDescriptor],
        id: String,
        label: String,
        control: UVCIntControl,
        unit: String? = nil,
        dependsOn: String? = nil
    ) {
        guard control.isCapable else { return }
        controls.append(ControlDescriptor(
            id: id,
            label: label,
            kind: "slider",
            value: control.getCurrent(),
            enabled: nil,
            minimum: control.minimum,
            maximum: control.maximum,
            step: max(1, control.resolution),
            unit: unit,
            dependsOn: dependsOn
        ))
    }

    private func appendToggle(
        _ controls: inout [ControlDescriptor],
        id: String,
        label: String,
        control: UVCControl,
        enabled: Bool
    ) {
        guard control.isCapable else { return }
        controls.append(ControlDescriptor(
            id: id,
            label: label,
            kind: "toggle",
            value: nil,
            enabled: enabled,
            minimum: nil,
            maximum: nil,
            step: nil,
            unit: nil,
            dependsOn: nil
        ))
    }

    private func set(_ control: UVCIntControl, _ update: ControlUpdate) throws {
        guard control.isCapable else { throw CameraServiceError.unsupportedControl(update.id) }
        guard let value = update.value else { throw CameraServiceError.missingValue }
        control.current = min(control.maximum, max(control.minimum, value))
    }

    private func set(_ control: UVCBoolControl, _ update: ControlUpdate) throws {
        guard control.isCapable else { throw CameraServiceError.unsupportedControl(update.id) }
        guard let enabled = update.enabled else { throw CameraServiceError.missingValue }
        control.isEnabled = enabled
    }

    private func reset(_ control: UVCIntControl) {
        guard control.isCapable else { return }
        control.current = control.defaultValue
    }
}
