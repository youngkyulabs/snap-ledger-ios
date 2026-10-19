import Foundation
import FoundationModels

@main
struct Probe {
    static func main() async {
        let m = SystemLanguageModel.default
        print("on-device availability:", m.availability)
        print("variant:", m.variant.displayName, "core3?", m.variant == .core3, "coreAdvanced3?", m.variant == .coreAdvanced3)
        print("contextSize:", m.contextSize)
        let caps = m.capabilities
        print("caps vision:", caps.contains(.vision), "guided:", caps.contains(.guidedGeneration), "reasoning:", caps.contains(.reasoning), "tools:", caps.contains(.toolCalling))
        print("supports ko_KR:", m.supportsLocale(Locale(identifier: "ko_KR")))
        let pcc = PrivateCloudComputeLanguageModel()
        print("PCC availability:", pcc.availability)
        let pc = pcc.capabilities
        print("PCC caps vision:", pc.contains(.vision), "guided:", pc.contains(.guidedGeneration), "reasoning:", pc.contains(.reasoning), "tools:", pc.contains(.toolCalling))
        print("PCC quota limitReached:", pcc.quotaUsage.isLimitReached, "reset:", String(describing: pcc.quotaUsage.resetDate))
        do { print("PCC contextSize:", try await pcc.contextSize) } catch { print("PCC contextSize error:", error) }
        do { print("PCC supports ko:", try await pcc.supportsLocale(Locale(identifier: "ko_KR"))) } catch { print("PCC locale error:", error) }
    }
}
