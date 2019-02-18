#!/usr/bin/env ruby

require "date"
require "logger"
require "optparse"
require "thread"
require "pry" # for debugging

require_relative "lib/github_client"
require_relative "lib/make_pull_request"

WORK_HOURS = 9..18
DAY_LENGTH = WORK_HOURS.last - WORK_HOURS.first

$logger = Logger.new(STDOUT)
$logger.level = Logger::DEBUG

$opts = {
  ludicrous_mode: false,
  repo: nil,
  token: nil,
  api_host: "https://api.github.com/",
  daily_prs: 35..45,
  merge_rate: 0.8,
  files_per_pr: 1..20,
  commits_per_pr: 1..8,
  comments_per_pr: 0..10,
}

OptionParser.new do |opts|
  opts.banner = "Usage: ./monkey.rb --repo=/dir --token=GH_TOKEN"

  opts.on("-rPATH", "--repo=PATH", "repo directory") do |v|
    $opts[:repo] = v
  end

  opts.on("-tTOKEN", "--token=TOKEN", "auth token") do |v|
    $opts[:token] = v
  end

  opts.on("--api_host=URL", "Github API Host") do |v|
    $opts[:api_host] = v
  end

  # just churn out PRs as fast as possible in series, no time sensitivity
  opts.on("--ludicrous", "Ludicrous mode") do |v|
    $opts[:ludicrous_mode] = true
  end
end.parse!

if $opts.fetch(:repo).nil? || $opts.fetch(:token).nil?
  raise ArgumentError, "repo and token are required args"
end

$repo_lock = Mutex.new # so multiple threads can work on multiple PRs at the same time

Dir.chdir($opts.fetch(:repo))
$logger.debug "Current directory is #{Dir.pwd}"

def schedule_days_prs
  pr_count = $opts.fetch(:daily_prs).to_a.sample
  # scale pr count if script is started in middle of day
  day_pct_left = (DAY_LENGTH - (Time.now.hour - WORK_HOURS.first)).to_f / DAY_LENGTH
  pr_count = (pr_count * day_pct_left).round

  $logger.debug "[main] Going to generate #{pr_count} pull requests on #{Date.today}"
  pr_count.times { |idx| schedule_pr(idx) }
end

def end_of_day
  now = Time.now
  Time.new(now.year, now.month, now.day, WORK_HOURS.last, 0, 0)
end

def schedule_pr(idx)
  secs_left_in_day = end_of_day - Time.now

  Thread.new do
    MakePullRequest.new(
      index: idx,
      duration_secs: rand(secs_left_in_day),
      will_merge: rand <= $opts.fetch(:merge_rate),
      commit_count: $opts.fetch(:commits_per_pr).to_a.sample,
      comment_count: $opts.fetch(:comments_per_pr).to_a.sample,
      files_count: $opts.fetch(:files_per_pr).to_a.sample,
    ).run
  end
end

def simulate_team
  while true
    schedule_days_prs

    now = Time.now
    next_morning = Time.new(
      now.year,
      now.month,
      now.day + 1,
      WORK_HOURS.first,
      0,
      0,
    )
    sleep_time = (next_morning - now).round
    $logger.info "[main] sleeping #{sleep_time} seconds until #{next_morning}"
    sleep sleep_time
  end
end

def run_ludicrous_mode
  idx = 0
  while true
    MakePullRequest.new(
      index: idx,
      duration_secs: 0,
      will_merge: rand <= $opts.fetch(:merge_rate),
      commit_count: $opts.fetch(:commits_per_pr).to_a.sample,
      comment_count: $opts.fetch(:comments_per_pr).to_a.sample,
      files_count: $opts.fetch(:files_per_pr).to_a.sample,
    ).run
    idx += 1
  end
end

if $opts.fetch(:ludicrous_mode)
  run_ludicrous_mode
else
  simulate_team
end
