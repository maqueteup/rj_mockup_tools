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
        @selected_entities = []
        @highlight_entities = []
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
          @selected_entities = []
          Sketchup.status_text = "#{@tool_name}: Selecione objetos (Clique para adicionar, Shift+Clique para remover, Enter para aplicar, Esc para cancelar)"
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
        @selected_entities = []
        @highlight_entities = []
      end

      # Mouse move handler - highlight entity under cursor
      def onMouseMove(flags, x, y, view)
        return unless @mode == :selecting

        # Pick entity under cursor
        ph = view.pick_helper
        ph.do_pick(x, y)
        picked = ph.best_picked

        # Clear previous highlight
        old_highlight = @highlight_entities.dup
        @highlight_entities.clear

        # Highlight if valid
        if picked && valid_entity?(picked)
          @highlight_entities << picked
        end

        # Redraw if highlight changed
        if old_highlight != @highlight_entities
          view.invalidate
        end
      end

      # Left mouse button click - select/deselect entity
      def onLButtonDown(flags, x, y, view)
        return unless @mode == :selecting

        # Pick entity
        ph = view.pick_helper
        ph.do_pick(x, y)
        picked = ph.best_picked

        return unless picked && valid_entity?(picked)

        # Check if Shift is pressed (for deselection)
        shift_down = (flags & MK_SHIFT) != 0

        if shift_down
          # Remove from selection
          if @selected_entities.include?(picked)
            @selected_entities.delete(picked)
            puts "#{@tool_name}: Removido da seleção (#{@selected_entities.length} selecionado(s))"
          end
        else
          # Add to selection
          unless @selected_entities.include?(picked)
            @selected_entities << picked
            puts "#{@tool_name}: Adicionado à seleção (#{@selected_entities.length} selecionado(s))"
          end
        end

        update_status_text
        view.invalidate
      end

      # Key down handler - Enter to confirm, Escape to cancel
      def onKeyDown(key, repeat, flags, view)
        case key
        when VK_RETURN, VK_SPACE
          # Enter or Space: confirm selection
          if @mode == :selecting
            if @selected_entities.empty?
              UI.messagebox("Nenhum objeto selecionado.")
            else
              execute_and_finish(@selected_entities)
            end
          end
          return true
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

      # Draw selection feedback
      def draw(view)
        return unless @mode == :selecting

        # Draw selected entities with green outline
        unless @selected_entities.empty?
          view.line_width = 3
          view.drawing_color = [0, 255, 0]  # Green
          @selected_entities.each do |entity|
            next unless entity.valid?
            draw_entity_bounds(view, entity)
          end
        end

        # Draw highlighted entity with yellow outline
        unless @highlight_entities.empty?
          view.line_width = 2
          view.drawing_color = [255, 255, 0]  # Yellow
          @highlight_entities.each do |entity|
            next unless entity.valid?
            draw_entity_bounds(view, entity)
          end
        end
      end

      # Draw bounding box for an entity
      def draw_entity_bounds(view, entity)
        return unless entity.respond_to?(:bounds)

        bounds = entity.bounds
        return if bounds.empty?

        # Get 8 corners of the bounding box
        min = bounds.min
        max = bounds.max

        corners = [
          Geom::Point3d.new(min.x, min.y, min.z),
          Geom::Point3d.new(max.x, min.y, min.z),
          Geom::Point3d.new(max.x, max.y, min.z),
          Geom::Point3d.new(min.x, max.y, min.z),
          Geom::Point3d.new(min.x, min.y, max.z),
          Geom::Point3d.new(max.x, min.y, max.z),
          Geom::Point3d.new(max.x, max.y, max.z),
          Geom::Point3d.new(min.x, max.y, max.z)
        ]

        # Draw bottom face
        view.draw(GL_LINE_LOOP, corners[0], corners[1], corners[2], corners[3])
        # Draw top face
        view.draw(GL_LINE_LOOP, corners[4], corners[5], corners[6], corners[7])
        # Draw vertical edges
        view.draw(GL_LINES, corners[0], corners[4])
        view.draw(GL_LINES, corners[1], corners[5])
        view.draw(GL_LINES, corners[2], corners[6])
        view.draw(GL_LINES, corners[3], corners[7])
      end

      # Update status text with selection count
      def update_status_text
        count = @selected_entities.length
        Sketchup.status_text = "#{@tool_name}: #{count} objeto(s) selecionado(s) (Clique para adicionar, Shift+Clique para remover, Enter para aplicar, Esc para cancelar)"
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
        @cursor_id ||= UI.create_cursor(File.join(__dir__, '..', 'icons', 'cursor_select.png'), 0, 0) rescue nil

        if @cursor_id
          UI.set_cursor(@cursor_id)
        else
          # Fallback to system cursor
          UI.set_cursor(632)  # Arrow with question mark
        end
      end

      # Tool name for menus
      def getExtents
        # This makes the tool camera behave better
        model = Sketchup.active_model
        return model.bounds if model
        return Geom::BoundingBox.new
      end

    end
  end
end
