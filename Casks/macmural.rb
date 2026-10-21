cask "macmural" do
  version "1.5.0"
  sha256 "d3ff3849f78ce14cd0fa19e5d105b037389094c2784bd288df351db27867b5fc"

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
