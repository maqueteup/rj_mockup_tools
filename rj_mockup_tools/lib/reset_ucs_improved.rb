# encoding: UTF-8
# reset_ucs_improved.rb
# Módulo para resetar UCS (gizmo) de componentes de forma inteligente

require 'sketchup.rb'

module Rjv
  module MockupTools

    # Ferramenta interativa para escolher canto do UCS
    class ResetUCSCornerTool
      VK_ESCAPE = 27
      CORNER_RADIUS = 25  # Raio em pixels para detecção de canto
      HIGHLIGHT_SIZE = 20.0.mm  # Tamanho do círculo de highlight

      def initialize
        @current_instance = nil
        @corners = []
        @hovered_corner = nil
        @corner_transformations = {}
        @picked_instance = nil
      end

      def activate
        @model = Sketchup.active_model
        @view = @model.active_view

        Sketchup.status_text = "Reset UCS: Clique em um componente, depois escolha o canto (ESC para sair)"
        puts "Ferramenta Reset UCS ativada - clique em componentes para resetar UCS"
      end

      def deactivate(view)
        view.invalidate
        @current_instance = nil
        @corners = []
        @picked_instance = nil
      end

      def onLButtonDown(flags, x, y, view)
        # Verifica se clicou em um canto
        if @hovered_corner && @current_instance
          apply_ucs_with_corner(@hovered_corner)

          # Limpa e continua pronto para próximo componente
          @current_instance = nil
          @corners = []
          @picked_instance = nil
          @hovered_corner = nil
          view.invalidate

          Sketchup.status_text = "Reset UCS aplicado! Clique em outro componente ou ESC para sair"
          return
        end

        # Se não clicou em canto, tenta selecionar um componente
        ph = view.pick_helper
        ph.do_pick(x, y)

        picked = nil
        if ph.count > 0
          # Explora todos os itens do pick para encontrar componentes aninhados
          # Começa do índice 0 (mais profundo) até count-1 (mais superficial)
          (0...ph.count).each do |pick_index|
            path = ph.path_at(pick_index)

            if path.is_a?(Sketchup::InstancePath)
              # Busca MakettePro no path, do mais profundo ao mais raso
              picked = find_makettepro_in_path(path)
              if picked
                break
              end

              # Se não encontrou MakettePro, tenta o último elemento se for componente
              leaf = path.to_a.last
              if leaf.is_a?(Sketchup::ComponentInstance)
                picked = leaf
                break
              end
            else
              # Não é path, usa o indexador [] do pick_helper
              entity = ph[pick_index]
              if entity && entity.is_a?(Sketchup::ComponentInstance)
                picked = entity
                break
              end
            end
          end
        end

        return unless picked
        return unless picked.is_a?(Sketchup::ComponentInstance)

        # Componente selecionado
        @current_instance = picked
        @picked_instance = picked
        prepare_corner_data_for_instance(picked)

        Sketchup.status_text = "Componente selecionado: #{picked.definition.name} - Escolha o canto"
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

      def prepare_corner_data_for_instance(instance)
        definition = instance.definition
        bounds = definition.bounds

        # Calcula os 4 cantos no plano Z atual
        min_pt = bounds.min
        max_pt = bounds.max

        corners_local = [
          Geom::Point3d.new(min_pt.x, min_pt.y, min_pt.z),  # Canto 0: inferior-esquerdo
          Geom::Point3d.new(max_pt.x, min_pt.y, min_pt.z),  # Canto 1: inferior-direito
          Geom::Point3d.new(max_pt.x, max_pt.y, min_pt.z),  # Canto 2: superior-direito
          Geom::Point3d.new(min_pt.x, max_pt.y, min_pt.z)   # Canto 3: superior-esquerdo
        ]

        @corners = corners_local
        calculate_corner_transformations(corners_local, bounds)
      end

      def calculate_corner_transformations(corners, bounds)
        # Cada canto escolhido se torna o novo canto inferior-esquerdo
        # O gizmo rotaciona no eixo Z dependendo do canto
        # Orientação inicial: X=(1,0,0), Y=(0,1,0), Z=(0,0,1)
        # Regra da mão direita: X × Y = Z

        @corner_transformations = {}

        z_axis = Geom::Vector3d.new(0, 0, 1)  # Z sempre para cima

        # Canto 0: inferior-esquerdo (sem rotação)
        @corner_transformations[0] = {
          origin: corners[0],
          x_axis: Geom::Vector3d.new(1, 0, 0),   # X direita
          y_axis: Geom::Vector3d.new(0, 1, 0),   # Y frente
          z_axis: z_axis,
          rotation: 0,
          label: "Inf-Esq (0°)"
        }

        # Canto 1: inferior-direito (90° anti-horário)
        # Após rotação: X aponta para cima (0,1,0), Y aponta para esquerda (-1,0,0)
        @corner_transformations[1] = {
          origin: corners[1],
          x_axis: Geom::Vector3d.new(0, 1, 0),   # X cima
          y_axis: Geom::Vector3d.new(-1, 0, 0),  # Y esquerda
          z_axis: z_axis,
          rotation: -90.degrees,
          label: "Inf-Dir (90°↺)"
        }

        # Canto 2: superior-direito (180°)
        # Após rotação: X aponta para esquerda (-1,0,0), Y aponta para trás (0,-1,0)
        @corner_transformations[2] = {
          origin: corners[2],
          x_axis: Geom::Vector3d.new(-1, 0, 0),  # X esquerda
          y_axis: Geom::Vector3d.new(0, -1, 0),  # Y trás
          z_axis: z_axis,
          rotation: 180.degrees,
          label: "Sup-Dir (180°)"
        }

        # Canto 3: superior-esquerdo (270° anti-horário = 90° horário)
        # Após rotação: X aponta para baixo (0,-1,0), Y aponta para direita (1,0,0)
        @corner_transformations[3] = {
          origin: corners[3],
          x_axis: Geom::Vector3d.new(0, -1, 0),  # X baixo
          y_axis: Geom::Vector3d.new(1, 0, 0),   # Y direita
          z_axis: z_axis,
          rotation: -270.degrees,
          label: "Sup-Esq (270°↺)"
        }
      end

      def onMouseMove(flags, x, y, view)
        @hovered_corner = nil

        return unless @current_instance && @current_instance.valid?

        # Verifica qual canto está próximo do mouse
        @corners.each_with_index do |corner, index|
          # Transforma o ponto do local do componente para o mundo
          world_pt = corner.transform(@current_instance.transformation)
          screen_pt = view.screen_coords(world_pt)

          # Calcula distância em pixels
          dx = screen_pt.x - x
          dy = screen_pt.y - y
          dist = Math.sqrt(dx * dx + dy * dy)

          if dist < CORNER_RADIUS
            @hovered_corner = index
            transformation_info = @corner_transformations[index]
            Sketchup.status_text = "#{transformation_info[:label]} - Clique para escolher"
            break
          end
        end

        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        if key == VK_ESCAPE
          puts "Reset UCS cancelado"
          @model.select_tool(nil)
          return true
        end
        false
      end

      def draw(view)
        return unless @current_instance && @current_instance.valid?
        return if @corners.empty?

        # Desenha os cantos
        @corners.each_with_index do |corner, index|
          world_pt = corner.transform(@current_instance.transformation)

          # Cor baseada em hover
          if @hovered_corner == index
            view.drawing_color = Sketchup::Color.new(255, 165, 0)  # Laranja quando hover
            view.line_width = 4

            # Desenha círculo maior para highlight
            draw_circle(view, world_pt, HIGHLIGHT_SIZE * 1.5)

            # Desenha os eixos propostos
            draw_axes_preview(view, world_pt, @corner_transformations[index])
          else
            view.drawing_color = Sketchup::Color.new(66, 133, 244)  # Azul padrão
            view.line_width = 2
          end

          # Desenha círculo no canto
          draw_circle(view, world_pt, HIGHLIGHT_SIZE)
        end

        # Desenha bordas do bounding box para contexto
        draw_bounding_box_edges(view)
      end

      def draw_circle(view, center, radius)
        # Desenha um círculo na viewport
        points = []
        segments = 16
        (0..segments).each do |i|
          angle = (i / segments.to_f) * 2.0 * Math::PI
          # Círculo no plano XY
          offset = Geom::Vector3d.new(
            Math.cos(angle) * radius,
            Math.sin(angle) * radius,
            0
          )
          points << center.offset(offset)
        end

        view.draw(GL_LINE_STRIP, points)
      end

      def draw_axes_preview(view, origin, transformation_info)
        # Desenha preview dos eixos X, Y, Z na orientação proposta
        axis_length = 100.0.mm

        # Eixo X - Vermelho
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(255, 0, 0)
        x_end = origin.offset(transformation_info[:x_axis].transform(axis_length))
        view.draw(GL_LINES, origin, x_end)

        # Eixo Y - Verde
        view.drawing_color = Sketchup::Color.new(0, 255, 0)
        y_end = origin.offset(transformation_info[:y_axis].transform(axis_length))
        view.draw(GL_LINES, origin, y_end)

        # Eixo Z - Azul
        view.drawing_color = Sketchup::Color.new(0, 0, 255)
        z_end = origin.offset(transformation_info[:z_axis].transform(axis_length))
        view.draw(GL_LINES, origin, z_end)
      end

      def draw_bounding_box_edges(view)
        return unless @current_instance && @current_instance.valid?

        definition = @current_instance.definition
        bounds = definition.bounds

        view.line_stipple = ""
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(100, 100, 100, 128)  # Cinza semi-transparente

        # Desenha as arestas do bounding box
        (0..11).each do |edge_index|
          p1 = get_bbox_edge_point(bounds, edge_index, 0)
          p2 = get_bbox_edge_point(bounds, edge_index, 1)

          wp1 = p1.transform(@current_instance.transformation)
          wp2 = p2.transform(@current_instance.transformation)

          view.draw(GL_LINES, wp1, wp2)
        end
      end

      def get_bbox_edge_point(bounds, edge_index, point_index)
        # Retorna os pontos das 12 arestas de um bounding box
        edges = [
          [0, 1], [1, 2], [2, 3], [3, 0],  # Base inferior
          [4, 5], [5, 6], [6, 7], [7, 4],  # Base superior
          [0, 4], [1, 5], [2, 6], [3, 7]   # Arestas verticais
        ]

        corner_indices = edges[edge_index]
        corner_index = corner_indices[point_index]
        return bounds.corner(corner_index)
      end

      def apply_ucs_with_corner(corner_index)
        return unless @current_instance && @current_instance.valid?

        model = Sketchup.active_model
        definition = @current_instance.definition
        transformation_info = @corner_transformations[corner_index]

        model.start_operation("Reset UCS - #{definition.name}", true)

        begin
          new_origin = transformation_info[:origin]
          puts "Aplicando UCS para #{definition.name} com origem em #{new_origin}"

          # Verifica se tem carimbo
          had_stamp = has_stamp?(definition)
          if had_stamp
            stamps_removed = remove_stamps(definition)
            puts "  → #{stamps_removed} carimbo(s) removido(s)"
          end

          # Move geometria para origem
          move_to_origin = Geom::Transformation.translation(new_origin.vector_to(ORIGIN))

          # Rotação no eixo Z dependendo do canto escolhido
          angle = transformation_info[:rotation] || 0
          z_axis = Geom::Vector3d.new(0, 0, 1)
          rotation_tf = Geom::Transformation.rotation(ORIGIN, z_axis, angle)

          # Combina translação e rotação
          combined_tf = rotation_tf * move_to_origin

          puts "  → Rotação aplicada: #{(angle * 180.0 / Math::PI).round}°"

          # Aplica à definição
          entities_to_transform = definition.entities.to_a
          definition.entities.transform_entities(combined_tf, entities_to_transform)

          # Compensa nas instâncias
          compensation_tf = combined_tf.inverse

          all_instances = definition.instances.to_a
          all_instances.each do |inst|
            next unless inst.valid?
            old_tf = inst.transformation
            new_tf = old_tf * compensation_tf
            inst.transformation = new_tf
          end

          # Reaplica carimbo se tinha
          if had_stamp
            if reapply_stamp(definition)
              puts "  → Carimbo reaplicado"
            end
          end

          model.commit_operation
          puts "✓ #{definition.name} processado - #{all_instances.length} instância(s)"

        rescue => e
          model.abort_operation
          puts "Erro ao aplicar Reset UCS: #{e.message}"
          puts e.backtrace.first(5)
        end
      end

      # Constantes para carimbos
      STAMP_LAYER_NAME = "MU_Texto".freeze
      STAMP_ATTRIBUTE_DICT = "Rjv_StampName".freeze
      STAMP_GROUP_IDENTIFIER_KEY = "IsStampNameGroup".freeze

      def has_stamp?(definition)
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

      def remove_stamps(definition)
        return 0 unless definition && definition.entities

        model = Sketchup.active_model
        stamp_layer = model.layers[STAMP_LAYER_NAME]
        return 0 unless stamp_layer

        stamps_removed = 0
        definition.entities.to_a.each do |entity|
          if entity.is_a?(Sketchup::Group) &&
             entity.layer == stamp_layer &&
             entity.get_attribute(STAMP_ATTRIBUTE_DICT, STAMP_GROUP_IDENTIFIER_KEY)
            entity.erase! if entity.valid?
            stamps_removed += 1
          end
        end

        stamps_removed
      end

      def reapply_stamp(definition)
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
        top_face = find_top_face(definition.entities)
        if top_face
          Rjv::MockupTools::StampName.send(:create_stamp_as_group, definition, top_face, settings, stamp_layer)
          return true
        end

        false
      end

      def find_top_face(entities)
        faces = entities.grep(Sketchup::Face)
        return nil if faces.empty?

        # Encontra face com normal Z+ (maior área)
        top_faces = faces.select { |face| face.normal.z > 0.7 }
        return nil if top_faces.empty?

        top_faces.max_by(&:area)
      end

      def onSetCursor
        if @hovered_corner
          UI.set_cursor(641)  # Cursor de mão
        else
          UI.set_cursor(0)  # Cursor padrão
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        if @current_instance && @current_instance.valid?
          bb.add(@current_instance.bounds)
        else
          # Retorna bounding box do modelo inteiro se não há instância
          bb = Sketchup.active_model.bounds
        end
        bb
      end
    end

    module ResetUCS
      extend self

      # Constantes
      TOLERANCE = 1e-4
      ORIGIN = Geom::Point3d.new(0, 0, 0)
      
      # Função principal modular para resetar UCS de componentes
      # Parâmetros:
      #   instances: Array de ComponentInstance ou ComponentInstance único, ou nil para usar seleção atual
      #   options: Hash com opções (opcional)
      #     - detection_mode: :intelligent (padrão), :bottom_left, :center
      #     - use_sheet_detection: true (padrão) - usa detector de chapas para posicionamento inteligente
      #     - silent: não mostra mensagens de UI (padrão: false)
      #     - debug: mostra mensagens de debug (padrão: false)
      #
      # Retorna: Hash com resultados
      #   - success: true/false
      #   - processed: número de definições processadas
      #   - failed: hash com definições que falharam
      #   - instances_updated: número total de instâncias atualizadas
      #   - message: mensagem descritiva
      def reset_ucs_smart(instances = nil, options = {})
        # Configurações padrão
        opts = {
          detection_mode: :intelligent,
          use_sheet_detection: true,
          silent: false,
          debug: false
        }.merge(options)
        
        # Se não foram fornecidos componentes, usa a seleção atual
        if instances.nil?
          model = Sketchup.active_model
          selection = model.selection
          instances = selection.grep(Sketchup::ComponentInstance)
        else
          # Normaliza entrada para array
          instances = [instances] unless instances.is_a?(Array)
          instances = instances.compact.select { |i| i.is_a?(Sketchup::ComponentInstance) }
        end
        
        if instances.empty?
          message = "Nenhuma instância de componente encontrada"
          UI.messagebox(message) unless opts[:silent]
          return {
            success: false,
            processed: 0,
            failed: {},
            instances_updated: 0,
            message: message
          }
        end
        
        model = instances.first.model
        instances_by_definition = instances.group_by(&:definition)
        processed_definitions = 0
        failed_definitions = {}
        total_instances_updated = 0
        
        puts "DEBUG: Processando #{instances_by_definition.keys.length} definição(ões) com modo #{opts[:detection_mode]}" if opts[:debug]
        
        model.start_operation("Reset UCS Inteligente", true)
        
        begin
          instances_by_definition.each do |definition, selected_instances|
            result = process_single_definition(definition, opts)
            
            if result[:success]
              processed_definitions += 1
              total_instances_updated += result[:instances_updated]
              puts "DEBUG: ✅ #{definition.name} processado - #{result[:instances_updated]} instância(s) atualizadas" if opts[:debug]
            else
              failed_definitions[definition.name] = result[:message]
              puts "DEBUG: ❌ #{definition.name} falhou: #{result[:message]}" if opts[:debug]
            end
          end
          
          model.commit_operation
          
          # Mensagem de resultado
          unless opts[:silent]
            if processed_definitions > 0
              message = "#{processed_definitions} definição(ões) teve(ram) seu UCS ajustado."
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
          end
          
          return {
            success: failed_definitions.empty?,
            processed: processed_definitions,
            failed: failed_definitions,
            instances_updated: total_instances_updated,
            message: "#{processed_definitions} processadas, #{total_instances_updated} instâncias atualizadas"
          }
          
        rescue => e
          model.abort_operation
          error_msg = "Erro durante reset UCS: #{e.message}"
          puts "ERROR: #{error_msg}" if opts[:debug]
          UI.messagebox(error_msg) unless opts[:silent]
          
          return {
            success: false,
            processed: 0,
            failed: { "Erro geral" => e.message },
            instances_updated: 0,
            message: error_msg
          }
        end
      end
      
      # Função de conveniência para usar com seleção atual (mantém compatibilidade)
      def run
        return reset_ucs_smart(nil, { detection_mode: :intelligent, debug: false })
      end

      # Função interativa para escolher canto do UCS (sem pré-seleção necessária)
      def run_interactive
        model = Sketchup.active_model
        puts "Iniciando ferramenta interativa de Reset UCS - clique em componentes"
        tool = Rjv::MockupTools::ResetUCSCornerTool.new
        model.select_tool(tool)
      end
      
      # Função de conveniência para modo bottom-left clássico
      def reset_ucs_bottom_left(instances = nil, options = {})
        opts = { detection_mode: :bottom_left }.merge(options)
        return reset_ucs_smart(instances, opts)
      end
      
      # Função de conveniência para modo inteligente (padrão)
      def reset_ucs_intelligent(instances = nil, options = {})
        opts = { detection_mode: :intelligent }.merge(options)
        return reset_ucs_smart(instances, opts)
      end
      
      # Função de conveniência para centralizar UCS
      def reset_ucs_center(instances = nil, options = {})
        opts = { detection_mode: :center }.merge(options)
        return reset_ucs_smart(instances, opts)
      end
      
      private
      
      # Processa uma única definição de componente
      def process_single_definition(definition, opts = {})
        puts "\nDEBUG: === Processando definição: #{definition.name} ===" if opts[:debug]
        
        if definition.entities.count == 0
          return { success: false, message: "Definição vazia", instances_updated: 0 }
        end
        
        bounds = definition.bounds
        if bounds.empty?
          return { success: false, message: "Bounding Box vazia", instances_updated: 0 }
        end
        
        # Calcula novo ponto de origem baseado no modo de detecção
        new_origin = calculate_smart_origin(definition, bounds, opts)
        
        unless new_origin
          return { success: false, message: "Falha ao calcular nova origem", instances_updated: 0 }
        end
        
        puts "DEBUG: Nova origem calculada: #{new_origin}" if opts[:debug]
        
        # Verifica se já está na posição correta
        if new_origin.distance(ORIGIN) < TOLERANCE
          puts "DEBUG: UCS já está correto" if opts[:debug]
          return { 
            success: true, 
            message: "UCS já estava correto", 
            instances_updated: definition.instances.length 
          }
        end
        
        # Aplica as transformações
        result = apply_ucs_transformation(definition, new_origin, opts)
        
        return result
      end
      
      # Calcula a nova origem de forma inteligente
      def calculate_smart_origin(definition, bounds, opts = {})
        mode = opts[:detection_mode] || :intelligent
        
        puts "DEBUG: Modo de detecção: #{mode}" if opts[:debug]
        
        case mode
        when :bottom_left
          return calculate_bottom_left_origin(bounds, opts)
        when :center
          return bounds.center
        when :intelligent
          return calculate_intelligent_origin(definition, bounds, opts)
        else
          puts "DEBUG: Modo desconhecido, usando bottom_left" if opts[:debug]
          return calculate_bottom_left_origin(bounds, opts)
        end
      end
      
      # Calcula origem no canto inferior esquerdo (método clássico)
      def calculate_bottom_left_origin(bounds, opts = {})
        corners = (0..7).map { |i| bounds.corner(i) }
        bottom_left = corners.min_by { |c| [c.z, c.x, c.y] }
        
        puts "DEBUG: Bottom-left clássico: #{bottom_left}" if opts[:debug]
        return bottom_left
      end
      
      # Calcula origem de forma inteligente baseada na geometria
      def calculate_intelligent_origin(definition, bounds, opts = {})
        # 1. Primeiro, tenta usar detecção de chapas se disponível
        if opts[:use_sheet_detection] && defined?(Rjv::MockupTools::SheetDetector)
          puts "DEBUG: Tentando detecção inteligente com SheetDetector..." if opts[:debug]
          
          # Cria uma instância temporária para análise
          temp_instance = create_temp_instance_for_analysis(definition)
          
          if temp_instance
            sheet_result = SheetDetector.detect_sheets(temp_instance, { debug: false, silent: true })
            
            # Limpa a instância temporária
            temp_instance.erase! if temp_instance.valid?
            
            if sheet_result[:is_sheet]
              puts "DEBUG: Componente detectado como chapa - usando posicionamento específico para chapas" if opts[:debug]
              return calculate_sheet_origin(definition, bounds, sheet_result, opts)
            else
              puts "DEBUG: Componente NÃO é chapa - usando detecção geométrica geral" if opts[:debug]
            end
          end
        end
        
        # 2. Se não é chapa ou detector não disponível, usa análise geométrica
        return calculate_geometric_origin(definition, bounds, opts)
      end
      
      # Cria instância temporária para análise (sem afetar o modelo)
      def create_temp_instance_for_analysis(definition)
        begin
          # Encontra qualquer entidade pai onde possamos criar temporariamente
          model = definition.model
          temp_instance = model.entities.add_instance(definition, Geom::Transformation.new)
          return temp_instance
        rescue => e
          puts "DEBUG: Erro ao criar instância temporária: #{e.message}"
          return nil
        end
      end
      
      # Calcula origem específica para chapas
      def calculate_sheet_origin(definition, bounds, sheet_result, opts = {})
        puts "DEBUG: Calculando origem para chapa..." if opts[:debug]
        
        # Para chapas, posiciona na face inferior no canto que otimiza o layout
        faces = definition.entities.grep(Sketchup::Face)
        
        # Encontra face inferior (maior área com normal Z-)
        bottom_faces = faces.select { |face| face.normal.z < -0.7 }
        
        if bottom_faces.any?
          bottom_face = bottom_faces.max_by(&:area)
          
          # Encontra o vértice da face inferior mais próximo do canto inferior-esquerdo
          vertices = bottom_face.vertices.map(&:position)
          
          # Ordena por Z (menor primeiro), depois X (menor primeiro), depois Y (menor primeiro)
          best_vertex = vertices.min_by { |v| [v.z, v.x, v.y] }
          
          puts "DEBUG: Origem da chapa no vértice: #{best_vertex}" if opts[:debug]
          return best_vertex
        end
        
        # Fallback para método clássico se não encontrar face inferior
        puts "DEBUG: Fallback para bottom-left (não encontrou face inferior)" if opts[:debug]
        return calculate_bottom_left_origin(bounds, opts)
      end
      
      # Calcula origem baseada na análise geométrica geral
      def calculate_geometric_origin(definition, bounds, opts = {})
        puts "DEBUG: Calculando origem geométrica geral..." if opts[:debug]
        
        # Analisa a geometria para encontrar o ponto de apoio mais provável
        faces = definition.entities.grep(Sketchup::Face)
        edges = definition.entities.grep(Sketchup::Edge)
        
        if faces.any?
          # Procura faces horizontais (candidatas a base)
          horizontal_faces = faces.select { |face| 
            face.normal.z.abs > 0.8  # Normal próxima de vertical (face horizontal)
          }
          
          if horizontal_faces.any?
            # Encontra a face horizontal mais baixa
            bottom_faces = horizontal_faces.select { |face| face.normal.z < 0 }  # Normal apontando para baixo
            
            if bottom_faces.any?
              bottom_face = bottom_faces.min_by { |face| 
                # Usa o Z médio da face
                vertices = face.vertices.map(&:position)
                vertices.map(&:z).sum / vertices.length.to_f
              }
              
              # Pega o vértice mais "inferior-esquerdo" desta face
              vertices = bottom_face.vertices.map(&:position)
              best_vertex = vertices.min_by { |v| [v.z, v.x, v.y] }
              
              puts "DEBUG: Origem baseada em face de apoio: #{best_vertex}" if opts[:debug]
              return best_vertex
            end
          end
        end
        
        # Fallback: método clássico
        puts "DEBUG: Fallback para bottom-left clássico" if opts[:debug]
        return calculate_bottom_left_origin(bounds, opts)
      end
      
      # Aplica as transformações de UCS
      def apply_ucs_transformation(definition, new_origin, opts = {})
        puts "DEBUG: Aplicando transformação UCS..." if opts[:debug]
        
        begin
          # T1: Move a geometria interna para a origem [0,0,0]
          move_geometry_to_origin_tf = Geom::Transformation.translation(new_origin.vector_to(ORIGIN))
          
          # T2: Transformação para DESFAZER o movimento interno (compensação)
          keep_instance_in_place_tf = move_geometry_to_origin_tf.inverse
          
          # Aplica T1 à definição
          entities_to_transform = definition.entities.to_a
          definition.entities.transform_entities(move_geometry_to_origin_tf, entities_to_transform)
          
          # Aplica a compensação a TODAS as instâncias desta definição
          all_instances_of_def = definition.instances.to_a
          instances_updated = 0
          
          all_instances_of_def.each do |inst|
            next unless inst.valid?
            
            old_transform = inst.transformation
            # A nova transformação mantém a instância onde estava
            new_transform = old_transform * keep_instance_in_place_tf
            inst.transformation = new_transform
            instances_updated += 1
          end
          
          puts "DEBUG: #{instances_updated} instância(s) atualizadas" if opts[:debug]
          
          return {
            success: true,
            message: "UCS resetado com sucesso",
            instances_updated: instances_updated
          }
          
        rescue => e
          return {
            success: false,
            message: "Erro ao aplicar transformação: #{e.message}",
            instances_updated: 0
          }
        end
      end
      
      # Função para analisar componentes antes de aplicar reset
      def analyze_components(instances = nil)
        if instances.nil?
          model = Sketchup.active_model
          selection = model.selection
          instances = selection.grep(Sketchup::ComponentInstance)
        else
          instances = [instances] unless instances.is_a?(Array)
          instances = instances.compact.select { |i| i.is_a?(Sketchup::ComponentInstance) }
        end
        
        if instances.empty?
          puts "=== ANÁLISE DE UCS ==="
          puts "Nenhum componente selecionado"
          puts "====================="
          return
        end
        
        instances_by_definition = instances.group_by(&:definition)
        
        puts "\n=== ANÁLISE DE UCS ==="
        puts "Componentes selecionados: #{instances.length}"
        puts "Definições únicas: #{instances_by_definition.keys.length}"
        
        instances_by_definition.each_with_index do |(definition, def_instances), index|
          puts "\n#{index + 1}. Definição: '#{definition.name}'"
          puts "   Instâncias: #{def_instances.length}"
          puts "   Entidades: #{definition.entities.length}"
          
          if definition.entities.length > 0
            bounds = definition.bounds
            corners = (0..7).map { |i| bounds.corner(i) }
            current_origin = corners.min_by { |c| [c.z, c.x, c.y] }
            
            puts "   Bounds: #{bounds.width.to_mm.round(1)} x #{bounds.height.to_mm.round(1)} x #{bounds.depth.to_mm.round(1)}mm"
            puts "   Origem atual: #{current_origin}"
            puts "   Precisa reset: #{current_origin.distance(ORIGIN) > TOLERANCE ? 'SIM' : 'NÃO'}"
            
            # Testa detecção inteligente se disponível
            if defined?(Rjv::MockupTools::SheetDetector)
              temp_instance = create_temp_instance_for_analysis(definition)
              if temp_instance
                sheet_result = SheetDetector.detect_sheets(temp_instance, { debug: false, silent: true })
                puts "   É chapa: #{sheet_result[:is_sheet] ? 'SIM' : 'NÃO'}"
                temp_instance.erase! if temp_instance.valid?
              end
            end
          end
        end
        puts "======================\n"
        
        return instances_by_definition
      end
    end
  end
end