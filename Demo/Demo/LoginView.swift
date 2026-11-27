import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var remember = false
    @State private var status = "idle"
    private let fruits = ["Apple", "Pear"]

    var body: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
            SecureField("Password", text: $password)
            Toggle("Remember me", isOn: $remember)
            Button("Sign In") { status = "signed-in" }
                .buttonStyle(.borderedProminent)
            Button { status = "help" } label: { Text("Help") }
            Button("Keep my ID") {}.accessibilityIdentifier("custom.keep")
            Text(status).accessibilityIdentifier("status")
            Text("\(#line)|\(#filePath)").accessibilityIdentifier("sourceProbe")
            ForEach(fruits, id: \.self) { fruit in
                HStack {
                    Text(fruit)
                    Button("Remove") { status = "removed-\(fruit)" }
                }
            }
        }
        .padding()
    }
}
