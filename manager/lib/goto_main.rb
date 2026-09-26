require "open3"

class GotoMain
  BRANCH = "master"

  class << self
    def call
      raise "You have uncommitted changes. Please commit or stash them before going to #{BRANCH}." if dirty?

      run("git", "fetch", "origin")
      run("git", "checkout", BRANCH)
      stdout = run("git", "pull", "--ff-only", "origin", BRANCH)
      message = stdout.to_s.strip
      message = "updated #{BRANCH}" if message.blank?
      puts "#{File.basename(Worktree.root)}: #{message}"
    end

    private

    def dirty?
      run("git", "status", "--porcelain").present?
    end

    def run(*command)
      stdout, stderr, status = Open3.capture3(*command, chdir: Worktree.root)
      return stdout if status.success?

      message = stderr.strip
      message = stdout.strip if message.blank?
      raise "#{command.join(" ")} failed: #{message}"
    end
  end
end
