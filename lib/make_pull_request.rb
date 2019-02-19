require "open3"
require "securerandom"
require "uri"

class MakePullRequest
  attr_reader :prefix, :index, :duration_secs, :will_merge, :commit_count, :comment_count, :files_count, :branch_name, :action_interval, :pr_number

  CommandError = Class.new(StandardError)

  LOREM_IPSUM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.".freeze

  def initialize(index:, duration_secs:, will_merge:, commit_count:, comment_count:, files_count:)
    @prefix = SecureRandom.hex(4)
    @index = index
    @duration_secs = duration_secs
    @will_merge = will_merge
    @commit_count = commit_count
    @comment_count = comment_count
    @files_count = files_count

    @branch_name = "monkey/#{Date.today}-#{prefix}-pr-#{index}"
    @action_interval =
      if duration_secs.zero?
        0
      else
        action_count = commit_count + comment_count + 1 # 1 for pr open
        action_count += 1 if will_merge
        duration.to_f / action_count
      end
  end

  def run
    $logger.info "#{log_tag} Simulating PR with comments=#{commit_count}, comments=#{comment_count}, will_merge=#{will_merge.inspect}"

    create_branch

    write_commit
    log_next_action_time
    sleep action_interval

    open_pull_request
    log_next_action_time
    sleep action_interval

    commits_remaining = (commit_count - 1).times.map { :commit }
    comments_remaining = comment_count.times.map { :comment }
    actions_remaining = (commits_remaining + comments_remaining).shuffle
    while actions_remaining.any?
      case (action = actions_remaining.pop)
      when :comment
        write_comment
      when :commit
        write_commit
      else
        raise "invalid action #{action}"
      end
      log_next_action_time
      sleep action_interval
    end

    if will_merge
      $logger.info "#{log_tag} Merging PR"
      api_client.merge_pull_request(number: pr_number)
    else
      $logger.info "#{log_tag} Closing PR"
      api_client.close_pull_request(number: pr_number)
    end
  end

  def create_branch
    $logger.info "#{log_tag} Creating branch #{branch_name}"
    $repo_lock.synchronize {
      run_cmd("git branch #{branch_name} master")
    }
  end

  def write_commit
    $logger.info "#{log_tag} Writing commit"
    $repo_lock.synchronize {
      run_cmd("git checkout #{branch_name}")
      files_count.times do |file_idx|
        path = "#{branch_name.gsub("/", "-")}-file-#{file_idx}"
        File.open(path, "w") { |fh| fh.write(commit_contents) }
        run_cmd("git add #{path}")
      end

      run_cmd("git commit -m '#{commit_message}'")
      run_cmd("git push origin #{branch_name}")
    }
  rescue CommandError => ex
    if /working tree clean/ =~ ex.message
      $logger.warn "#{log_tag} commit randomly happend to not change repo at all"
    else
      raise ex
    end
  end

  def open_pull_request
    $logger.info "#{log_tag} Opening PR"
    @pr_number ||= api_client.open_pull_request(
      body: pr_body,
      branch: branch_name,
      title: pr_title,
    ).fetch("number")
  end

  def write_comment
    $logger.info "#{log_tag} Writing comment"
    api_client.comment_pull_request(number: pr_number, body: comment_body)
  end

  def log_next_action_time
    t = Time.now + action_interval
    $logger.info "#{log_tag} Next action will happen at #{t}"
  end

  def log_tag
    "[#{branch_name}]"
  end

  def commit_file_name
    "#{branch_name}.rb"
  end

  def commit_contents
    lines = RandomGaussian.from_range(1..100)

    lines.times.map do |idx|
      "puts \"#{idx}\""
    end.join("\n")
  end

  def commit_message
    "monkey commit message for #{branch_name} at #{Time.now}"
  end

  def pr_title
    branch_name
  end

  def pr_body
    LOREM_IPSUM
  end

  def comment_body
    LOREM_IPSUM
  end

  def api_client
    @api_client ||= GithubClient.new(
      token: $opts.fetch(:token),
      repo_slug: repo_slug,
    )
  end

  def repo_slug
    URI.parse(`git remote get-url origin`.strip).path.gsub(%r{^/}, "").gsub(%r{\.git$}, "")
  end

  def run_cmd(cmd)
    Open3.popen3(cmd) do |_stdin, stdout, stderr, wait_thr|
      exit_code = wait_thr.value.exitstatus

      if exit_code > 0
        raise CommandError, "`#{cmd}` exited with #{exit_code}: stdout=#{stdout.read} stderr=#{stderr.read}"
      end
    end
  end
end
