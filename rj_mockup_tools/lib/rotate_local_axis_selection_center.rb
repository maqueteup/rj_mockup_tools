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

      # Interactive tool for X rotation
      class RotateXTool < InteractiveSelectionTool
        def initialize
          filter = ->(entity) {
            entity.valid? &&
            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
          }
          super("Rotacionar Eixo X +90°", filter)
        end

        def execute_on_selection(entities, model)
          RotateLocalAxisSelectionCenter.perform_rotation_x(entities, model)
        end
      end

      # Interactive tool for Y rotation
      class RotateYTool < InteractiveSelectionTool
        def initialize
          filter = ->(entity) {
            entity.valid? &&
            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
          }
          super("Rotacionar Eixo Y +90°", filter)
        end

        def execute_on_selection(entities, model)
          RotateLocalAxisSelectionCenter.perform_rotation_y(entities, model)
        end
      end

      # Interactive tool for Z rotation
      class RotateZTool < InteractiveSelectionTool
        def initialize
          filter = ->(entity) {
            entity.valid? &&
            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
          }
          super("Rotacionar Eixo Z +90°", filter)
        end

        def execute_on_selection(entities, model)
          RotateLocalAxisSelectionCenter.perform_rotation_z(entities, model)
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