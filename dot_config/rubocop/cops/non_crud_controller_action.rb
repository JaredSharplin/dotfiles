# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Personal
      # Flags public controller methods outside the seven REST actions.
      class NonCrudControllerAction < Base
        include VisibilityHelp

        MSG = "`%<action>s` is a custom controller action. Make it a CRUD action on a new " \
          "resource instead — `Cards::ClosuresController#create`, not `CardsController#close`. " \
          "See payaus .claude/skills/code-reviewer/resources/vanilla-rails.md § CRUD Everything."

        REST_ACTIONS = %w[index show new create edit update destroy].freeze
        CONTROLLER_FILE = %r{app/controllers/.*_controller\.rb\z}

        def on_def(node)
          return unless controller_file?
          return unless node.parent_module_name&.end_with?("Controller")
          return if REST_ACTIONS.include?(node.method_name.to_s)
          return unless node_visibility(node) == :public

          add_offense(node, message: format(MSG, action: node.method_name))
        end

        private

        def controller_file?
          CONTROLLER_FILE.match?(processed_source.file_path.to_s)
        end
      end
    end
  end
end
