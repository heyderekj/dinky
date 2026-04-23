cask "dinky" do
  version "2.7.10"
  sha256 "ed4846d766adeb98ff8fda7ff468acff76d7f259feb0c3155bbbbb37895f157a"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: ">= :sequoia"

  app "Dinky.app"
end
