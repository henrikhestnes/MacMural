cask "macmural" do
  version "1.5.2"
  sha256 "c53509485c0364169fabaed230a2eaa40a0386ab655e3e3f716c47945946ebe4"

  url "https://github.com/henrikhestnes/MacMural/releases/download/v#{version}/MacMural.zip"
  name "MacMural"
  desc "Draw arrows, rectangles, and fading laser trails over your screen"
  homepage "https://github.com/henrikhestnes/MacMural"

  depends_on macos: :ventura

  app "MacMural.app"

  uninstall quit: "io.macmural.app"

  zap trash: "~/Library/Preferences/io.macmural.app.plist"

  caveats <<~EOS
    This build is signed with a self-signed certificate and has not been notarized by Apple.
  EOS
end
