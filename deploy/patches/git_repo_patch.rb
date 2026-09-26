class GitRepoPatch < BasePatch
  class << self
    def always
      push_to("origin", Constants.github_repo)
    end

    private

    def push_to(remote, repo)
      return if repo.to_s.strip.empty?

      Cmd.local("GIT_SSH_COMMAND='ssh -i #{Constants.ssh_key_path}' git remote remove #{remote}") rescue StandardError
      Cmd.local("GIT_SSH_COMMAND='ssh -i #{Constants.ssh_key_path}' git remote add #{remote} #{repo}")
      Cmd.local("git config remote.#{remote}.gh-resolved base")
      Cmd.local("GIT_SSH_COMMAND='ssh -i #{Constants.ssh_key_path}' git push #{remote} master")
    end
  end
end
