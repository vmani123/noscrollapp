import ManagedSettings
import ManagedSettingsUI
import UIKit

final class BlockShield: ShieldConfigurationDataSource {
    private func shield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.06, green: 0.10, blue: 0.09, alpha: 1),
            icon: UIImage(systemName: "lock.shield"),
            title: .init(text: "This block is still active.", color: .white),
            subtitle: .init(text: "Access returns when your committed block ends.", color: .lightGray),
            primaryButtonLabel: .init(text: "Close", color: .white),
            primaryButtonBackgroundColor: .systemTeal,
            secondaryButtonLabel: nil)
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { shield() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { shield() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { shield() }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { shield() }
}
