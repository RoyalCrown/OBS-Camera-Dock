import Foundation
import UVCControls

func runUSBDiagnostics() {
    do {
        let device = try UVCDevice(vendorId: 5426, productId: 3596)
        let properties = device.properties
        let result: [String: Any] = [
            "focusAuto": properties.focusAuto.isCapable,
            "focus": properties.focusAbsolute.isCapable,
            "exposureMode": properties.exposureMode.isCapable,
            "exposureTime": properties.exposureTime.isCapable,
            "gain": properties.gain.isCapable,
            "whiteBalanceAuto": properties.whiteBalanceAuto.isCapable,
            "whiteBalance": properties.whiteBalance.isCapable,
            "brightness": properties.brightness.isCapable,
            "contrast": properties.contrast.isCapable,
            "saturation": properties.saturation.isCapable,
            "sharpness": properties.sharpness.isCapable,
            "zoom": properties.zoomAbsolute.isCapable
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } catch {
        fputs("USB diagnostika selhala: \(error.localizedDescription)\n", stderr)
    }
}
