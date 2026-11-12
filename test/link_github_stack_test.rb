#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

load File.expand_path("../dot_local/bin/executable_link-github-stack", __dir__)

class LinearStackBranchesTest < Minitest::Test
  def test_two_branch_stack_from_the_top
    branches = LinkGithubStack.linear_stack_branches(
      branch: "child", parent_by_branch: {"parent" => "master", "child" => "parent"}, main_branch: "master"
    )

    assert_equal %w[parent child], branches
  end

  def test_two_branch_stack_from_the_bottom
    branches = LinkGithubStack.linear_stack_branches(
      branch: "parent", parent_by_branch: {"parent" => "master", "child" => "parent"}, main_branch: "master"
    )

    assert_equal %w[parent child], branches
  end

  def test_three_branch_stack_from_the_middle
    branches = LinkGithubStack.linear_stack_branches(
      branch: "middle",
      parent_by_branch: {"bottom" => "master", "middle" => "bottom", "top" => "middle"},
      main_branch: "master"
    )

    assert_equal %w[bottom middle top], branches
  end

  def test_branch_on_main_without_children_is_alone
    branches = LinkGithubStack.linear_stack_branches(
      branch: "solo", parent_by_branch: {"solo" => "master", "other" => "master"}, main_branch: "master"
    )

    assert_equal %w[solo], branches
  end

  def test_fork_from_the_parent_stops_at_the_parent
    branches = LinkGithubStack.linear_stack_branches(
      branch: "parent",
      parent_by_branch: {"parent" => "master", "first-child" => "parent", "second-child" => "parent"},
      main_branch: "master"
    )

    assert_equal %w[parent], branches
  end

  def test_fork_from_one_child_follows_only_that_child
    branches = LinkGithubStack.linear_stack_branches(
      branch: "second-child",
      parent_by_branch: {
        "parent" => "master", "first-child" => "parent", "second-child" => "parent", "grandchild" => "second-child"
      },
      main_branch: "master"
    )

    assert_equal %w[parent second-child grandchild], branches
  end
end

class StackedPullRequestNumbersTest < Minitest::Test
  def test_every_branch_has_an_open_pull_request
    numbers = LinkGithubStack.stacked_pull_request_numbers(
      branches: %w[bottom middle top],
      open_pull_request_number_by_branch: {"bottom" => 10, "middle" => 11, "top" => 12},
      branch: "middle"
    )

    assert_equal [10, 11, 12], numbers
  end

  def test_bottom_branch_without_an_open_pull_request_is_left_out
    numbers = LinkGithubStack.stacked_pull_request_numbers(
      branches: %w[bottom middle top],
      open_pull_request_number_by_branch: {"middle" => 11, "top" => 12},
      branch: "top"
    )

    assert_equal [11, 12], numbers
  end

  def test_gap_above_the_current_branch_cuts_the_run
    numbers = LinkGithubStack.stacked_pull_request_numbers(
      branches: %w[bottom middle gap top],
      open_pull_request_number_by_branch: {"bottom" => 10, "middle" => 11, "top" => 13},
      branch: "middle"
    )

    assert_equal [10, 11], numbers
  end

  def test_single_open_pull_request_is_not_a_stack
    numbers = LinkGithubStack.stacked_pull_request_numbers(
      branches: %w[bottom top],
      open_pull_request_number_by_branch: {"top" => 12},
      branch: "top"
    )

    assert_equal [], numbers
  end

  def test_current_branch_without_an_open_pull_request_is_not_a_stack
    numbers = LinkGithubStack.stacked_pull_request_numbers(
      branches: %w[bottom middle top],
      open_pull_request_number_by_branch: {"bottom" => 10, "top" => 12},
      branch: "middle"
    )

    assert_equal [], numbers
  end
end
