# encoding: UTF-8
require 'sketchup.rb'
require_relative 'interactive_selection_tool'

module Rjv
  module MockupTools
    module Apply3DPrint
      extend self

      LAYER_NAME = "MU_Impressão_3D".freeze
      LAYER_COLOR = Sketchup::Color.new(128, 0, 128)  # Roxo/Purple

      # Interactive tool class for Apply3DPrint
      class Apply3DPrintTool < InteractiveSelectionTool

        def initialize
          filter = ->(entity) {
            entity.valid? &&
            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
          }
          super("Aplicar Impressão 3D", filter)
        end

        def execute_on_selection(entities, model)
          Apply3DPrint.apply_to_entities(entities, model)
        end

      end

      # Main entry point - supports both pre-selection and interactive selection
      def run
        model = Sketchup.active_model
        selection = model.selection.to_a.select do |e|
          e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        end

        if selection.empty?
          # No valid pre-selection, activate interactive tool
          puts "Aplicar Impressão 3D: Ativando modo de seleção interativa"
          model.select_tool(Apply3DPrintTool.new)
          return
        end

        # Has pre-selection, apply directly
        apply_to_entities(selection, model)
      end

      # Core logic - applies 3D print layer and attributes to entities
      def apply_to_entities(entities, model)
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

          entities.each do |entity|
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
