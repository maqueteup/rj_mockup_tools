# encoding: UTF-8
require 'sketchup.rb'

module Rjv
  module MockupTools
    module SelectStamps
      extend self

      # A camada que identifica um carimbo
      STAMP_LAYER_NAME = "MU_Texto".freeze

      def self.select_all_stamps
        model = Sketchup.active_model
        selection = model.selection
        
        # Procura a camada no modelo. Se não existir, não há o que selecionar.
        stamp_layer = model.layers[STAMP_LAYER_NAME]
        unless stamp_layer
          UI.messagebox("A camada '#{STAMP_LAYER_NAME}' não existe neste modelo.")
          return
        end

        stamps_to_select = []
        
        # Define o ponto de partida da busca: a seleção atual ou a raiz do modelo
        entities_to_start_search = selection.empty? ? model.entities : selection
        
        # Função recursiva para encontrar todas as entidades na camada do carimbo
        search_proc = Proc.new do |entities_collection|
          entities_collection.each do |e|
            # --- LÓGICA CORRETA: Procura por qualquer entidade na camada certa ---
            stamps_to_select << e if e.layer == stamp_layer

            # Continua a busca dentro de grupos e componentes, independentemente da camada do container
            if e.is_a?(Sketchup::ComponentInstance)
              search_proc.call(e.definition.entities)
            elsif e.is_a?(Sketchup::Group)
              search_proc.call(e.entities)
            end
          end
        end

        # Inicia a busca a partir do ponto de partida definido
        search_proc.call(entities_to_start_search)
        
        stamps_to_select.uniq!

        if stamps_to_select.empty?
          message = selection.empty? ? "Nenhum carimbo encontrado no modelo." : "Nenhum carimbo encontrado na seleção."
          UI.messagebox(message)
          return
        end

        model.selection.clear
        model.selection.add(stamps_to_select)
        
        message = "#{stamps_to_select.length} carimbo(s) selecionados. Pressione F11 ou use o menu de contexto para atualizar."
        Sketchup.status_text = message
        puts message
      end

    end
  end
end