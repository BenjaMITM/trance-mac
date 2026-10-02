import Foundation

struct RenderLayer {
    var path: String
    var animated: Bool
    var alpha: Double
    var zoom: Double
    var origin: Double
}
struct RenderText {
    var text: String
    var kind: String
    var alpha: Double
    var zoom: Double
    var origin: Double
    var fontPath: String?
}
struct RenderFrame {
    var layers: [RenderLayer] = []
    var texts: [RenderText] = []
    var spiralSpeed = 0.0
    var spiralType = 0.0
    var spiralWidth = 1.0
    var warpAmplitude = 0.0
    var warpWavelength = 0.15
    var warpSpeed = 2.0
    var time = 0.0
}
