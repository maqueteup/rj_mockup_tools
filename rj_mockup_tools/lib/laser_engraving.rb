# lib/laser_engraving.rb (Sem grupo - apenas muda layer)
# encoding: UTF-8

module Rjv
  module MockupTools
    module LaserEngraving
      extend self
      ATTRIBUTE_DICT = "RJV_MockupTools".freeze
      ENGRAVING_LAYER_NAME = "RJV_Gravação_Laser".freeze
      ENGRAVING_EDGE_KEY = "is_engraving_edge".freeze
      PROCESSED_STATE_KEY = "engraving_processed_state".freeze

      def run_on_all_pending
        model = Sketchup.active_model
        pending_definitions = find_pending_definitions(model)
        if pending_definitions.empty?
          UI.messagebox("Nenhum componente MakettePro com gravação pendente foi encontrado.")
          return
        end
        model.start_operation("Criar Gravação em Lote", true)
        count = 0
        pending_definitions.each do |definition|
          process_definition(definition)
          count += 1
        end
        model.commit_operation
        UI.messagebox("#{count} componente(s) tiveram a gravação a laser criada com sucesso!")
      end

      def run_on_selection
        model = Sketchup.active_model
        selection = model.selection
        target_instances = selection.select do |e|
          e.is_a?(Sketchup::ComponentInstance) &&
          e.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
        end
        if target_instances.empty?
          UI.messagebox("Nenhum componente 'MakettePro' encontrado na sua seleção.")
          return
        end
        target_definitions = target_instances.map(&:definition).uniq
        model.start_operation("Criar Gravação na Seleção", true)
        count = 0
        target_definitions.each do |definition|
          process_definition(definition)
          count += 1
        end
        model.commit_operation
        UI.messagebox("#{count} definição(ões) selecionada(s) tiveram a gravação criada.")
      end

      # ⚠️ CONTADOR EM TEMPO REAL DESABILITADO
      # Este método era chamado por um timer em segundo plano
      def check_for_pending_engravings
        return 0  # Sempre retorna 0 (desabilitado)
      end

      private

      def has_engravable_edges?(definition)
        entities = definition.entities
        entities.grep(Sketchup::Edge).any? do |edge|
          # Ignora arestas já marcadas como gravação
          next false if edge.get_attribute(ATTRIBUTE_DICT, ENGRAVING_EDGE_KEY)
          
          # Verifica se é aresta de gravação (sem face ou entre faces paralelas)
          edge.faces.length == 0 || 
          (edge.faces.length == 2 && edge.faces[0].normal.parallel?(edge.faces[1].normal))
        end
      end
      
      def find_pending_definitions(model)
        model.definitions.select do |definition|
          is_makette = definition.get_attribute("MakettePro", "identifier") == "MakettePro"
          next false unless is_makette
          
          json_string = definition.get_attribute(ATTRIBUTE_DICT, PROCESSED_STATE_KEY)
          stored_state = nil
          if json_string
            begin
              stored_state = JSON.parse(json_string)
            rescue
              stored_state = nil
            end
          end

          # Conta arestas que NÃO são de gravação
          current_edge_count = definition.entities.grep(Sketchup::Edge).count do |edge|
            !edge.get_attribute(ATTRIBUTE_DICT, ENGRAVING_EDGE_KEY)
          end

          needs_check = stored_state.nil? || stored_state["edge_count"] != current_edge_count
          
          needs_check && has_engravable_edges?(definition)
        end
      end

      def process_definition(definition)
        entities = definition.entities
        
        # Cria a layer de gravação se não existir
        engraving_layer = definition.model.layers[ENGRAVING_LAYER_NAME]
        unless engraving_layer
          engraving_layer = definition.model.layers.add(ENGRAVING_LAYER_NAME)
          engraving_layer.color = "Red"
        end

        edges_to_mark = []
        
        entities.grep(Sketchup::Edge).each do |edge|
          # Ignora arestas já marcadas como gravação
          next if edge.get_attribute(ATTRIBUTE_DICT, ENGRAVING_EDGE_KEY)
          
          # Aresta solta (sem faces) -> é gravação
          if edge.faces.length == 0
            edges_to_mark << edge
            next
          end
          
          # Aresta entre duas faces paralelas -> é gravação
          if edge.faces.length == 2
            face1, face2 = edge.faces
            if face1.normal.parallel?(face2.normal)
              edges_to_mark << edge
            end
          end
        end

        # APENAS muda a layer das arestas, SEM apagar nada!
        edges_to_mark.each do |edge|
          edge.layer = engraving_layer
          edge.set_attribute(ATTRIBUTE_DICT, ENGRAVING_EDGE_KEY, true)
        end
        
        # Atualiza o estado de processamento
        final_edge_count = entities.grep(Sketchup::Edge).count do |edge|
          !edge.get_attribute(ATTRIBUTE_DICT, ENGRAVING_EDGE_KEY)
        end
        
        state_hash = { "edge_count" => final_edge_count }
        definition.set_attribute(ATTRIBUTE_DICT, PROCESSED_STATE_KEY, state_hash.to_json)
        
        puts "✅ Gravação processada: #{edges_to_mark.length} arestas marcadas na layer '#{ENGRAVING_LAYER_NAME}'"
      end
    end
  end
end