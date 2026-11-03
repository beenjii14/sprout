class Sprout < Formula
  desc "Create cleanly named Git branches straight from Jira tickets"
  homepage "https://beenjii14.github.io/sprout/"
  url "https://github.com/beenjii14/sprout/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "5c83cea4800e06269edbb78e01656a2e1d60d3de7c0d9b01c37b0285ce13a50c"
  license "MIT"
  head "https://github.com/beenjii14/sprout.git", branch: "main"

  depends_on "jq"
  uses_from_macos "curl"
  uses_from_macos "perl"
  uses_from_macos "zsh"

  def install
    pkgshare.install "sprout.plugin.zsh"
    bin.install "install.sh" => "sprout-setup"
    bin.install "uninstall.sh" => "sprout-uninstall"
  end

  def caveats
    <<~EOS
      sprout is a zsh plugin. Load it by running the guided setup:

        sprout-setup

      or add this line to your ~/.zshrc yourself:

        source "#{opt_pkgshare}/sprout.plugin.zsh"

      Then open a new terminal and try: sprout --help
    EOS
  end

  test do
    ENV["SPROUT_CONFIG"] = File::NULL
    ENV["SPROUT_AI"] = "0"
    output = shell_output(
      "zsh -c 'source #{pkgshare}/sprout.plugin.zsh; sprout --dry-run PROJ-1 \"Add login\"'",
    )
    assert_equal "PROJ-1/feat-add-login", output.strip
  end
end
