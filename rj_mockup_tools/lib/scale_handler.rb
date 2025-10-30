# lib/scale_handler.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    module ScaleHandler
      extend self

      TOLERANCE = 1e-6
      X_AXIS = Geom::Vector3d.new(1, 0, 0)
      Y_AXIS = Geom::Vector3d.new(0, 1, 0)
      Z_AXIS = Geom::Vector3d.new(0, 0, 1)

      def is_scaled?(transformation)
        scale_x = transformation.xaxis.length
        scale_y = transformation.yaxis.length
        scale_z = transformation.zaxis.length
        
        (scale_x - 1.0).abs > TOLERANCE ||
        (scale_y - 1.0).abs > TOLERANCE ||
        (scale_z - 1.0).abs > TOLERANCE
      end

      def find_scaled_makette_pro(search_space)
        results = []
        find_recursively(search_space, results, Geom::Transformation.new)
        results.uniq
      end

      def select_scaled
        model = Sketchup.active_model
        scaled_instances = find_scaled_makette_pro(model.active_entities)
        
        if scaled_instances.empty?
          UI.messagebox("Nenhum componente MakettePro escalonado encontrado.")
        else
          model.selection.clear
          model.selection.add(scaled_instances)
          UI.messagebox("#{scaled_instances.length} componente(s) escalonado(s) foram selecionado(s).")
        end
      end

      # [MÉTODO CORRIGIDO]
      def fix_selected_scaled
        model = Sketchup.active_model
        selection = model.selection
        
        # A verificação agora é feita em uma única passada, garantindo todos os critérios.
        scaled_to_fix = selection.select do |e|
          e.is_a?(Sketchup::ComponentInstance) &&
          e.definition.get_attribute("MakettePro", "identifier") == "MakettePro" &&
          is_scaled?(e.transformation)
        end
        
        if scaled_to_fix.empty?
          UI.messagebox("Nenhum componente MakettePro escalonado selecionado para correção.")
          return
        end
        
        model.start_operation("Corrigir Escala de Componentes", true)
        
        count = 0
        scaled_to_fix.each do |instance|
          bake_instance_scale_to_definition(instance)
          count += 1
        end
        
        model.commit_operation
        UI.messagebox("#{count} componente(s) escalonado(s) foram corrigido(s).")
      end

      private

      # Lógica de busca está correta, pois encontra todos os candidatos
      def find_recursively(entities, results, parent_transform)
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          
          world_transform = parent_transform * entity.transformation
          
          if entity.is_a?(Sketchup::ComponentInstance)
            is_makette = entity.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
            if is_makette && is_scaled?(world_transform)
              results << entity
            end
          end
          
          find_recursively(entity.definition.entities, results, world_transform)
        end
      end

      def bake_instance_scale_to_definition(instance)
        if instance.definition.count_instances > 1
          instance = instance.make_unique
        end
        
        tr = instance.transformation
        
        x_scale = X_AXIS.transform(tr).length
        y_scale = Y_AXIS.transform(tr).length
        z_scale = Z_AXIS.transform(tr).length

        tr_definition = Geom::Transformation.scaling(x_scale, y_scale, z_scale)
        tr_instance_inverse = tr_definition.inverse

        definition = instance.definition
        entities = definition.entities
        return if entities.empty?
        
        entities.transform_entities(tr_definition, entities.to_a)

        definition.instances.each do |inst|
          inst.transform!(inst.transformation * tr_instance_inverse)
        end
      end
    end
  end
end