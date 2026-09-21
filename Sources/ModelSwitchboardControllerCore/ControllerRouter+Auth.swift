import Foundation

extension ControllerRouter {
  func authorized(_ request: ControllerHTTPRequest) -> Bool {
    guard let authToken else { return true }
    return constantTimeEqual(request.headers["authorization"] ?? "", "Bearer \(authToken)")
  }

  func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var difference = UInt8(truncatingIfNeeded: left.count ^ right.count)
    for index in 0..<max(left.count, right.count) {
      difference |= utf8Byte(left, index) ^ utf8Byte(right, index)
    }
    return difference == 0
  }

  func utf8Byte(_ bytes: [UInt8], _ index: Int) -> UInt8 {
    index < bytes.count ? bytes[index] : 0
  }
}
