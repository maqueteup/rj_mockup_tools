# encoding: UTF-8
# Mockup Tools RJV - Flip UCS Tool Module (Correct Local Flip)

require 'sketchup.rb'

module Rjv
  module MockupTools

    # Ferramenta interativa para inverter eixos
    class FlipUCSInteractiveTool
      VK_ESCAPE = 27

      def initialize
        @current_instance = nil
        @z_direction = nil  # :up ou :down
      end

      def activate
        @model = Sketchup.active_model
        @view = @model.active_view
        Sketchup.status_text = "Inverter Eixos: Clique em um componente para inverter (ESC para sair)"
        puts "Ferramenta Inverter Eixos ativada - clique em componentes"
      end

      def deactivate(view)
        view.invalidate
        @current_instance = nil
        @z_direction = nil
      end

      def onLButtonDown(flags, x, y, view)
        # Usa EXATAMENTE a mesma lógica que RenameSelectionTool
        ph = view.pick_helper
        ph.do_pick(x, y)

        picked = nil
        if ph.count > 0
          # Tenta usar path para objetos aninhados
          path = ph.path_at(0)
          if path.is_a?(Sketchup::InstancePath)
            # Procura no path por componentes com identifier=MakettePro
            picked = find_makettepro_in_path(path)
            # Se não encontrou MakettePro, usa o último elemento
            picked ||= path.to_a.last
          else
            # Fallback para best_picked
            picked = ph.best_picked
          end
        end

        return unless picked
        return unless picked.is_a?(Sketchup::ComponentInstance)

        # Aplicar flip imediatamente
        apply_flip_to_instance(picked)

        Sketchup.status_text = "Eixos invertidos! Clique em outro componente ou ESC para sair"
        view.invalidate
      end

      # Encontra o primeiro componente MakettePro no path
      def find_makettepro_in_path(path)
        path_array = path.to_a.reverse
        path_array.each do |entity|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          definition = entity.definition
          if definition.get_attribute("MakettePro", "identifier") == "MakettePro"
            return entity
          end
        end
        nil
      end

      def apply_flip_to_instance(instance)
        return unless instance && instance.valid?

        model = Sketchup.active_model
        definition = instance.definition

        model.start_operation("Inverter Eixos - #{definition.name}", true)

        begin
          puts "Invertendo eixos para #{definition.name}"

          # Detecta e remove carimbos
          had_stamps = FlipUCS.has_stamps?(definition)
          if had_stamps
            FlipUCS.remove_stamps(definition)
          end

          # Aplica transformação de flip
          entities_to_transform = definition.entities.to_a
          definition.entities.transform_entities(FlipUCS::FLIP_YZ_TRANSFORMATION, entities_to_transform)

          # Compensa nas instâncias
          all_instances = definition.instances.to_a
          all_instances.each do |inst|
            next unless inst.valid?
            old_tf = inst.transformation
            new_tf = old_tf * FlipUCS::FLIP_YZ_TRANSFORMATION
            inst.transformation = new_tf
          end

          # Reaplica carimbos
          if had_stamps
            FlipUCS.reapply_stamps(definition)
          end

          model.commit_operation
          puts "✓ #{definition.name} processado - #{all_instances.length} instância(s)"

        rescue => e
          model.abort_operation
          puts "Erro ao inverter eixos: #{e.message}"
          puts e.backtrace.first(5)
        end
      end

      def onMouseMove(flags, x, y, view)
        # Detecta componente sob o mouse para mostrar preview
        ph = view.pick_helper
        ph.do_pick(x, y)

        @current_instance = nil
        if ph.count > 0
          path = ph.path_at(0)
          if path.is_a?(Sketchup::InstancePath)
            picked = find_makettepro_in_path(path)
            picked ||= path.to_a.last
          else
            picked = ph.best_picked
          end

          if picked && picked.is_a?(Sketchup::ComponentInstance)
            @current_instance = picked
            # Detecta direção do eixo Z
            @z_direction = detect_z_direction(picked)
          end
        end

        view.invalidate
      end

      def detect_z_direction(instance)
        # Pega o eixo Z da transformação da instância
        tf = instance.transformation
        z_vector = tf.zaxis
        # Se Z aponta mais para cima que para baixo, é :up
        z_vector.z > 0 ? :up : :down
      end

      def draw(view)
        return unless @current_instance && @current_instance.valid?

        # Desenha bounding box
        bounds = @current_instance.bounds
        view.line_stipple = ""
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(66, 133, 244)  # Azul

        # Desenha as 12 arestas do bounding box
        (0..11).each do |edge_index|
          p1 = get_bbox_edge_point(bounds, edge_index, 0)
          p2 = get_bbox_edge_point(bounds, edge_index, 1)
          view.draw(GL_LINES, p1, p2)
        end

        # Desenha seta do eixo Z
        draw_z_axis_arrow(view)
      end

      def draw_z_axis_arrow(view)
        return unless @current_instance

        tf = @current_instance.transformation
        center = @current_instance.bounds.center
        z_vector = tf.zaxis

        # Tamanho da seta
        arrow_length = 100.0.mm
        arrow_head_length = 20.0.mm
        arrow_head_width = 10.0.mm

        # Ponta da seta
        arrow_end = center.offset(z_vector.transform(arrow_length))

        # Cor baseada na direção
        if @z_direction == :up
          view.drawing_color = Sketchup::Color.new(0, 255, 0)  # Verde = Z para cima
        else
          view.drawing_color = Sketchup::Color.new(255, 0, 0)  # Vermelho = Z para baixo
        end

        view.line_width = 4

        # Linha principal
        view.draw(GL_LINES, center, arrow_end)

        # Cabeça da seta (cone simplificado como linhas)
        head_base = center.offset(z_vector.transform(arrow_length - arrow_head_length))
        perpendicular = z_vector.axes[0]  # Pega vetor perpendicular

        # 4 linhas formando a ponta
        4.times do |i|
          angle = (i / 4.0) * 2.0 * Math::PI
          offset_x = Math.cos(angle) * arrow_head_width
          offset_y = Math.sin(angle) * arrow_head_width
          base_point = head_base.offset(
            Geom::Vector3d.new(
              perpendicular.x * offset_x,
              perpendicular.y * offset_y,
              0
            )
          )
          view.draw(GL_LINES, base_point, arrow_end)
        end
      end

      def get_bbox_edge_point(bounds, edge_index, point_index)
        edges = [
          [0, 1], [1, 2], [2, 3], [3, 0],  # Base inferior
          [4, 5], [5, 6], [6, 7], [7, 4],  # Base superior
          [0, 4], [1, 5], [2, 6], [3, 7]   # Arestas verticais
        ]
        corner_indices = edges[edge_index]
        corner_index = corner_indices[point_index]
        return bounds.corner(corner_index)
      end

      def onKeyDown(key, repeat, flags, view)
        if key == VK_ESCAPE
          puts "Ferramenta Inverter Eixos desativada"
          @model.select_tool(nil)
          return true
        end
        false
      end

      def onSetCursor
        UI.set_cursor(0)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        if @current_instance && @current_instance.valid?
          bb.add(@current_instance.bounds)
        else
          bb = Sketchup.active_model.bounds
        end
        bb
      end
    end

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