import Foundation
import ModelSwitchboardCore

enum HTTPParseResult {
  case request(ControllerHTTPRequest)
  case needMore
  case error(Int, String, String)
}
