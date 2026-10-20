cask "macmural" do
  version "1.2.0"
  sha256 "a4857434cf894e5c10446e221a01138baa8077fbf10146b0de6f42abef9f8b11"

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
