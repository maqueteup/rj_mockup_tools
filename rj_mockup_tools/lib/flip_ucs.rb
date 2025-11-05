# encoding: UTF-8
# Mockup Tools RJV - Flip UCS Tool Module (Correct Local Flip)

require 'sketchup.rb'

module Rjv
  module MockupTools
    module FlipUCS

      # --- Constantes ---
      ORIGIN = Geom::Point3d.new(0, 0, 0).freeze
      # Transformação que inverte Y e Z localmente (mantém X)
      FLIP_YZ_TRANSFORMATION = Geom::Transformation.scaling(ORIGIN, 1, -1, -1).freeze
      STAMP_LAYER_NAME = "MU_Texto".freeze
      STAMP_ATTRIBUTE_DICT = "Rjv_StampName".freeze
      STAMP_GROUP_IDENTIFIER_KEY = "IsStampNameGroup".freeze

      # --- Métodos auxiliares para gerenciar carimbos ---

      # Detecta se uma definição contém carimbos
      def self.has_stamps?(definition)
        return false unless definition && definition.entities

        model = Sketchup.active_model
        stamp_layer = model.layers[STAMP_LAYER_NAME]
        return false unless stamp_layer

        definition.entities.any? do |entity|
          entity.is_a?(Sketchup::Group) &&
          entity.layer == stamp_layer &&
          entity.get_attribute(STAMP_ATTRIBUTE_DICT, STAMP_GROUP_IDENTIFIER_KEY)
        end
      end

      # Remove todos os carimbos de uma definição
      def self.remove_stamps(definition)
        return 0 unless definition && definition.entities

        model = Sketchup.active_model
        stamp_layer = model.layers[STAMP_LAYER_NAME]
        return 0 unless stamp_layer

        stamps_to_remove = []
        definition.entities.each do |entity|
          if entity.is_a?(Sketchup::Group) &&
             entity.layer == stamp_layer &&
             entity.get_attribute(STAMP_ATTRIBUTE_DICT, STAMP_GROUP_IDENTIFIER_KEY)
            stamps_to_remove << entity
          end
        end

        stamps_to_remove.each { |stamp| stamp.erase! if stamp.valid? }

        puts "   - #{stamps_to_remove.length} carimbo(s) removido(s)"
        stamps_to_remove.length
      end

      # Reaplica carimbos a uma definição
      def self.reapply_stamps(definition)
        return false unless definition

        # Garante que StampName está carregado
        Rjv::MockupTools.ensure_loaded('StampName')
        return false unless defined?(Rjv::MockupTools::StampName)

        model = Sketchup.active_model
        settings = Rjv::MockupTools::StampName.load_settings
        stamp_layer = model.layers[STAMP_LAYER_NAME]
        stamp_layer ||= model.layers.add(STAMP_LAYER_NAME)
        stamp_layer.color = [0, 255, 0] if stamp_layer

        # Verifica se a definição é MakettePro (planificável)
        return false unless definition.get_attribute("MakettePro", "identifier") == "MakettePro"

        # Cria o carimbo
        top_face = Rjv::MockupTools::StampName.send(:find_top_face, definition.entities)
        if top_face
          Rjv::MockupTools::StampName.send(:create_stamp_as_group, definition, top_face, settings, stamp_layer)
          puts "   - Carimbo reaplicado"
          return true
        end

        false
      end

      # --- Método principal chamado pelo comando ---
      def self.run
        model = Sketchup.active_model
        selection = model.selection
        selected_instances = selection.grep(Sketchup::ComponentInstance)

        if selected_instances.empty?; UI.messagebox("Nenhuma instância selecionada."); return; end

        instances_by_definition = selected_instances.group_by(&:definition)
        processed_definitions = 0
        failed_definitions = {}

        model.start_operation("Flip UCS Múltiplo (Local)", true) # Nome da operação

        instances_by_definition.each do |definition, _instances|
          definition_name = definition.name # Guarda nome
          begin
            # Validações
            if definition.entities.count == 0; puts "Aviso: Def '#{definition_name}' vazia."; failed_definitions[definition_name]||="Vazia"; next; end

            puts "--- Processando Flip UCS Local para: #{definition_name} ---"

            # --- PASSO 0: Gerenciar Carimbos ---
            # Detecta se há carimbos e os remove antes do flip
            had_stamps = has_stamps?(definition)
            if had_stamps
              remove_stamps(definition)
            end

            # --- PASSO 1: Aplicar Transformação de Flip Interna ---
            #    Transforma a geometria para que o que estava em +Y/+Z agora esteja em -Y/-Z
            entities_to_transform = definition.entities.to_a
            definition.entities.transform_entities(FLIP_YZ_TRANSFORMATION, entities_to_transform)
            puts "   - Geometria interna invertida localmente (Y e Z)."

            # --- PASSO 2: Compensar TODAS as Instâncias ---
            #    A compensação é a INVERSA da transformação interna.
            #    Como a transformação interna foi uma escala de [1,-1,-1],
            #    a inversa é a mesma transformação (escalar por -1 duas vezes volta ao original).
            compensate_instance_tf = FLIP_YZ_TRANSFORMATION # Inversa de Scaling(1,-1,-1) é ela mesma

            all_instances_of_def = definition.instances.to_a
            all_instances_of_def.each do |inst|
               next unless inst.valid?
               old_transform = inst.transformation
               # Nova TF = TF Antiga * Compensação
               new_transform = old_transform * compensate_instance_tf
               begin
                 inst.transformation = new_transform
               rescue TypeError => e # Segurança
                   puts "!!! ERRO DE TIPO ao aplicar compensação flip para inst #{inst.entityID}: #{e.message}"
                   raise e # Relança para abortar esta definição
               rescue => e
                    puts "!!! ERRO ao aplicar compensação flip para inst #{inst.entityID}: #{e.message}"
                    raise e
               end
            end
            puts "   - #{all_instances_of_def.length} instância(s) compensada(s)."

            # --- PASSO 3: Reaplicar Carimbos ---
            # Se havia carimbos, reaplica após o flip
            if had_stamps
              reapply_stamps(definition)
            end

            # --- (Opcional) Chamar Reset UCS ---
            # Se quiser que o botão Flip também faça o Reset imediatamente depois:
            # puts "   - Chamando Reset UCS após Flip..."
            # reset_success, reset_message = ResetUCS.process_single_definition(definition) # Precisa do ResetUCS refatorado
            # unless reset_success
            #   raise "Reset UCS falhou após Flip: #{reset_message}" # Levanta erro se o reset falhar
            # end
            # --- Fim Chamada Reset UCS ---


            processed_definitions += 1

          rescue => e
            puts "-> Erro processando Flip UCS para '#{definition_name}': #{e.message}"
            failed_definitions[definition_name] = e.message
          end # Fim begin/rescue por definição
        end # Fim loop each definition

        model.commit_operation

        # Feedback Final
        if processed_definitions > 0
           # Ajustar mensagem se chamar ResetUCS ou não
           # message = "#{processed_definitions} definição(ões) teve(tiveram) seu UCS invertido [e resetado]."
           message = "#{processed_definitions} definição(ões) teve(tiveram) seu UCS invertido (Flip YZ)."
           if failed_definitions.any?; message += "\nFalha em #{failed_definitions.count}: #{failed_definitions.keys.join(', ')}"; UI.messagebox(message); else; Sketchup.status_text = message; end
        elsif failed_definitions.any?
            UI.messagebox("Falha ao processar #{failed_definitions.count} definição(ões):\n#{failed_definitions.map{|k,v| "#{k}: #{v}"}.join("\n")}")
        else
            UI.messagebox("Nenhuma definição válida encontrada.")
        end

      end # Fim self.run

    end # module FlipUCS
  end # module MockupTools
end # module Rjv

# --- Carregar ResetUCS se for chamá-lo ---
# require_relative 'reset_ucs.rb' # Descomente se for chamar ResetUCS.process_single_definition