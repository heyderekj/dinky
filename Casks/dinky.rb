cask "dinky" do
  version "2.13.1"
  sha256 "c000501016182953d4685b5eac2687ac655450916fac89a3ff03595f8d546152"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
