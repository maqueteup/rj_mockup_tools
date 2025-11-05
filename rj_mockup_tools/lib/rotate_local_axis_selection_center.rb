# encoding: UTF-8
# Mockup Tools RJV - Rotate 90 Local Axis / Selection Center

require 'sketchup.rb'

module Rjv
  module MockupTools
    module RotateLocalAxisSelectionCenter

      # --- Constantes ---
      ROTATION_ANGLE = 90.degrees
      GLOBAL_X_AXIS = Geom::Vector3d.new(1, 0, 0).freeze
      GLOBAL_Y_AXIS = Geom::Vector3d.new(0, 1, 0).freeze
      GLOBAL_Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze

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

      # --- Rotacionar em torno do Eixo X (Local ou Global) ---
      def self.rotate_local_x
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)
        unless selection && center
          UI.messagebox("Selecione um ou mais Grupos/Componentes válidos.")
          return
        end

        # Detecta se Shift está pressionado
        use_global = shift_pressed?

        if use_global
          # Usa eixo X global
          rotation_axis = GLOBAL_X_AXIS
          operation_name = "Rotate Global X 90"
          puts "Rotacionando em torno do Eixo X GLOBAL no Centro da Seleção: #{center.inspect}"
        else
          # Usa eixo X local da primeira entidade
          reference_entity = selection.first
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
        model.active_entities.transform_entities(transformation, selection)
        model.commit_operation
      end

      # --- Rotacionar em torno do Eixo Y (Local ou Global) ---
      def self.rotate_local_y
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)
        unless selection && center; UI.messagebox("Selecione Grupo(s)/Componente(s)."); return; end

        # Detecta se Shift está pressionado
        use_global = shift_pressed?

        if use_global
          # Usa eixo Y global
          rotation_axis = GLOBAL_Y_AXIS
          operation_name = "Rotate Global Y 90"
          puts "Rotacionando em torno do Eixo Y GLOBAL no Centro da Seleção: #{center.inspect}"
        else
          # Usa eixo Y local da primeira entidade
          reference_entity = selection.first
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
        model.active_entities.transform_entities(transformation, selection)
        model.commit_operation
      end

      # --- Rotacionar em torno do Eixo Z (Local ou Global) ---
      def self.rotate_local_z
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)
        unless selection && center; UI.messagebox("Selecione Grupo(s)/Componente(s)."); return; end

        # Detecta se Shift está pressionado
        use_global = shift_pressed?

        if use_global
          # Usa eixo Z global
          rotation_axis = GLOBAL_Z_AXIS
          operation_name = "Rotate Global Z 90"
          puts "Rotacionando em torno do Eixo Z GLOBAL no Centro da Seleção: #{center.inspect}"
        else
          # Usa eixo Z local da primeira entidade
          reference_entity = selection.first
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
        model.active_entities.transform_entities(transformation, selection)
        model.commit_operation
      end

    end # module RotateLocalAxisSelectionCenter
  end # module MockupTools
end # module Rjv