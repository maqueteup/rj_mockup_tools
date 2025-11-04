# encoding: UTF-8
require 'sketchup.rb'

module Rjv
  module MockupTools
    module UpdateStamps
      extend self

      STAMP_ATTRIBUTE_DICT = "Rjv_StampName".freeze
      PARENT_DEF_NAME_KEY = "ParentDefName".freeze

      # [MÉTODO CORRIGIDO E REESCRITO]
      def self.check_for_updates
        model = Sketchup.active_model
        updates_needed_count = 0
        
        # Função de busca recursiva que rastreia os pais
        search_proc = ->(entities, parents) do
          entities.each do |ent|
            # Verifica se é um grupo de carimbo
            if ent.is_a?(Sketchup::Group) && ent.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY)
              
              # Verifica se está dentro de um grupo de planificação
              is_in_plan_group = parents.any? { |p| 
                p.respond_to?(:name) && (p.name.downcase.include?("planifica") || p.name.downcase.include?("plano de corte")) 
              }
              
              # Se NÃO estiver em um grupo de planificação, procede com a verificação do nome
              unless is_in_plan_group
                parent_definition = ent.parent
                if parent_definition.is_a?(Sketchup::ComponentDefinition)
                  saved_parent_name = ent.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY)
                  current_parent_name = parent_definition.name
                  
                  if saved_parent_name != current_parent_name
                    updates_needed_count += 1
                  end
                end
              end
            end
            
            # Continua a busca recursiva dentro de grupos e componentes
            if ent.respond_to?(:definition) && ent.definition
              search_proc.call(ent.definition.entities, parents + [ent])
            end
          end
        end
        
        # Inicia a busca a partir da raiz do modelo
        search_proc.call(model.entities, [])
        
        return updates_needed_count
      end

def self.fix_pending_stamps
        model = Sketchup.active_model
        settings = Rjv::MockupTools::StampName.load_settings
        stamp_layer = model.layers[Rjv::MockupTools::StampName::STAMP_LAYER_NAME]
        return unless stamp_layer
        
        stamps_to_fix = []
        
        # 1. Busca todos os carimbos que precisam de correção e não estão em grupos de planificação
        search_proc = ->(entities, parents) do
          entities.each do |ent|
            if ent.is_a?(Sketchup::Group) && ent.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY)
              is_in_plan_group = parents.any? { |p| p.respond_to?(:name) && (p.name.downcase.include?("planifica") || p.name.downcase.include?("plano de corte")) }
              
              unless is_in_plan_group
                parent_definition = ent.parent
                if parent_definition.is_a?(Sketchup::ComponentDefinition)
                  saved_parent_name = ent.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY)
                  current_parent_name = parent_definition.name
                  
                  if saved_parent_name != current_parent_name
                    stamps_to_fix << ent
                  end
                end
              end
            end
            
            if ent.respond_to?(:definition) && ent.definition
              search_proc.call(ent.definition.entities, parents + [ent])
            end
          end
        end
        search_proc.call(model.entities, [])
        
        if stamps_to_fix.empty?
          Sketchup.status_text = "Nenhum carimbo pendente para atualizar."
          return
        end
        
        model.start_operation("Corrigir Carimbos Pendentes", true)
        updated_count = 0
        
        # 2. Itera e corrige APENAS a lista filtrada
        stamps_to_fix.each do |stamp_group|
          next unless stamp_group.valid?
          parent_definition = stamp_group.parent
          top_face = Rjv::MockupTools::StampName.send(:find_top_face, parent_definition.entities)
          if top_face
            stamp_group.erase!
            Rjv::MockupTools::StampName.send(:create_stamp_as_group, parent_definition, top_face, settings, stamp_layer)
            updated_count += 1
          end
        end
        
        model.commit_operation
        
        message = "#{updated_count} carimbo(s) pendente(s) foram atualizados."
        Sketchup.status_text = message
        puts message

        UI.start_timer(0.1, false) do
          Rjv::MockupTools.check_and_update_selection_info
        end
      end

      # Sua função 'run' está ótima e não precisa de alterações.
      # A lógica dela já funciona bem, pois ou opera na seleção ou
      # busca todos os carimbos para verificar. A filtragem de planificação
      # é mais importante para o notificador.
      def self.run
        model = Sketchup.active_model
        selection = model.selection
        
        settings = Rjv::MockupTools::StampName.load_settings
        stamp_layer = model.layers[Rjv::MockupTools::StampName::STAMP_LAYER_NAME]
        return unless stamp_layer

        model.start_operation("Atualizar Carimbos", true)
        
        updated_count = 0
        
        stamps_to_process = []
        force_update = !selection.empty?
        
        if force_update
          stamps_to_process = selection.select { |e| e.is_a?(Sketchup::Group) && e.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY) }
          if stamps_to_process.empty?
            model.abort_operation
            UI.messagebox("Nenhum carimbo válido selecionado para forçar a atualização.")
            return
          end
        else
          search_proc = ->(entities) do
            entities.each do |e|
              if e.is_a?(Sketchup::Group) && e.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY); stamps_to_process << e; end
              if e.respond_to?(:definition) && e.definition; search_proc.call(e.definition.entities); end
            end
          end
          search_proc.call(model.entities)
        end
        
        stamps_to_process.uniq.each do |stamp_group|
          next unless stamp_group.valid?
          parent_definition = stamp_group.parent
          next unless parent_definition.is_a?(Sketchup::ComponentDefinition)

          saved_parent_name = stamp_group.get_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY)
          current_parent_name = parent_definition.name

          if force_update || (saved_parent_name != current_parent_name)
            top_face = Rjv::MockupTools::StampName.send(:find_top_face, parent_definition.entities)
            if top_face
              stamp_group.erase!
              Rjv::MockupTools::StampName.send(:create_stamp_as_group, parent_definition, top_face, settings, stamp_layer)
              updated_count += 1
            end
          end
        end

        model.commit_operation
        
        message = "#{updated_count} carimbo(s) foram atualizados."
        Sketchup.status_text = message
        puts message
      end

    end
  end
end