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
    var presets: PresetLibrary = PresetLibrary()
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
    static let panelControls: [String: [String]] = [
        "expo": ["exposureAuto", "exposureTime", "gain", "brightness", "focusAuto", "focus"],
        "obraz": ["contrast", "saturation", "sharpness", "whiteBalanceAuto", "whiteBalance"],
        "optika": ["zoom", "tilt", "pan", "backlight"]
    ]

    static let startupPresetID = "rrc_base"
    static let startupPresetName = "rrc_base"

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
        appendSlider(&controls, id: "backlight", label: "Backlight", control: properties.backlightCompensation)
        if properties.panTiltAbsolute.isCapable {
            let panTilt = properties.panTiltAbsolute
            appendAxis(
                &controls,
                id: "pan",
                label: "Pan",
                value: panTilt.current1,
                minimum: panTilt.minimum1,
                maximum: panTilt.maximum1,
                step: max(1, panTilt.resolution1),
                unit: "°"
            )
            appendAxis(
                &controls,
                id: "tilt",
                label: "Tilt",
                value: panTilt.current2,
                minimum: panTilt.minimum2,
                maximum: panTilt.maximum2,
                step: max(1, panTilt.resolution2),
                unit: "°"
            )
        }

        return CameraState(
            connected: true,
            cameraName: device.localizedName,
            message: controls.isEmpty
                ? "Kamera je připojena, ale nehlásí žádné podporované UVC ovladače."
                : "Připojeno",
            controls: controls
        )
    }

    func snapshot(panel: String) throws -> [String: PresetValue] {
        guard uvcDevice != nil else { throw CameraServiceError.noCamera }
        let ids = Self.panelControls[panel] ?? []
        var values: [String: PresetValue] = [:]
        for control in state().controls where ids.contains(control.id) {
            values[control.id] = PresetValue(value: control.value, enabled: control.enabled)
        }
        return values
    }

    func applyPreset(_ values: [String: PresetValue]) throws {
        guard uvcDevice != nil else { throw CameraServiceError.noCamera }
        for (id, preset) in values where preset.enabled != nil {
            try? apply(ControlUpdate(id: id, value: nil, enabled: preset.enabled))
        }
        for (id, preset) in values where preset.value != nil {
            try? apply(ControlUpdate(id: id, value: preset.value, enabled: nil))
        }
    }

    static func buildRRCBaseValues(controls: [ControlDescriptor]) -> [String: PresetValue]? {
        guard controls.contains(where: { $0.id == "exposureTime" }) else { return nil }
        var values: [String: PresetValue] = [:]
        values["exposureAuto"] = PresetValue(value: nil, enabled: false)
        values["focusAuto"] = PresetValue(value: nil, enabled: false)
        values["whiteBalanceAuto"] = PresetValue(value: nil, enabled: false)

        if let control = controls.first(where: { $0.id == "exposureTime" }) {
            values["exposureTime"] = PresetValue(value: uvcFromShutter(60, control: control), enabled: nil)
        }
        if let control = controls.first(where: { $0.id == "gain" }) {
            values["gain"] = PresetValue(value: gainFromISO(400, control: control), enabled: nil)
        }
        if let control = controls.first(where: { $0.id == "brightness" }) {
            values["brightness"] = PresetValue(value: uvcFromPercent(48, control: control), enabled: nil)
        }
        if let control = controls.first(where: { $0.id == "focus" }) {
            values["focus"] = PresetValue(value: uvcFromFocusDisplay(68, control: control), enabled: nil)
        }
        if let control = controls.first(where: { $0.id == "whiteBalance" }) {
            values["whiteBalance"] = PresetValue(value: kelvinValue(4200, control: control), enabled: nil)
        }
        return values
    }

    static func uvcFromShutter(_ denom: Int, control: ControlDescriptor) -> Int {
        let uvc = max(1, (10_000 + denom / 2) / denom)
        return clamp(uvc, control: control)
    }

    static func gainFromISO(_ iso: Int, control: ControlDescriptor) -> Int {
        let clampedISO = min(1600, max(100, iso))
        let t = log(Double(clampedISO) / 100.0) / log(16.0)
        let span = Double((control.maximum ?? 0) - (control.minimum ?? 0))
        let step = Double(max(1, control.step ?? 1))
        let minimum = Double(control.minimum ?? 0)
        let raw = minimum + t * span
        return clamp(Int((raw / step).rounded()) * Int(step), control: control)
    }

    static func uvcFromPercent(_ percent: Int, control: ControlDescriptor) -> Int {
        let span = (control.maximum ?? 0) - (control.minimum ?? 0)
        guard span > 0 else { return control.minimum ?? 0 }
        let step = max(1, control.step ?? 1)
        let minimum = control.minimum ?? 0
        let raw = Double(minimum) + (Double(min(100, max(0, percent))) / 100.0) * Double(span)
        return clamp(Int((raw / Double(step)).rounded()) * step, control: control)
    }

    static func uvcFromFocusDisplay(_ display: Int, control: ControlDescriptor) -> Int {
        uvcFromPercent(100 - display, control: control)
    }

    static func kelvinValue(_ kelvin: Int, control: ControlDescriptor) -> Int {
        let range = whiteBalanceRange(control)
        let rounded = Int((Double(kelvin) / 50.0).rounded()) * 50
        return clamp(rounded, minimum: range.min, maximum: range.max)
    }

    private static func whiteBalanceRange(_ control: ControlDescriptor) -> (min: Int, max: Int) {
        let warm = 2800
        let cool = 6500
        let minValue = max(control.minimum ?? warm, warm)
        let maxValue = min(control.maximum ?? cool, cool)
        if maxValue <= minValue {
            return (control.minimum ?? warm, control.maximum ?? cool)
        }
        return (minValue, maxValue)
    }

    private static func clamp(_ value: Int, control: ControlDescriptor) -> Int {
        clamp(value, minimum: control.minimum ?? value, maximum: control.maximum ?? value)
    }

    private static func clamp(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(maximum, max(minimum, value))
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
        case "backlight":
            try set(properties.backlightCompensation, update)
        case "pan":
            try set(properties.panTiltAbsolute, axis: 1, update)
        case "tilt":
            try set(properties.panTiltAbsolute, axis: 2, update)
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
        reset(p.backlightCompensation)
        if p.panTiltAbsolute.isCapable {
            p.panTiltAbsolute.current1 = p.panTiltAbsolute.defaultValue1
            p.panTiltAbsolute.current2 = p.panTiltAbsolute.defaultValue2
        }
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

    private func appendAxis(
        _ controls: inout [ControlDescriptor],
        id: String,
        label: String,
        value: Int,
        minimum: Int,
        maximum: Int,
        step: Int,
        unit: String?
    ) {
        guard minimum != maximum else { return }
        controls.append(ControlDescriptor(
            id: id,
            label: label,
            kind: "slider",
            value: value,
            enabled: nil,
            minimum: minimum,
            maximum: maximum,
            step: step,
            unit: unit,
            dependsOn: nil
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

    private func set(_ control: UVCMultipleIntControl, axis: Int, _ update: ControlUpdate) throws {
        guard control.isCapable else { throw CameraServiceError.unsupportedControl(update.id) }
        guard let value = update.value else { throw CameraServiceError.missingValue }
        if axis == 1 {
            control.current1 = min(control.maximum1, max(control.minimum1, value))
        } else {
            control.current2 = min(control.maximum2, max(control.minimum2, value))
        }
    }

    private func reset(_ control: UVCIntControl) {
        guard control.isCapable else { return }
        control.current = control.defaultValue
    }
}
