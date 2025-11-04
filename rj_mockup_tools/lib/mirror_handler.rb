# lib/mirror_handler.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    module MirrorHandler
      extend self

      # --- Métodos Públicos (chamados pelos menus e pelo Seletor) ---

      # Retorna uma lista de instâncias MakettePro espelhadas
      def find_mirrored_makette_pro(search_space)
        find_mirrored_makette_pro_with_transforms(search_space).map { |info| info[:instance] }
      end

      # Seleciona as instâncias espelhadas no modelo
      def select_mirrored
        model = Sketchup.active_model
        mirrored_instances = find_mirrored_makette_pro(model.active_entities)
        
        if mirrored_instances.empty?
          UI.messagebox("Nenhum componente MakettePro espelhado encontrado.")
        else
          model.selection.clear
          model.selection.add(mirrored_instances)
          Sketchup.status_text = "#{mirrored_instances.length} componente(s) espelhado(s) selecionado(s)."
        end
      end

      # Corrige todas as instâncias espelhadas encontradas no modelo
      def fix_all_mirrored
        model = Sketchup.active_model
        mirrored_info = find_mirrored_makette_pro_with_transforms(model.active_entities)
        
        if mirrored_info.empty?
          UI.messagebox("Nenhum componente MakettePro espelhado para corrigir.")
          return
        end
        
        model.start_operation("Corrigir Componentes Espelhados", true)
        
        @mirrored_defs_cache = {} # Cache para evitar recriar definições
        count = 0
        
        mirrored_info.each do |info|
          fix_instance(
            info[:instance], 
            info[:world_transform], 
            info[:parent_transform]
          )
          count += 1
        end
        
        model.commit_operation
        UI.messagebox("#{count} componente(s) espelhado(s) foram corrigido(s).")

        # Atualiza a UI do seletor para zerar o contador
        Rjv::MockupTools.check_and_update_selection_info if Rjv::MockupTools.selector_dialog&.visible?
      end

      private

      # --- Métodos Auxiliares e Lógica Interna ---

      # Verifica se uma transformação resulta em espelhamento
      def is_mirrored?(transformation)
        (transformation.xaxis * transformation.yaxis).dot(transformation.zaxis) < 0
      end
      
      # Retorna um array de hashes com as instâncias e suas transformações
      def find_mirrored_makette_pro_with_transforms(search_space)
        results = []
        find_recursively(search_space, results, Geom::Transformation.new)
        results.uniq { |info| info[:instance] }
      end

      # Busca recursivamente, acumulando a transformação
      def find_recursively(entities, results, parent_transform)
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          
          world_transform = parent_transform * entity.transformation
          
          if entity.is_a?(Sketchup::ComponentInstance)
            is_makette = entity.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
            if is_makette && is_mirrored?(world_transform)
              results << { 
                instance: entity, 
                world_transform: world_transform,
                parent_transform: parent_transform 
              }
            end
          end
          
          find_recursively(entity.definition.entities, results, world_transform)
        end
      end
      
      # Cria uma nova definição espelhada ou a retorna do cache
      def get_or_create_mirrored_definition(original_def)
        return @mirrored_defs_cache[original_def] if @mirrored_defs_cache.key?(original_def)

        model = original_def.model
        mirrored_def_name = model.definitions.unique_name("#{original_def.name}_espelhada")
        mirrored_def = model.definitions.add(mirrored_def_name)
        
        mirror_transform = Geom::Transformation.scaling(-1, 1, 1)
        temp_instance = mirrored_def.entities.add_instance(original_def, mirror_transform)
        temp_instance.explode if temp_instance
        
        original_def.attribute_dictionaries.each do |dict|
          dict.each_pair { |key, value| mirrored_def.set_attribute(dict.name, key, value) }
        end
        
        @mirrored_defs_cache[original_def] = mirrored_def
        return mirrored_def
      end
      
      # O coração da lógica de correção, agora validado
      def fix_instance(instance, world_transform, parent_transform)
        return unless instance.valid?

        mirrored_def = get_or_create_mirrored_definition(instance.definition)
        
        unmirror_transform = Geom::Transformation.scaling(-1, 1, 1)
        new_world_transform = world_transform * unmirror_transform
        
        # A nova transformação LOCAL é a mundial desejada, multiplicada pela inversa do pai.
        new_local_transform = parent_transform.inverse * new_world_transform
        
        new_instance = instance.parent.entities.add_instance(mirrored_def, new_local_transform)
        
        # Copia as propriedades da instância
        new_instance.name = instance.name
        new_instance.layer = instance.layer
        new_instance.material = instance.material
        
        instance.erase!
      end
    end
  end
end