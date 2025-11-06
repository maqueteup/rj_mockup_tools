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

      def initialize(instances)
        @instances = instances
        @instances_by_definition = instances.group_by(&:definition)
        @current_instance = nil
        @corners = []
        @hovered_corner = nil
        @corner_transformations = {}
        @show_multiple_message = instances.length > 1
      end

      def activate
        @model = Sketchup.active_model
        @view = @model.active_view

        # Prepara os dados para cada definição
        prepare_corner_data

        Sketchup.status_text = "Reset UCS: Passe o mouse sobre um canto e clique para escolher a origem (Esc para cancelar)"
        puts "Ferramenta Reset UCS ativada - #{@instances.length} objeto(s)"
      end

      def deactivate(view)
        view.invalidate
      end

      def prepare_corner_data
        @instances_by_definition.each do |definition, def_instances|
          # Usa a primeira instância como referência para visualização
          @current_instance ||= def_instances.first

          bounds = definition.bounds

          # Calcula os 4 cantos no plano Z atual
          # Mantém Z constante, varia apenas X e Y
          min_pt = bounds.min
          max_pt = bounds.max

          # 4 cantos: (min_x, min_y), (max_x, min_y), (max_x, max_y), (min_x, max_y)
          corners_local = [
            Geom::Point3d.new(min_pt.x, min_pt.y, min_pt.z),  # Canto 0: inferior-esquerdo
            Geom::Point3d.new(max_pt.x, min_pt.y, min_pt.z),  # Canto 1: inferior-direito
            Geom::Point3d.new(max_pt.x, max_pt.y, min_pt.z),  # Canto 2: superior-direito
            Geom::Point3d.new(min_pt.x, max_pt.y, min_pt.z)   # Canto 3: superior-esquerdo
          ]

          @corners = corners_local

          # Para cada canto, calcula a transformação que atende a regra da mão direita
          calculate_corner_transformations(corners_local, bounds)
        end
      end

      def calculate_corner_transformations(corners, bounds)
        # Para cada canto, define uma orientação que atende a regra da mão direita
        # Estratégia: X tangente ao perímetro (sentido horário), Y aponta para dentro
        # Olhando do canto para o centro: X está à direita, Y está à frente
        # Regra da mão direita: X × Y = Z

        @corner_transformations = {}

        # Z sempre aponta para cima
        z_axis = Geom::Vector3d.new(0, 0, 1)

        # Canto 0: inferior-esquerdo (min_x, min_y)
        # Próximo canto no sentido horário: (max_x, min_y)
        # X tangente ao perímetro (direção horária): para a direita
        x_axis_0 = Geom::Vector3d.new(1, 0, 0)
        # Y perpendicular, apontando para dentro (direção do centro)
        y_axis_0 = Geom::Vector3d.new(0, 1, 0)
        @corner_transformations[0] = {
          origin: corners[0],
          x_axis: x_axis_0,
          y_axis: y_axis_0,
          z_axis: z_axis,
          label: "Inferior-Esquerdo (X→direita, Y→centro)"
        }

        # Canto 1: inferior-direito (max_x, min_y)
        # Próximo canto no sentido horário: (max_x, max_y)
        # X tangente ao perímetro (direção horária): para cima
        x_axis_1 = Geom::Vector3d.new(0, 1, 0)
        # Y perpendicular, apontando para dentro: para a esquerda
        y_axis_1 = Geom::Vector3d.new(-1, 0, 0)
        @corner_transformations[1] = {
          origin: corners[1],
          x_axis: x_axis_1,
          y_axis: y_axis_1,
          z_axis: z_axis,
          label: "Inferior-Direito (X→cima, Y→centro)"
        }

        # Canto 2: superior-direito (max_x, max_y)
        # Próximo canto no sentido horário: (min_x, max_y)
        # X tangente ao perímetro (direção horária): para a esquerda
        x_axis_2 = Geom::Vector3d.new(-1, 0, 0)
        # Y perpendicular, apontando para dentro: para baixo
        y_axis_2 = Geom::Vector3d.new(0, -1, 0)
        @corner_transformations[2] = {
          origin: corners[2],
          x_axis: x_axis_2,
          y_axis: y_axis_2,
          z_axis: z_axis,
          label: "Superior-Direito (X→esquerda, Y→centro)"
        }

        # Canto 3: superior-esquerdo (min_x, max_y)
        # Próximo canto no sentido horário: (min_x, min_y)
        # X tangente ao perímetro (direção horária): para baixo
        x_axis_3 = Geom::Vector3d.new(0, -1, 0)
        # Y perpendicular, apontando para dentro: para a direita
        y_axis_3 = Geom::Vector3d.new(1, 0, 0)
        @corner_transformations[3] = {
          origin: corners[3],
          x_axis: x_axis_3,
          y_axis: y_axis_3,
          z_axis: z_axis,
          label: "Superior-Esquerdo (X→baixo, Y→centro)"
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

      def onLButtonDown(flags, x, y, view)
        return unless @hovered_corner

        # Usuário clicou em um canto
        corner_index = @hovered_corner
        transformation_info = @corner_transformations[corner_index]

        puts "Canto escolhido: #{transformation_info[:label]}"

        # Aplica o reset UCS com este canto e orientação
        apply_ucs_with_corner(corner_index, transformation_info)

        # Finaliza a ferramenta
        @model.select_tool(nil)
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

      def apply_ucs_with_corner(corner_index, transformation_info)
        model = Sketchup.active_model

        model.start_operation("Reset UCS - Canto #{corner_index}", true)

        begin
          @instances_by_definition.each do |definition, def_instances|
            new_origin = transformation_info[:origin]

            puts "Aplicando UCS para #{definition.name} com origem em #{new_origin}"

            # Move geometria para origem
            move_to_origin = Geom::Transformation.translation(new_origin.vector_to(ORIGIN))

            # Aplica rotação baseada nos eixos escolhidos
            # Cria transformação de rotação baseada nos eixos
            rotation_tf = create_rotation_transformation(
              transformation_info[:x_axis],
              transformation_info[:y_axis],
              transformation_info[:z_axis]
            )

            # Combina translação e rotação
            combined_tf = rotation_tf * move_to_origin

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

            puts "✓ #{definition.name} processado - #{all_instances.length} instância(s)"
          end

          model.commit_operation
          Sketchup.status_text = "Reset UCS aplicado com sucesso"

        rescue => e
          model.abort_operation
          puts "Erro ao aplicar Reset UCS: #{e.message}"
          puts e.backtrace.first(5)
          UI.messagebox("Erro ao aplicar Reset UCS: #{e.message}")
        end
      end

      def create_rotation_transformation(x_axis, y_axis, z_axis)
        # Cria uma transformação de rotação baseada nos eixos fornecidos
        # Normaliza os eixos
        x_norm = x_axis.normalize
        y_norm = y_axis.normalize
        z_norm = z_axis.normalize

        # Cria matriz de transformação
        # A matriz é organizada em colunas: [x_axis, y_axis, z_axis, origin]
        matrix = [
          x_norm.x, x_norm.y, x_norm.z, 0,
          y_norm.x, y_norm.y, y_norm.z, 0,
          z_norm.x, z_norm.y, z_norm.z, 0,
          0, 0, 0, 1
        ]

        return Geom::Transformation.new(matrix)
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
        @instances.each do |inst|
          bb.add(inst.bounds) if inst.valid?
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

      # Função interativa para escolher canto do UCS
      def run_interactive
        model = Sketchup.active_model
        selection = model.selection

        # Suporta objetos aninhados e busca componentes MakettePro
        instances = []
        selection.each do |entity|
          if entity.is_a?(Sketchup::ComponentInstance)
            # Verifica se é MakettePro ou adiciona diretamente
            instances << entity
          elsif entity.is_a?(Sketchup::InstancePath)
            # Procura por componentes MakettePro no path
            makettepro = find_makettepro_in_path(entity)
            if makettepro
              instances << makettepro unless instances.include?(makettepro)
            else
              # Se não encontrou MakettePro, usa o último elemento
              leaf = entity.to_a.last
              instances << leaf if leaf.is_a?(Sketchup::ComponentInstance)
            end
          end
        end

        if instances.empty?
          UI.messagebox("Selecione pelo menos um componente para resetar o UCS.")
          return
        end

        puts "Iniciando ferramenta interativa de Reset UCS para #{instances.length} componente(s)..."
        tool = Rjv::MockupTools::ResetUCSCornerTool.new(instances)
        model.select_tool(tool)
      end

      # Encontra o primeiro componente MakettePro no path (do mais profundo para o mais raso)
      def find_makettepro_in_path(path)
        path_array = path.to_a.reverse  # Começa do mais profundo
        path_array.each do |entity|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          definition = entity.definition
          if definition.get_attribute("MakettePro", "identifier") == "MakettePro"
            return entity
          end
        end
        nil
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