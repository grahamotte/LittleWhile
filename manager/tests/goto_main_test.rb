require_relative "test_helper"

class GotoMainTest < Minitest::Test
  def test_fetches_checks_out_and_fast_forwards_master
    commands = stub_git(
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "Updating abc..def\nFast-forward\n", "", git_ok ],
    )

    output, = capture_io { GotoMain.call }

    assert_equal [
      [ "git", "status", "--porcelain" ],
      [ "git", "fetch", "origin" ],
      [ "git", "checkout", "master" ],
      [ "git", "pull", "--ff-only", "origin", "master" ],
    ], commands.map { |command| command[:args] }
    assert commands.all? { |command| command[:directory] == Worktree.root }
    assert_equal "#{File.basename(Worktree.root)}: Updating abc..def\nFast-forward", output.strip
  end

  def test_prints_updated_master_when_pull_output_is_blank
    stub_git(
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "", "", git_ok ],
    )

    output, = capture_io { GotoMain.call }

    assert_equal "#{File.basename(Worktree.root)}: updated master\n", output
  end

  def test_raises_on_dirty_worktree_without_fetching
    commands = stub_git([ " M mise.toml\n", "", git_ok ])

    error = assert_raises(RuntimeError) { capture_io { GotoMain.call } }

    assert_equal "You have uncommitted changes. Please commit or stash them before going to master.", error.message
    assert_equal [ [ "git", "status", "--porcelain" ] ], commands.map { |command| command[:args] }
  end

  def test_raises_when_fetch_fails
    stub_git(
      [ "", "", git_ok ],
      [ "", "network error", git_bad ],
    )

    error = assert_raises(RuntimeError) { capture_io { GotoMain.call } }

    assert_equal "git fetch origin failed: network error", error.message
  end

  def test_raises_when_checkout_fails
    stub_git(
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "", "conflict", git_bad ],
    )

    error = assert_raises(RuntimeError) { capture_io { GotoMain.call } }

    assert_equal "git checkout master failed: conflict", error.message
  end

  def test_raises_when_pull_fails
    stub_git(
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "", "", git_ok ],
      [ "", "not possible to fast-forward", git_bad ],
    )

    error = assert_raises(RuntimeError) { capture_io { GotoMain.call } }

    assert_equal "git pull --ff-only origin master failed: not possible to fast-forward", error.message
  end

  def test_uses_stdout_when_stderr_is_blank
    stub_git(
      [ "", "", git_ok ],
      [ "failed", "", git_bad ],
    )

    error = assert_raises(RuntimeError) { capture_io { GotoMain.call } }

    assert_equal "git fetch origin failed: failed", error.message
  end

  private

  def stub_git(*results)
    commands = []
    Open3.stubs(:capture3).with do |*args, **kwargs|
      commands << { args:, directory: kwargs[:chdir] }
      true
    end.returns(*results)
    commands
  end

  def git_ok
    @git_ok ||= Object.new.tap { |object| object.define_singleton_method(:success?) { true } }
  end

  def git_bad
    @git_bad ||= Object.new.tap { |object| object.define_singleton_method(:success?) { false } }
  end
end
