cask "dinky" do
  version "2.15.0"
  sha256 "080177b810d39e34f04410b1c03cb967c2974ebe99e0600fb9fb1a0a8b2e0d84"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
