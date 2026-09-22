import Foundation
import Testing

@Test("R14/R19: installed app declares no tracking, collection, domains, or required-reason APIs")
func privacyManifestMatchesOfflineArchitecture() throws {
  let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
  let data = try Data(contentsOf: url)
  let plist = try #require(
    PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  #expect(plist["NSPrivacyTracking"] as? Bool == false)
  #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
  #expect((plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.isEmpty == true)
  #expect((plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])?.isEmpty == true)
}
