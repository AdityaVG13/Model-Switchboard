import Foundation

extension ControllerRouter {
  var postRoutes: [RouteKey: Route] {
    [
      RouteKey(method: "POST", path: "/api/start"): profileAction(service.start),
      RouteKey(method: "POST", path: "/api/stop"): profileAction(service.stop),
      RouteKey(method: "POST", path: "/api/restart"): profileAction(service.restart),
      RouteKey(method: "POST", path: "/api/switch"): profileAction(service.switchProfile),
      RouteKey(method: "POST", path: "/api/stop-all"): { [self] request in
        _ = try requestObject(request)
        try service.stopAll()
        return try response(service.actionResponse())
      },
      RouteKey(method: "POST", path: "/api/config/profiles-dir"): { [self] request in
        let payload = try requestObject(request)
        return try response(
          service.setProfilesDirectory(try requiredString(payload, key: "profiles_dir")))
      },
      RouteKey(method: "POST", path: "/api/integrations/run"): { [self] request in
        let payload = try requestObject(request)
        try service.runIntegration(
          try requiredString(payload, key: "integration"),
          action: payload["action"] as? String ?? "sync"
        )
        return try response(service.actionResponse())
      },
      RouteKey(method: "POST", path: "/api/benchmark/start"): { [self] request in
        let payload = try requestObject(request)
        let selected = try optionalStrings(payload, key: "profiles")
        _ = try service.benchmarks.start(
          profiles: selected,
          suite: payload["suite"] as? String ?? "quick",
          allowConcurrent: JSONSupport.boolValue(payload["allow_concurrent"]) ?? false,
          keepRunning: JSONSupport.boolValue(payload["keep_running"]) ?? false
        )
        return try response(service.actionResponse())
      },
    ]
  }
}
