import SwiftUI

struct DonationView: View {
    var body: some View {
        UniformCardView(
            title: "Support Docker",
            description: "If you find Docker useful, consider donating. Your support helps keep the project going!",
            buttonTitle: "Support Docker",
            buttonLink: "https://buymeacoffee.com/keplercafe"
        )
    }
}
