cask "dinky" do
  version "2.12.0"
  sha256 "35bdf4bc9bcf8f3fc84903b74f9159cd1a9964a4ef13d33d041af424c9fb3450"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
