cask "dinky" do
  version "2.13.0"
  sha256 "ddf83f08ddf1fa93e45a042189715688a6789d00c88ea9b1f66e16181cd121d7"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
