# encoding: UTF-8
# Mockup Tools RJV - Rotate 90 Local Axis / Selection Center

require 'sketchup.rb'
require_relative 'interactive_selection_tool'

module Rjv
  module MockupTools
    module RotateLocalAxisSelectionCenter

      # --- Constantes ---
      ROTATION_ANGLE = 90.degrees
      GLOBAL_X_AXIS = Geom::Vector3d.new(1, 0, 0).freeze
      GLOBAL_Y_AXIS = Geom::Vector3d.new(0, 1, 0).freeze
      GLOBAL_Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze

      # Interactive tool for X rotation (continuous mode)
      class RotateXTool
        VK_ESCAPE = 27

        def initialize
          @axis = :x
          @axis_color = 'red'
          @last_clicked = []
        end

        def activate
          @model = Sketchup.active_model
          @view = @model.active_view
          Sketchup.status_text = "Rotação X: Clique nos objetos (Shift = global, Esc = sair)"
          puts "Rotação X contínua ativada"
        end

        def deactivate(view)
          view.invalidate
        end

        def onLButtonDown(flags, x, y, view)
          ph = view.pick_helper
          ph.do_pick(x, y)
          picked = ph.best_picked

          return unless picked
          return unless picked.is_a?(Sketchup::Group) || picked.is_a?(Sketchup::ComponentInstance)

          # Executa rotação
          RotateLocalAxisSelectionCenter.perform_rotation_x([picked], @model)

          # Marca como último clicado para feedback visual
          @last_clicked = [picked]
          @view.invalidate

          # Limpa o feedback após 0.3s
          UI.start_timer(0.3, false) do
            @last_clicked = []
            @view.invalidate if @view
          end
        end

        def onKeyDown(key, repeat, flags, view)
          if key == VK_ESCAPE
            puts "Rotação X: Cancelado"
            @model.select_tool(nil)
            return true
          end
          false
        end

        def draw(view)
          # Desenha círculo vermelho no centro do último objeto clicado
          return if @last_clicked.empty?

          @last_clicked.each do |entity|
            next unless entity.valid?

            bounds = entity.bounds
            center = bounds.center

            # Desenha círculo grande vermelho no plano YZ
            draw_circle_x(view, center, 100, @axis_color)
          end
        end

        def draw_circle_x(view, center, radius, color)
          # Círculo no plano YZ (perpendicular ao eixo X)
          points = []
          segments = 36
          segments.times do |i|
            angle = (i.to_f / segments) * Math::PI * 2
            offset = Geom::Vector3d.new(0, Math.cos(angle) * radius, Math.sin(angle) * radius)
            points << center.offset(offset)
          end
          points << points.first

          view.line_width = 4
          view.drawing_color = color
          view.draw(GL_LINE_STRIP, points)

          # Seta indicando rotação +90°
          arrow_angle = Math::PI / 2
          arrow_point = center.offset(Geom::Vector3d.new(0, Math.cos(arrow_angle) * radius, Math.sin(arrow_angle) * radius))
          arrow_head1 = arrow_point.offset(Geom::Vector3d.new(0, -15, 10))
          arrow_head2 = arrow_point.offset(Geom::Vector3d.new(15, 0, 10))
          view.line_width = 3
          view.draw(GL_LINES, [arrow_point, arrow_head1, arrow_point, arrow_head2])
        end

        def onSetCursor
          UI.set_cursor(0)
        end
      end

      # Interactive tool for Y rotation (continuous mode)
      class RotateYTool
        VK_ESCAPE = 27

        def initialize
          @axis = :y
          @axis_color = 'green'
          @last_clicked = []
        end

        def activate
          @model = Sketchup.active_model
          @view = @model.active_view
          Sketchup.status_text = "Rotação Y: Clique nos objetos (Shift = global, Esc = sair)"
          puts "Rotação Y contínua ativada"
        end

        def deactivate(view)
          view.invalidate
        end

        def onLButtonDown(flags, x, y, view)
          ph = view.pick_helper
          ph.do_pick(x, y)
          picked = ph.best_picked

          return unless picked
          return unless picked.is_a?(Sketchup::Group) || picked.is_a?(Sketchup::ComponentInstance)

          # Executa rotação
          RotateLocalAxisSelectionCenter.perform_rotation_y([picked], @model)

          # Marca como último clicado para feedback visual
          @last_clicked = [picked]
          @view.invalidate

          # Limpa o feedback após 0.3s
          UI.start_timer(0.3, false) do
            @last_clicked = []
            @view.invalidate if @view
          end
        end

        def onKeyDown(key, repeat, flags, view)
          if key == VK_ESCAPE
            puts "Rotação Y: Cancelado"
            @model.select_tool(nil)
            return true
          end
          false
        end

        def draw(view)
          # Desenha círculo verde no centro do último objeto clicado
          return if @last_clicked.empty?

          @last_clicked.each do |entity|
            next unless entity.valid?

            bounds = entity.bounds
            center = bounds.center

            # Desenha círculo grande verde no plano XZ
            draw_circle_y(view, center, 100, @axis_color)
          end
        end

        def draw_circle_y(view, center, radius, color)
          # Círculo no plano XZ (perpendicular ao eixo Y)
          points = []
          segments = 36
          segments.times do |i|
            angle = (i.to_f / segments) * Math::PI * 2
            offset = Geom::Vector3d.new(Math.cos(angle) * radius, 0, Math.sin(angle) * radius)
            points << center.offset(offset)
          end
          points << points.first

          view.line_width = 4
          view.drawing_color = color
          view.draw(GL_LINE_STRIP, points)

          # Seta indicando rotação +90°
          arrow_angle = Math::PI / 2
          arrow_point = center.offset(Geom::Vector3d.new(Math.cos(arrow_angle) * radius, 0, Math.sin(arrow_angle) * radius))
          arrow_head1 = arrow_point.offset(Geom::Vector3d.new(-15, 0, 10))
          arrow_head2 = arrow_point.offset(Geom::Vector3d.new(0, 15, 10))
          view.line_width = 3
          view.draw(GL_LINES, [arrow_point, arrow_head1, arrow_point, arrow_head2])
        end

        def onSetCursor
          UI.set_cursor(0)
        end
      end

      # Interactive tool for Z rotation (continuous mode)
      class RotateZTool
        VK_ESCAPE = 27

        def initialize
          @axis = :z
          @axis_color = 'blue'
          @last_clicked = []
        end

        def activate
          @model = Sketchup.active_model
          @view = @model.active_view
          Sketchup.status_text = "Rotação Z: Clique nos objetos (Shift = global, Esc = sair)"
          puts "Rotação Z contínua ativada"
        end

        def deactivate(view)
          view.invalidate
        end

        def onLButtonDown(flags, x, y, view)
          ph = view.pick_helper
          ph.do_pick(x, y)
          picked = ph.best_picked

          return unless picked
          return unless picked.is_a?(Sketchup::Group) || picked.is_a?(Sketchup::ComponentInstance)

          # Executa rotação
          RotateLocalAxisSelectionCenter.perform_rotation_z([picked], @model)

          # Marca como último clicado para feedback visual
          @last_clicked = [picked]
          @view.invalidate

          # Limpa o feedback após 0.3s
          UI.start_timer(0.3, false) do
            @last_clicked = []
            @view.invalidate if @view
          end
        end

        def onKeyDown(key, repeat, flags, view)
          if key == VK_ESCAPE
            puts "Rotação Z: Cancelado"
            @model.select_tool(nil)
            return true
          end
          false
        end

        def draw(view)
          # Desenha círculo azul no centro do último objeto clicado
          return if @last_clicked.empty?

          @last_clicked.each do |entity|
            next unless entity.valid?

            bounds = entity.bounds
            center = bounds.center

            # Desenha círculo grande azul no plano XY
            draw_circle_z(view, center, 100, @axis_color)
          end
        end

        def draw_circle_z(view, center, radius, color)
          # Círculo no plano XY (perpendicular ao eixo Z)
          points = []
          segments = 36
          segments.times do |i|
            angle = (i.to_f / segments) * Math::PI * 2
            offset = Geom::Vector3d.new(Math.cos(angle) * radius, Math.sin(angle) * radius, 0)
            points << center.offset(offset)
          end
          points << points.first

          view.line_width = 4
          view.drawing_color = color
          view.draw(GL_LINE_STRIP, points)

          # Seta indicando rotação +90°
          arrow_angle = 0  # Posição à direita do círculo
          arrow_point = center.offset(Geom::Vector3d.new(Math.cos(arrow_angle) * radius, Math.sin(arrow_angle) * radius, 0))
          arrow_head1 = arrow_point.offset(Geom::Vector3d.new(10, -15, 0))
          arrow_head2 = arrow_point.offset(Geom::Vector3d.new(10, 0, 15))
          view.line_width = 3
          view.draw(GL_LINES, [arrow_point, arrow_head1, arrow_point, arrow_head2])
        end

        def onSetCursor
          UI.set_cursor(0)
        end
      end

      # --- Método Auxiliar Comum ---
      private_class_method def self.get_selection_and_center(model)
        selection = model.selection.to_a.select do |e|
           e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        end
        return nil, nil if selection.empty? # Retorna nil se seleção vazia

        # Calcula centro da BBox combinada
        total_bounds = Geom::BoundingBox.new
        selection.each { |e| total_bounds.add(e.bounds) if e.respond_to?(:bounds) && !e.bounds.empty? }
        center = total_bounds.center rescue nil # Pega o centro com segurança

        return selection, center
      end

      # --- Detectar se Shift está pressionado ---
      private_class_method def self.shift_pressed?
        begin
          # Tenta detectar o estado do Shift via Win32API (Windows)
          if Sketchup.platform == :platform_win
            require 'fiddle'
            require 'fiddle/import'

            # GetKeyState do Windows
            user32 = Fiddle::dlopen('user32')
            get_key_state = Fiddle::Function.new(user32['GetKeyState'], [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT)

            # VK_SHIFT = 0x10
            state = get_key_state.call(0x10)
            return (state & 0x8000) != 0
          end
        rescue => e
          puts "Aviso: Não foi possível detectar estado do Shift: #{e.message}"
        end

        # Fallback: sempre retorna false (usa local axes)
        return false
      end

      # --- Entry point for X rotation (supports both workflows) ---
      def self.rotate_local_x
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)

        if selection.nil? || center.nil?
          # No valid pre-selection, activate interactive tool
          puts "Rotação X: Ativando modo de seleção interativa"
          model.select_tool(RotateXTool.new)
          return
        end

        # Has pre-selection, perform rotation directly
        perform_rotation_x(selection, model)
      end

      # --- Core logic for X rotation ---
      def self.perform_rotation_x(entities, model)
        # Calculate center
        total_bounds = Geom::BoundingBox.new
        entities.each { |e| total_bounds.add(e.bounds) if e.respond_to?(:bounds) && !e.bounds.empty? }
        center = total_bounds.center

        # Detecta se Shift está pressionado
        use_global = shift_pressed?

        if use_global
          # Usa eixo X global
          rotation_axis = GLOBAL_X_AXIS
          operation_name = "Rotate Global X 90"
          puts "Rotacionando em torno do Eixo X GLOBAL no Centro da Seleção: #{center.inspect}"
        else
          # Usa eixo X local da primeira entidade
          reference_entity = entities.first
          rotation_axis = reference_entity.transformation.xaxis rescue nil
          unless rotation_axis && rotation_axis.valid? && rotation_axis.length > 1e-6
              UI.messagebox("Não foi possível obter o eixo X local da primeira entidade selecionada.")
              return
          end
          operation_name = "Rotate Local X 90"
          puts "Rotacionando em torno do Eixo X Local (ref: #{reference_entity.entityID}) no Centro da Seleção: #{center.inspect}"
        end

        model.start_operation(operation_name, true)
        transformation = Geom::Transformation.rotation(center, rotation_axis, ROTATION_ANGLE)
        model.active_entities.transform_entities(transformation, entities)
        model.commit_operation
      end

      # --- Entry point for Y rotation (supports both workflows) ---
      def self.rotate_local_y
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)

        if selection.nil? || center.nil?
          # No valid pre-selection, activate interactive tool
          puts "Rotação Y: Ativando modo de seleção interativa"
          model.select_tool(RotateYTool.new)
          return
        end

        # Has pre-selection, perform rotation directly
        perform_rotation_y(selection, model)
      end

      # --- Core logic for Y rotation ---
      def self.perform_rotation_y(entities, model)
        # Calculate center
        total_bounds = Geom::BoundingBox.new
        entities.each { |e| total_bounds.add(e.bounds) if e.respond_to?(:bounds) && !e.bounds.empty? }
        center = total_bounds.center

        # Detecta se Shift está pressionado
        use_global = shift_pressed?

        if use_global
          # Usa eixo Y global
          rotation_axis = GLOBAL_Y_AXIS
          operation_name = "Rotate Global Y 90"
          puts "Rotacionando em torno do Eixo Y GLOBAL no Centro da Seleção: #{center.inspect}"
        else
          # Usa eixo Y local da primeira entidade
          reference_entity = entities.first
          rotation_axis = reference_entity.transformation.yaxis rescue nil
          unless rotation_axis && rotation_axis.valid? && rotation_axis.length > 1e-6
              UI.messagebox("Não foi possível obter o eixo Y local da primeira entidade selecionada.")
              return
          end
          operation_name = "Rotate Local Y 90"
          puts "Rotacionando em torno do Eixo Y Local (ref: #{reference_entity.entityID}) no Centro da Seleção: #{center.inspect}"
        end

        model.start_operation(operation_name, true)
        transformation = Geom::Transformation.rotation(center, rotation_axis, ROTATION_ANGLE)
        model.active_entities.transform_entities(transformation, entities)
        model.commit_operation
      end

      # --- Entry point for Z rotation (supports both workflows) ---
      def self.rotate_local_z
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)

        if selection.nil? || center.nil?
          # No valid pre-selection, activate interactive tool
          puts "Rotação Z: Ativando modo de seleção interativa"
          model.select_tool(RotateZTool.new)
          return
        end

        # Has pre-selection, perform rotation directly
        perform_rotation_z(selection, model)
      end

      # --- Core logic for Z rotation ---
      def self.perform_rotation_z(entities, model)
        # Calculate center
        total_bounds = Geom::BoundingBox.new
        entities.each { |e| total_bounds.add(e.bounds) if e.respond_to?(:bounds) && !e.bounds.empty? }
        center = total_bounds.center

        # Detecta se Shift está pressionado
        use_global = shift_pressed?

        if use_global
          # Usa eixo Z global
          rotation_axis = GLOBAL_Z_AXIS
          operation_name = "Rotate Global Z 90"
          puts "Rotacionando em torno do Eixo Z GLOBAL no Centro da Seleção: #{center.inspect}"
        else
          # Usa eixo Z local da primeira entidade
          reference_entity = entities.first
          rotation_axis = reference_entity.transformation.zaxis rescue nil
          unless rotation_axis && rotation_axis.valid? && rotation_axis.length > 1e-6
              UI.messagebox("Não foi possível obter o eixo Z local da primeira entidade selecionada.")
              return
          end
          operation_name = "Rotate Local Z 90"
          puts "Rotacionando em torno do Eixo Z Local (ref: #{reference_entity.entityID}) no Centro da Seleção: #{center.inspect}"
        end

        model.start_operation(operation_name, true)
        transformation = Geom::Transformation.rotation(center, rotation_axis, ROTATION_ANGLE)
        model.active_entities.transform_entities(transformation, entities)
        model.commit_operation
      end

    end # module RotateLocalAxisSelectionCenter
  end # module MockupTools
end # module Rjv