cask "dinky" do
  version "2.16.0"
  sha256 "ec12d867e753b951a8f711c238647d72ca2b808bd387164b2d8c1266b67d3868"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
