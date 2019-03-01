#!/usr/bin/env ruby

require "optparse"
require "pry" # for debugging

require_relative "lib/github_client"

$opts = {
  repo: nil,
  token: nil,
  api_host: "https://api.github.com/",
}

OptionParser.new do |opts|
  opts.banner = "Usage: ./close_open_prs.rb --repo=/dir --token=GH_TOKEN"

  opts.on("-rPATH", "--repo=PATH", "repo directory") do |v|
    $opts[:repo] = v
  end

  opts.on("-tTOKEN", "--token=TOKEN", "auth token") do |v|
    $opts[:token] = v
  end

  opts.on("--api_host=URL", "Github API Host") do |v|
    $opts[:api_host] = v
  end
end.parse!

Dir.chdir($opts.fetch(:repo))
repo_slug = URI.parse(`git remote get-url origin`.strip).path.gsub(%r{^/}, "").gsub(%r{\.git$}, "")
api_client = GithubClient.new(
  token: $opts.fetch(:token),
  repo_slug: repo_slug,
)

api_client.each_open_pull_request do |pr|
  api_client.close_pull_request(number: pr.fetch("number"))
end
