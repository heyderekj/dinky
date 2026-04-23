cask "dinky" do
  version "2.7.11"
  sha256 "00092a7044b8d4a102cc75d4de115937cb2f13ccb363de7710aea2b9f4ef8582"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: ">= :sequoia"

  app "Dinky.app"
end
