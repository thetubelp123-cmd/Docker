import SwiftUI

struct DonationView: View {
    var body: some View {
        UniformCardView(
            title: "Support DockerDoor",
            description: "If you find DockerDoor useful, consider donating. Your support helps keep the project going!",
            buttonTitle: "Support DockerDoor",
            buttonLink: "https://buymeacoffee.com/keplercafe"
        )
    }
}
