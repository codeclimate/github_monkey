# GitHub Monkey

A monkey with access to several typewriters and the GitHub API. More plainly: a
script to generate commit & PR traffic on a GH repo.

## Usage

`./monkey.rb --repo=/dir --token=GH_TOKEN`

This typical usage will run the script and simulate a smallish eng team over the
course of a day, opening pull requests, commenting on them, and merging a
certain percentage of them. It tries to simulate a team by only taking actions
between 9 AM and 6 PM, and spreading out its work between those hours.

### Ludicrous mode

`./monkey.rb --repo=/dir --token=GH_TOKEN --ludicrous`

Ludicrous mode does not take time between actions or restrict itself to a
certain number of PRs a day. It just creates PRs with activity as fast as it can.
