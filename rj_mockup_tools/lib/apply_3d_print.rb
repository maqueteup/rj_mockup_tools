# encoding: UTF-8
require 'sketchup.rb'

module Rjv
  module MockupTools
    module Apply3DPrint
      extend self

      LAYER_NAME = "MU_Impressão_3D".freeze
      LAYER_COLOR = Sketchup::Color.new(128, 0, 128)  # Roxo/Purple

      def run
        model = Sketchup.active_model
        selection = model.selection

        if selection.empty?
          UI.messagebox("Selecione um ou mais objetos para aplicar 'Impressão 3D'")
          return
        end

        model.start_operation("Aplicar Impressão 3D", true)

        begin
          # Cria/obtém a layer
          layer_3d = model.layers[LAYER_NAME]
          unless layer_3d
            layer_3d = model.layers.add(LAYER_NAME)
            layer_3d.color = LAYER_COLOR
            puts "✅ Layer '#{LAYER_NAME}' criada (cor roxa)"
          end

          count = 0

          selection.each do |entity|
            next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            next unless entity.valid?

            # Aplica a layer
            entity.layer = layer_3d

            # Marca como MakettePro para ser planificável
            if entity.is_a?(Sketchup::ComponentInstance) && entity.definition
              entity.definition.set_attribute("MakettePro", "identifier", "MakettePro")
              puts "  ✓ #{entity.definition.name} → Impressão 3D (planificável)"
            elsif entity.is_a?(Sketchup::Group)
              entity.set_attribute("MakettePro", "identifier", "MakettePro")
              puts "  ✓ #{entity.name || 'Group'} → Impressão 3D (planificável)"
            end

            count += 1
          end

          model.commit_operation

          message = "✅ #{count} objeto(s) marcado(s) como 'Impressão 3D' e planificável!"
          UI.messagebox(message)
          puts message

        rescue => e
          model.abort_operation
          UI.messagebox("❌ Erro: #{e.message}")
          puts "Erro: #{e.message}"
          puts e.backtrace.first(5)
        end
      end

    end
  end
end
