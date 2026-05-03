cask "dinky" do
  version "2.11.2"
  sha256 "396b69d0c041a06125cdd12793be5baa8b133e3c7cd7b26f23691aaba7f392ae"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: ">= :sequoia"

  app "Dinky.app"
end
