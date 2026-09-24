cask "dinky" do
  version "2.13.2"
  sha256 "fa0ba88d4e8ffa04dd37c6803e89f3268a188e3632de279f66d4cb7000f8ea34"

  url "https://github.com/heyderekj/dinky/releases/download/v#{version}/Dinky-#{version}.zip"
  name "Dinky"
  desc "Image, video, audio, and PDF compression utility"
  homepage "https://github.com/heyderekj/dinky"

  depends_on macos: :sequoia

  app "Dinky.app"
end
