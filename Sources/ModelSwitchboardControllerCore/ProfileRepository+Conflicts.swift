import Foundation

extension ProfileRepository {
  public func conflicts(in profiles: [String: ControllerProfile]) -> [String: (String, [String])] {
    let groups = Dictionary(
      grouping: profiles.values.compactMap { profile in
        profile.endpointIdentity.map { ($0, profile.name) }
      }, by: \.0)
    var result: [String: (String, [String])] = [:]
    for (endpoint, entries) in groups where entries.count > 1 {
      let names = entries.map(\.1).sorted()
      for name in names {
        result[name] = (endpoint, names.filter { $0 != name })
      }
    }
    return result
  }

  public func ensureUnique(_ name: String, action: String, profiles: [String: ControllerProfile])
    throws
  {
    guard let conflict = conflicts(in: profiles)[name] else { return }
    throw ControllerError.profileConflict(
      "Cannot \(action) \(name): endpoint \(conflict.0) is also configured for \(conflict.1.joined(separator: ", "))."
    )
  }
}
