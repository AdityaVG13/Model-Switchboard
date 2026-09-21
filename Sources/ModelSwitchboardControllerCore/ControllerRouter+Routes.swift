import Foundation

extension ControllerRouter {
  var routes: [RouteKey: Route] {
    var combined = getRoutes
    for (key, route) in postRoutes {
      combined[key] = route
    }
    return combined
  }
}
