// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeviceBattery",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeviceBattery", targets: ["DeviceBattery"]),
    ],
    targets: [
        // Pure protocol, parsing and state logic. No AppKit, fully unit-tested.
        .target(name: "BatteryCore"),
        // The desktop widget: AppKit UI plus IOKit / process glue.
        .executableTarget(
            name: "DeviceBattery",
            dependencies: ["BatteryCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore"]),
    ]
)
