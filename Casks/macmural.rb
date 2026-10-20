cask "macmural" do
  version "1.3.0"
  sha256 "41e647c7d8b7bc220e7b00693fc560b40e52fc38d687ee135d73bd13d544b0bc"

  url "https://github.com/henrikhestnes/MacMural/releases/download/v#{version}/MacMural.zip"
  name "MacMural"
  desc "Draw arrows, rectangles, and fading laser trails over your screen"
  homepage "https://github.com/henrikhestnes/MacMural"

  depends_on macos: :ventura

  app "MacMural.app"

  uninstall quit: "io.macmural.app"

  zap trash: "~/Library/Preferences/io.macmural.app.plist"

  caveats <<~EOS
    This build is ad-hoc signed and has not been notarized by Apple.
  EOS
end
