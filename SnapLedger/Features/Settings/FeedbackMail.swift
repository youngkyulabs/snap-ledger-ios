import Foundation

enum FeedbackMail {
    static let subject = "찰칵가계부 피드백"

    static func body(
        appVersion: String?,
        buildNumber: String?,
        systemVersion: String,
        deviceModel: String
    ) -> String {
        let version = (appVersion?.isEmpty == false ? appVersion : nil) ?? "?"
        let build = (buildNumber?.isEmpty == false ? buildNumber : nil) ?? "?"
        return """


        ---
        찰칵가계부 \(version) (\(build))
        iOS \(systemVersion) · \(deviceModel)
        """
    }
}
