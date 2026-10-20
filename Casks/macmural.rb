cask "macmural" do
  version "1.4.0"
  sha256 "3982799f6c8b71b63227ded83af2099faab911be846fa9e4ecbfe09ab07afeb2"

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
