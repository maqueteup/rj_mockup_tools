# encoding: UTF-8
# Mockup Tools RJV - Reset UCS (Gizmo) Tool Module

require 'sketchup.rb'

module Rjv
  module MockupTools
    module ResetUCS

      # --- Constantes ---
      TOLERANCE = 1e-4 # Tolerância para comparações

      # --- Método principal chamado pelo comando ---
      def self.run
        model = Sketchup.active_model
        selection = model.selection
        selected_instances = selection.grep(Sketchup::ComponentInstance)

        if selected_instances.empty?
          UI.messagebox("Nenhuma instância de componente selecionada.")
          return
        end

        instances_by_definition = selected_instances.group_by(&:definition)
        processed_definitions = 0
        failed_definitions = {}

        model.start_operation("Reset UCS Múltiplo", true)

        instances_by_definition.each do |definition, _instances_in_selection| # Não precisamos das instâncias selecionadas aqui
          begin
            if definition.entities.count == 0
              puts "Aviso: Definição '#{definition.name}' vazia. Pulando."
              failed_definitions[definition.name] = "Definição vazia"
              next
            end

            bounds = definition.bounds
            if bounds.empty?
                 puts "Aviso: Bounding Box da definição '#{definition.name}' vazia. Pulando."
                 failed_definitions[definition.name] = "Bounding Box vazia"
                 next
            end
            corners = (0..7).map { |i| bounds.corner(i) }
            bottom_left_in_def_coords = corners.min_by { |c| [c.z, c.x, c.y] }

            unless bottom_left_in_def_coords
                puts "Aviso: Falha ao encontrar canto inf-esq para '#{definition.name}'. Pulando."
                failed_definitions[definition.name] = "Falha ao encontrar canto"
                next
            end

            if bottom_left_in_def_coords.distance(ORIGIN) < TOLERANCE
                puts "Info: UCS da definição '#{definition.name}' já está correto. Pulando."
                processed_definitions += 1
                next
            end

            # T1: Move a geometria interna para a origem [0,0,0]
            move_geometry_to_origin_tf = Geom::Transformation.translation(bottom_left_in_def_coords.vector_to(ORIGIN))
            # T2: Transformação para DESFAZER o movimento interno (compensação)
            keep_instance_in_place_tf = move_geometry_to_origin_tf.inverse

            # Aplica T1 à definição
            entities_to_transform = definition.entities.to_a
            definition.entities.transform_entities(move_geometry_to_origin_tf, entities_to_transform)

            # Aplica a compensação a TODAS as instâncias desta definição
            all_instances_of_def = definition.instances.to_a # Pega todas e converte para array
            all_instances_of_def.each do |inst|
               next unless inst.valid?
               old_transform = inst.transformation
               # <<<< CORREÇÃO DA ORDEM DA MULTIPLICAÇÃO >>>>
               # A nova transformação coloca a instância onde estava ANTES,
               # e ENTÃO aplica a transformação que DESFAZ o movimento interno da geometria.
               # O ponto [0,0,0] interno (que agora é o canto inf-esq) será mapeado
               # para onde o canto inf-esq estava no mundo.
               # Transformação_Antiga * Compensação_Interna
               new_transform = old_transform * keep_instance_in_place_tf
               # <<<< FIM DA CORREÇÃO >>>>
               inst.transformation = new_transform
            end

            processed_definitions += 1
            puts "UCS da definição '#{definition.name}' movido. #{all_instances_of_def.length} instância(s) atualizada(s)."

          rescue => e
            puts "Erro ao resetar UCS para '#{definition.name}':\n#{e.message}"
            failed_definitions[definition.name] = e.message
          end
        end # Fim do loop each definition

        model.commit_operation

        # Feedback Final (igual)
        if processed_definitions > 0
           message = "#{processed_definitions} definição(ões) teve(tiveram) seu UCS ajustado."
           if failed_definitions.any?
              message += "\nFalha ao processar #{failed_definitions.count} definição(ões): #{failed_definitions.keys.join(', ')}"
              UI.messagebox(message)
           else
              Sketchup.status_text = message
           end
        elsif failed_definitions.any?
            UI.messagebox("Falha ao processar #{failed_definitions.count} definição(ões) selecionada(s):\n#{failed_definitions.map{|k,v| "#{k}: #{v}"}.join("\n")}")
        else
            UI.messagebox("Nenhuma definição de componente válida encontrada na seleção.")
        end

      end # Fim self.run

    end # module ResetUCS
  end # module MockupTools
end # module Rjv