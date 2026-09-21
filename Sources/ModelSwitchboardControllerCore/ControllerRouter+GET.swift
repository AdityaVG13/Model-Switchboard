import Foundation

extension ControllerRouter {
  var getRoutes: [RouteKey: Route] {
    [
      RouteKey(method: "GET", path: "/api/status"): { [self] _ in
        let payload = try service.statusPayload()
        try? service.writeStatusCache(payload)
        return try response(payload)
      },
      RouteKey(method: "GET", path: "/api/doctor"): { [self] _ in
        try response(service.doctor.report())
      },
      RouteKey(method: "GET", path: "/api/benchmark/status"): { [self] _ in
        try response(service.benchmarks.status())
      },
      RouteKey(method: "GET", path: "/api/integrations"): { [self] _ in
        try json([
          "integrations": try jsonObjects(service.integrationStatus()),
          "profiles_dir": service.configuration.profilesDirectory.path,
          "controller_root": service.configuration.root.path,
        ])
      },
    ]
  }
}
