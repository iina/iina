// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "IINALogic",
  platforms: [.macOS(.v12)],
  products: [
    .library(name: "IINALogic", targets: ["IINALogic"])
  ],
  targets: [
    .target(name: "IINALogic"),
    .testTarget(name: "IINALogicTests", dependencies: ["IINALogic"])
  ]
)
