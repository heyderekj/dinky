cask "dinky" do
  version "2.10.0"
  sha256 "b53007480609c58b5bc1e9871f58167d48871b802946f6ed054b40ce11542e47"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: ">= :sequoia"

  app "Dinky.app"
end
