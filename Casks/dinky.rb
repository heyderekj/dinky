cask "dinky" do
  version "2.14.0"
  sha256 "cef101d29262c9e4d44b270d9c2a70e52ea00119fb7bbe6ae82e835adcf43ca8"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
