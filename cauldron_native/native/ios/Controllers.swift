import GameController

final class Controllers {
    static let shared = Controllers()

    private var devices: [ObjectIdentifier: Int32] = [:]
    private var nextDevice: Int32 = 0
    private var state: [String: Float] = [:]

    func start() {
        let center = NotificationCenter.default
        center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        }
        center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.detach(controller) }
        }
        GCController.controllers().forEach(attach)
    }

    private func attach(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        guard devices[key] == nil, let gamepad = controller.extendedGamepad else { return }
        let device = nextDevice
        nextDevice += 1
        devices[key] = device
        cn_pad_connected(device, controller.vendorName ?? "controller")
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in self?.report(device, gamepad) }
    }

    private func detach(_ controller: GCController) {
        guard let device = devices.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        controller.extendedGamepad?.valueChangedHandler = nil
        state = state.filter { !$0.key.hasPrefix("\(device):") }
        cn_pad_disconnected(device)
    }

    private func report(_ device: Int32, _ pad: GCExtendedGamepad) {
        button(device, "a", pad.buttonA.isPressed)
        button(device, "b", pad.buttonB.isPressed)
        button(device, "x", pad.buttonX.isPressed)
        button(device, "y", pad.buttonY.isPressed)
        button(device, "left_bumper", pad.leftShoulder.isPressed)
        button(device, "right_bumper", pad.rightShoulder.isPressed)
        button(device, "start", pad.buttonMenu.isPressed)
        button(device, "back", pad.buttonOptions?.isPressed ?? false)
        button(device, "guide", pad.buttonHome?.isPressed ?? false)
        button(device, "left_stick", pad.leftThumbstickButton?.isPressed ?? false)
        button(device, "right_stick", pad.rightThumbstickButton?.isPressed ?? false)
        button(device, "dpad_up", pad.dpad.up.isPressed)
        button(device, "dpad_down", pad.dpad.down.isPressed)
        button(device, "dpad_left", pad.dpad.left.isPressed)
        button(device, "dpad_right", pad.dpad.right.isPressed)
        axis(device, "left_x", pad.leftThumbstick.xAxis.value)
        axis(device, "left_y", -pad.leftThumbstick.yAxis.value)
        axis(device, "right_x", pad.rightThumbstick.xAxis.value)
        axis(device, "right_y", -pad.rightThumbstick.yAxis.value)
        axis(device, "left_trigger", pad.leftTrigger.value)
        axis(device, "right_trigger", pad.rightTrigger.value)
    }

    private func button(_ device: Int32, _ name: String, _ pressed: Bool) {
        let key = "\(device):\(name)"
        let value: Float = pressed ? 1 : 0
        let last = state[key]
        state[key] = value
        if last == nil ? pressed : last != value { cn_pad_button(device, name, pressed ? 1 : 0) }
    }

    private func axis(_ device: Int32, _ name: String, _ value: Float) {
        let key = "\(device):\(name)"
        if let last = state[key], abs(last - value) < 0.01 { return }
        state[key] = value
        cn_pad_axis(device, name, value)
    }
}
