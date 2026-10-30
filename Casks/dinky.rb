cask "dinky" do
  version "2.17.0"
  sha256 "862d2afeadec32cda774503740d5d5fdd4a172dac237e6c996de59cb74e28d99"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
