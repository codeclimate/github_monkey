require "net/http"
require "json"

class GithubClient
  attr_reader :token, :repo_slug

  MAX_MERGE_ATTEMPTS = 5

  RequestError = Class.new(StandardError)

  def initialize(token:, repo_slug:)
    @token = token
    @repo_slug = repo_slug
  end

  def each_open_pull_request
    next_page_url = request_uri("/repos/#{repo_slug}/pulls")

    while next_page_url
      puts "processing #{next_page_url}"
      req = Net::HTTP::Get.new(next_page_url)
      add_headers(req)

      res = make_request(req)
      prs = JSON.parse(res.body)

      prs.each do |pr|
        yield pr
      end

      if res["link"] && res["link"].include?('rel="next"')
        links = res["link"].split(",")
        next_link = links.find { |l| l.include?('rel="next"') }
        uri = next_link.match(%r{<(.+)>})[1]
        next_page_url = URI.parse(uri)
      else
        next_page_url = nil
      end
    end
  end

  def open_pull_request(branch:, title:, body:)
    path = "repos/#{repo_slug}/pulls"
    body = {
      base: "master",
      body: body,
      head: branch,
      title: title,
    }

    post_body(path, body)
  end

  def comment_pull_request(number:, body:)
    path = "/repos/#{repo_slug}/issues/#{number}/comments"
    body = { body: body }
    post_body(path, body)
  end

  def merge_pull_request(number:)
    path = "/repos/#{repo_slug}/pulls/#{number}/merge"
    uri = request_uri(path)

    req = Net::HTTP::Put.new(uri)
    add_headers(req)

    merged = false
    merge_attempts = 0
    while !merged && merge_attempts <= MAX_MERGE_ATTEMPTS
      merge_attempts += 1
      res = make_request(req)
      if res.code.to_i == 200
        merged = true
      elsif res.code.to_i == 405 # "not mergeable (yet?)"
        # do nothing
      elsif res.code.to_i == 500 # WTF?
        # do nothing
      else
        raise RequestError, "request failed to #{req.uri}: #{res.inspect}"
      end
    end

    if !merged && merge_attempts > MAX_MERGE_ATTEMPTS
      $logger.error("Could not merge PR ##{number}")
    end
  end

  def close_pull_request(number:)
    path = "/repos/#{repo_slug}/pulls/#{number}"
    body = { state: "closed" }
    patch_body(path, body)
  end

  def delete_branch(branch:)
    uri = request_uri("/repos/#{repo_slug}/git/refs/heads/#{branch}")
    req = Net::HTTP::Delete.new(uri)
    add_headers(req)
    make_request(req)
  end

  private

  def request_uri(path)
    full_path = File.join(base_path, path)
    full_path = "/#{full_path}" if full_path[0] != "/"
    uri = base_uri.dup
    uri.path = full_path
    uri
  end

  def add_headers(req)
    req.add_field "Accept", "application/vnd.github.v3+json"
    req.add_field "Authorization", "token #{token}"
    req.add_field "user-agent", "github-monkey/1.0"
  end

  def make_request(req)
    http = Net::HTTP.new(base_uri.host, base_uri.port)
    http.use_ssl = (req.uri.scheme == "https")
    http.request(req)
  end

  def post_body(path, body)
    uri = request_uri(path)

    req = Net::HTTP::Post.new(uri)
    add_headers(req)
    req.body = JSON.pretty_generate(body)

    res = make_request(req)

    if res.code.to_i >= 200 && res.code.to_i < 300
      return JSON.parse(res.body)
    else
      raise RequestError, "request failed to #{req.uri}: #{res.inspect}"
    end
  end

  def patch_body(path, body)
    uri = request_uri(path)

    req = Net::HTTP::Patch.new(uri)
    add_headers(req)
    req.body = JSON.pretty_generate(body)

    res = make_request(req)

    if res.code.to_i >= 200 && res.code.to_i < 300
      return JSON.parse(res.body)
    else
      raise RequestError, "request failed to #{req.uri}: #{res.inspect}"
    end
  end

  def base_uri
    @base_uri ||= URI.parse($opts.fetch(:api_host))
  end

  def base_path
    base_uri.path
  end
end
