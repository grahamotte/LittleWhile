require_relative "../test_helper"

class GitRepoPatchTest < Minitest::Test
  def test_skips_blank_repositories
    github = ENV["GITHUB_REPO"]
    ENV["GITHUB_REPO"] = ""
    GitRepoPatch.always
  ensure
    ENV["GITHUB_REPO"] = github
  end

  def test_pushes_configured_repository
    github = ENV["GITHUB_REPO"]
    ENV["GITHUB_REPO"] = "git@github.com:example/app.git"
    Cmd.expects(:local).with(includes("git remote remove origin")).raises("missing")
    Cmd.expects(:local).with(includes("git remote add origin git@github.com:example/app.git"))
    Cmd.expects(:local).with("git config remote.origin.gh-resolved base")
    Cmd.expects(:local).with(includes("git push origin master"))

    GitRepoPatch.always
  ensure
    ENV["GITHUB_REPO"] = github
  end
end
