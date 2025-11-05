# encoding: UTF-8
# Base class for interactive selection tools

require 'sketchup.rb'

module Rjv
  module MockupTools
    # Base class for tools that support interactive selection
    # Subclasses should implement: execute_on_selection(entities, model)
    class InteractiveSelectionTool

      def initialize(tool_name, filter_proc = nil)
        @tool_name = tool_name
        @filter_proc = filter_proc || default_filter
        @cursor_id = nil
        reset_state
      end

      # Override this in subclasses to define what entities are valid
      def default_filter
        ->(entity) {
          entity.valid? &&
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
        }
      end

      # Override this in subclasses to perform the actual operation
      def execute_on_selection(entities, model)
        raise NotImplementedError, "Subclasses must implement execute_on_selection"
      end

      # Check if entity is valid for this tool
      def valid_entity?(entity)
        @filter_proc.call(entity)
      end

      # Activate the tool
      def activate
        @model = Sketchup.active_model
        @view = @model.active_view

        # Check for pre-selection
        preselection = @model.selection.to_a.select { |e| valid_entity?(e) }

        if preselection.empty?
          # No valid pre-selection, enter interactive mode
          @mode = :selecting
          Sketchup.status_text = "#{@tool_name}: Clique no objeto para aplicar (Esc para cancelar)"
          puts "#{@tool_name}: Modo de seleção interativa ativado"
        else
          # Has pre-selection, execute immediately
          @mode = :completed
          puts "#{@tool_name}: Usando seleção prévia (#{preselection.length} objeto(s))"
          execute_and_finish(preselection)
        end

        @view.invalidate
      end

      # Deactivate the tool
      def deactivate(view)
        view.invalidate
        reset_state
      end

      # Reset tool state
      def reset_state
        @mode = :idle
      end

      # Left mouse button click - execute on entity immediately
      def onLButtonDown(flags, x, y, view)
        return unless @mode == :selecting

        # Pick entity
        ph = view.pick_helper
        ph.do_pick(x, y)
        picked = ph.best_picked

        return unless picked && valid_entity?(picked)

        # Execute immediately on this entity
        puts "#{@tool_name}: Executando em #{picked.is_a?(Sketchup::ComponentInstance) ? picked.definition.name : picked.name}"
        execute_and_finish([picked])
      end

      # Key down handler - Escape to cancel
      def onKeyDown(key, repeat, flags, view)
        # SketchUp key codes
        VK_ESCAPE = 27

        case key
        when VK_ESCAPE
          # Escape: cancel
          if @mode == :selecting
            puts "#{@tool_name}: Cancelado pelo usuário"
            @model.select_tool(nil)
          end
          return true
        end

        false
      end

      # Execute the operation and finish
      def execute_and_finish(entities)
        @mode = :completed

        # Execute the subclass operation
        begin
          execute_on_selection(entities, @model)
        rescue => e
          UI.messagebox("Erro ao executar #{@tool_name}: #{e.message}")
          puts "Erro: #{e.message}"
          puts e.backtrace.first(5).join("\n")
        end

        # Return to selection tool
        @model.select_tool(nil)
      end

      # Cursor support
      def onSetCursor
        # Use standard cursor
        UI.set_cursor(0)  # Arrow cursor
      end

      # Tool extents
      def getExtents
        model = Sketchup.active_model
        return model.bounds if model
        return Geom::BoundingBox.new
      end

    end
  end
end
