# encoding: UTF-8
# Mockup Tools RJV - Rotate 90 Local Axis / Selection Center

require 'sketchup.rb'

module Rjv
  module MockupTools
    module RotateLocalAxisSelectionCenter

      # --- Constantes ---
      ROTATION_ANGLE = 90.degrees

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

      # --- Rotacionar em torno do Eixo X LOCAL da primeira entidade ---
      def self.rotate_local_x
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)
        unless selection && center
          UI.messagebox("Selecione um ou mais Grupos/Componentes válidos.")
          return
        end

        # Pega a primeira entidade válida como referência para o eixo
        reference_entity = selection.first
        local_xaxis_world = reference_entity.transformation.xaxis rescue nil
        unless local_xaxis_world && local_xaxis_world.valid? && local_xaxis_world.length > 1e-6
            UI.messagebox("Não foi possível obter o eixo X local da primeira entidade selecionada.")
            return
        end

        puts "Rotacionando em torno do Eixo X Local (ref: #{reference_entity.entityID}) no Centro da Seleção: #{center.inspect}"
        model.start_operation("Rotate Local X 90", true)
        transformation = Geom::Transformation.rotation(center, local_xaxis_world, ROTATION_ANGLE)
        model.active_entities.transform_entities(transformation, selection) # Aplica a toda seleção válida
        model.commit_operation
      end

      # --- Rotacionar em torno do Eixo Y LOCAL da primeira entidade ---
      def self.rotate_local_y
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)
        unless selection && center; UI.messagebox("Selecione Grupo(s)/Componente(s)."); return; end

        reference_entity = selection.first
        local_yaxis_world = reference_entity.transformation.yaxis rescue nil
        unless local_yaxis_world && local_yaxis_world.valid? && local_yaxis_world.length > 1e-6
            UI.messagebox("Não foi possível obter o eixo Y local da primeira entidade selecionada.")
            return
        end

        puts "Rotacionando em torno do Eixo Y Local (ref: #{reference_entity.entityID}) no Centro da Seleção: #{center.inspect}"
        model.start_operation("Rotate Local Y 90", true)
        transformation = Geom::Transformation.rotation(center, local_yaxis_world, ROTATION_ANGLE)
        model.active_entities.transform_entities(transformation, selection)
        model.commit_operation
      end

      # --- Rotacionar em torno do Eixo Z LOCAL da primeira entidade ---
      def self.rotate_local_z
        model = Sketchup.active_model
        selection, center = get_selection_and_center(model)
        unless selection && center; UI.messagebox("Selecione Grupo(s)/Componente(s)."); return; end

        reference_entity = selection.first
        local_zaxis_world = reference_entity.transformation.zaxis rescue nil
        unless local_zaxis_world && local_zaxis_world.valid? && local_zaxis_world.length > 1e-6
            UI.messagebox("Não foi possível obter o eixo Z local da primeira entidade selecionada.")
            return
        end

        puts "Rotacionando em torno do Eixo Z Local (ref: #{reference_entity.entityID}) no Centro da Seleção: #{center.inspect}"
        model.start_operation("Rotate Local Z 90", true)
        transformation = Geom::Transformation.rotation(center, local_zaxis_world, ROTATION_ANGLE)
        model.active_entities.transform_entities(transformation, selection)
        model.commit_operation
      end

    end # module RotateLocalAxisSelectionCenter
  end # module MockupTools
end # module Rjv