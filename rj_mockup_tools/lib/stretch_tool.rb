# lib/stretch_tool.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    class StretchTool
      def initialize
        @model = Sketchup.active_model
        reset_tool
      end

      def activate
        @initial_selection = @model.selection.to_a
        if @initial_selection.empty?
          UI.messagebox("Por favor, selecione um ou mais componentes/grupos primeiro.")
          @model.select_tool(nil)
          return
        end
        reset_tool
        setup_virtual_faces
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(reason, view)
        reset_tool
        view.invalidate
      end

      def reset_tool
        @state = :selecting_grip
        @ip = Sketchup::InputPoint.new
        @ip_start = Sketchup::InputPoint.new
        @highlighted_grip = nil
        @grip_info = nil
        @influence_bb = nil
        @stretch_data = { entities_to_move: [], vertices_to_stretch: [] }
        @stretch_vector = Geom::Vector3d.new(0,0,0)
        @selection_bb = nil
        @virtual_faces = []
        @bidirectional_mode = false
        @opposite_influence_bb = nil
        
        Sketchup.set_status_text("1. Clique em uma das faces da bounding box para definir o 'grip'.")
      end
      
      def enableVCB?
        return true if @state == :defining_depth || @state == :defining_stretch_vector
        false
      end

      def onUserText(text, view)
        return unless text.is_a?(String) && !text.empty?
        begin; value = text.to_l; rescue; UI.beep; return; end

        if @state == :defining_depth
          @influence_bb = create_influence_area(@grip_info, value)
          advance_to_stretch_vector_state(view)
        elsif @state == :defining_stretch_vector
          vector = @grip_info[:normal].clone
          if vector.length > 1e-9
            vector.length = value
            apply_stretch(vector)
            @model.select_tool(nil)
          else
            UI.beep
          end
        end
      end

      def onMouseMove(flags, x, y, view)
        # Detecta se Ctrl está pressionado para modo bidirecional
        @bidirectional_mode = (flags & MK_CONTROL) != 0
        
        case @state
        when :selecting_grip
          @highlighted_grip = detect_virtual_face_at_cursor(x, y, view)
          view.invalidate
        when :defining_depth
          @ip.pick(view, x, y)
          
          mouse_vec = @grip_info[:start_point].vector_to(@ip.position)
          depth = mouse_vec.dot(@grip_info[:normal].reverse)
          depth = [depth, 0].max
          
          @influence_bb = create_influence_area(@grip_info, depth)
          Sketchup.vcb_value = depth.to_s
          view.invalidate
        when :defining_stretch_vector
          @ip.pick(view, x, y)
          
          mouse_vec = @grip_info[:start_point].vector_to(@ip.position)
          distance = mouse_vec.dot(@grip_info[:normal])
          
          if distance.abs > 1e-9
            @stretch_vector = @grip_info[:normal].clone
            @stretch_vector.length = distance.abs
            @stretch_vector.reverse! if distance < 0
          else
            @stretch_vector = Geom::Vector3d.new(0,0,0)
          end
          
          update_status_text_for_stretch_mode
          Sketchup.vcb_value = distance.to_s
          view.invalidate
        end
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when :selecting_grip
          if @highlighted_grip
            @grip_info = @highlighted_grip
            @state = :defining_depth
            @highlighted_grip = nil
            Sketchup.set_status_text("2. Mova o mouse para definir a área de influência (profundidade) ou digite um valor e tecle Enter.")
            view.invalidate
          end
        when :defining_depth
          advance_to_stretch_vector_state(view)
        when :defining_stretch_vector
          if @stretch_vector.length > 1e-9
            apply_stretch(@stretch_vector)
            @model.select_tool(nil)
          else
            UI.beep
          end
        end
      end

      def draw(view)
        case @state
        when :selecting_grip
          @virtual_faces.each do |face_info|
            if face_info == @highlighted_grip
              view.line_stipple = ""
              view.line_width = 3
              view.drawing_color = "Red"
              view.draw(GL_LINE_LOOP, face_info[:points])
              view.drawing_color = [255, 0, 0, 100]
              view.draw(GL_POLYGON, face_info[:points])
            else
              view.line_stipple = "-"
              view.line_width = 1
              view.drawing_color = [100, 100, 100, 150]
              view.draw(GL_LINE_LOOP, face_info[:points])
            end
          end
        when :defining_depth
          draw_grip_feedback(view)
          draw_bb(view, @influence_bb, [0, 255, 0, 100]) if @influence_bb
          draw_depth_feedback(view)
        when :defining_stretch_vector
          draw_grip_feedback(view)
          draw_bb(view, @influence_bb, [255, 165, 0, 100]) if @influence_bb
          draw_stretch_feedback(view)
          draw_stretch_arrow(view)
        end
        
        @ip.draw(view) if @ip && @ip.valid?
      end
      
      private

      def setup_virtual_faces
        @selection_bb = calculate_selection_bounding_box(@initial_selection)
        unless @selection_bb&.valid?
          UI.messagebox("Erro: Não foi possível calcular a bounding box da seleção.")
          @model.select_tool(nil)
          return
        end

        @virtual_faces = create_virtual_faces(@selection_bb)
      end

      def create_virtual_faces(bb)
        faces_data = [
          { normal: Geom::Vector3d.new(1, 0, 0), name: "direita" },
          { normal: Geom::Vector3d.new(-1, 0, 0), name: "esquerda" },
          { normal: Geom::Vector3d.new(0, 1, 0), name: "frente" },
          { normal: Geom::Vector3d.new(0, -1, 0), name: "trás" },
          { normal: Geom::Vector3d.new(0, 0, 1), name: "cima" },
          { normal: Geom::Vector3d.new(0, 0, -1), name: "baixo" }
        ]
        
        virtual_faces = []
        faces_data.each do |face_data|
          points = get_bb_face_points(bb, face_data[:normal])
          next if points.empty?
          
          face_center = calculate_face_center(points)
          
          virtual_faces << {
            normal: face_data[:normal],
            start_point: face_center,
            points: points,
            name: face_data[:name]
          }
        end
        
        virtual_faces
      end

      def calculate_face_center(points)
        center = Geom::Point3d.new(0, 0, 0)
        points.each { |pt| center = center + pt.to_a }
        Geom::Point3d.new(center.x / points.length, center.y / points.length, center.z / points.length)
      end
      
      def detect_virtual_face_at_cursor(x, y, view)
        @virtual_faces.each do |face_info|
          screen_points = face_info[:points].map { |pt| view.screen_coords(pt) }
          return face_info if point_in_polygon?([x, y], screen_points)
        end
        nil
      end
      
      def point_in_polygon?(point, polygon_points)
        x, y = point
        inside = false
        j = polygon_points.length - 1
        
        polygon_points.each_with_index do |vertex, i|
          xi, yi = vertex.x, vertex.y
          xj, yj = polygon_points[j].x, polygon_points[j].y
          
          if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            inside = !inside
          end
          j = i
        end
        
        inside
      end
      
      def calculate_selection_bounding_box(selection)
        bb = Geom::BoundingBox.new
        selection.each do |entity|
          bb.add(entity.bounds) if entity.respond_to?(:bounds)
        end
        bb.valid? ? bb : nil
      end
      
      def get_bb_face_points(bb, normal)
        min_x, min_y, min_z = bb.min.to_a
        max_x, max_y, max_z = bb.max.to_a
        
        case normal.to_a
        when [1, 0, 0]   # Face direita (+X)
          [
            Geom::Point3d.new(max_x, min_y, min_z),
            Geom::Point3d.new(max_x, max_y, min_z),
            Geom::Point3d.new(max_x, max_y, max_z),
            Geom::Point3d.new(max_x, min_y, max_z)
          ]
        when [-1, 0, 0]  # Face esquerda (-X)
          [
            Geom::Point3d.new(min_x, min_y, min_z),
            Geom::Point3d.new(min_x, min_y, max_z),
            Geom::Point3d.new(min_x, max_y, max_z),
            Geom::Point3d.new(min_x, max_y, min_z)
          ]
        when [0, 1, 0]   # Face frente (+Y)
          [
            Geom::Point3d.new(min_x, max_y, min_z),
            Geom::Point3d.new(max_x, max_y, min_z),
            Geom::Point3d.new(max_x, max_y, max_z),
            Geom::Point3d.new(min_x, max_y, max_z)
          ]
        when [0, -1, 0]  # Face trás (-Y)
          [
            Geom::Point3d.new(min_x, min_y, min_z),
            Geom::Point3d.new(min_x, min_y, max_z),
            Geom::Point3d.new(max_x, min_y, max_z),
            Geom::Point3d.new(max_x, min_y, min_z)
          ]
        when [0, 0, 1]   # Face cima (+Z)
          [
            Geom::Point3d.new(min_x, min_y, max_z),
            Geom::Point3d.new(min_x, max_y, max_z),
            Geom::Point3d.new(max_x, max_y, max_z),
            Geom::Point3d.new(max_x, min_y, max_z)
          ]
        when [0, 0, -1]  # Face baixo (-Z)
          [
            Geom::Point3d.new(min_x, min_y, min_z),
            Geom::Point3d.new(max_x, min_y, min_z),
            Geom::Point3d.new(max_x, max_y, min_z),
            Geom::Point3d.new(min_x, max_y, min_z)
          ]
        else
          []
        end
      end

      def advance_to_stretch_vector_state(view)
        @state = :defining_stretch_vector
        analyze_geometry_for_stretch
        
        # Se modo bidirecional, prepara área oposta
        if @bidirectional_mode
          setup_bidirectional_areas
        end
        
        update_status_text_for_stretch_mode
      end

      def update_status_text_for_stretch_mode
        if @bidirectional_mode
          Sketchup.set_status_text("3. [MODO BIDIRECIONAL] Mova o mouse para esticar (Ctrl pressionado = contrai lado oposto)")
        else
          Sketchup.set_status_text("3. Mova o mouse para onde a face selecionada deve ir (Ctrl = modo bidirecional)")
        end
      end

      def setup_bidirectional_areas
        return unless @grip_info && @selection_bb
        
        puts "Configurando modo bidirecional..."
        
        # Calcula a área oposta baseada no grip selecionado
        opposite_grip = find_opposite_grip(@grip_info)
        
        if opposite_grip
          # Cria área de influência oposta (mesmo tamanho da área principal)
          depth = calculate_influence_depth
          @opposite_influence_bb = create_influence_area(opposite_grip, depth)
          puts "  -> Área oposta criada com profundidade: #{depth}"
        else
          puts "  -> Aviso: Não foi possível encontrar área oposta"
          @bidirectional_mode = false
        end
      end

      def find_opposite_grip(current_grip)
        # Encontra a face oposta baseada na normal
        opposite_normal = current_grip[:normal].reverse
        
        @virtual_faces.find { |face| face[:normal] == opposite_normal }
      end

      def calculate_influence_depth
        return 0 unless @influence_bb && @selection_bb
        
        # Usa a mesma profundidade da área principal
        # Ou calcula baseado na geometria
        @selection_bb.diagonal * 0.3  # 30% da diagonal como padrão
      end
      
      def analyze_geometry_for_stretch
        puts "\n=== ANÁLISE DE GEOMETRIA PARA STRETCH ==="
        
        # Limpa dados anteriores
        @stretch_data = { entities_to_move: [], vertices_to_stretch: [] }
        
        # Analisa cada entidade da seleção inicial
        @initial_selection.each_with_index do |entity, index|
          puts "Analisando entidade #{index + 1}: #{entity.class}"
          analyze_entity(entity, Geom::Transformation.new, @influence_bb)
        end
        
        # Remove duplicatas e conflitos
        resolve_conflicts
        
        puts "Resultado da análise:"
        puts "  - Entidades para mover: #{@stretch_data[:entities_to_move].length}"
        puts "  - Vértices para esticar: #{@stretch_data[:vertices_to_stretch].length}"
        puts "=== FIM DA ANÁLISE ===\n"
      end

      def analyze_entity(entity, parent_transform, influence_bb)
        return unless entity.respond_to?(:bounds)
        
        # Transformação acumulada até este nível
        current_transform = parent_transform * (entity.transformation || Geom::Transformation.new)
        
        # Bounding box da entidade em coordenadas mundiais
        world_bb = get_world_bounding_box(entity, parent_transform)
        
        # Verifica se a entidade toda está dentro da área de influência
        if influence_bb.contains?(world_bb)
          puts "  -> Entidade completamente dentro: movendo toda"
          @stretch_data[:entities_to_move] << {
            entity: entity,
            parent_transform: parent_transform,
            world_transform: current_transform,
            context: get_entity_context(entity)
          }
          return # Não precisa analisar internamente se vai mover toda
        end
        
        # Se intersecta, precisa analisar internamente
        if influence_bb.intersect(world_bb).valid?
          puts "  -> Entidade intersecta: analisando internamente"
          
          # Para componentes/grupos, torna único se necessário ANTES da análise
          make_unique_if_needed(entity)
          
          # Analisa a geometria interna
          analyze_internal_geometry(entity, current_transform, influence_bb)
          
          # Analisa sub-componentes aninhados
          if entity.respond_to?(:definition)
            nested_entities = entity.definition.entities.select { |e| 
              e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) 
            }
            nested_entities.each do |nested_entity|
              analyze_entity(nested_entity, current_transform, influence_bb)
            end
          end
        else
          puts "  -> Entidade fora da área de influência: ignorando"
        end
      end

      def get_world_bounding_box(entity, parent_transform)
        # Para componentes/grupos, precisa transformar a bounding box local
        if entity.respond_to?(:definition)
          local_bb = entity.definition.bounds
          transform_bounding_box(local_bb, parent_transform * entity.transformation)
        else
          # Para outras entidades, bounds já está em coordenadas do contexto pai
          transform_bounding_box(entity.bounds, parent_transform)
        end
      end

      def transform_bounding_box(local_bb, transform)
        return local_bb unless transform
        
        new_bb = Geom::BoundingBox.new
        8.times { |i| new_bb.add(local_bb.corner(i).transform(transform)) }
        new_bb
      end

      def make_unique_if_needed(entity)
        if entity.is_a?(Sketchup::ComponentInstance) && 
           entity.definition.count_instances > 1
          puts "    -> Tornando componente único (#{entity.definition.count_instances} instâncias)"
          entity.make_unique
        end
      end

      def analyze_internal_geometry(entity, world_transform, influence_bb)
        return unless entity.respond_to?(:definition)
        
        definition = entity.definition
        
        # Analisa todos os vértices da geometria interna
        definition.entities.grep(Sketchup::Edge).each do |edge|
          edge.vertices.each do |vertex|
            world_pos = vertex.position.transform(world_transform)
            
            if influence_bb.contains?(world_pos)
              @stretch_data[:vertices_to_stretch] << {
                vertex: vertex,
                world_transform: world_transform,
                container: entity,
                definition: definition,
                world_position: world_pos
              }
            end
          end
        end
      end

      def resolve_conflicts
        # Remove vértices que pertencem a entidades que serão movidas inteiras
        entities_to_move_set = Set.new(@stretch_data[:entities_to_move].map { |info| info[:entity] })
        
        @stretch_data[:vertices_to_stretch].reject! do |vertex_info|
          # Se o container do vértice vai ser movido inteiro, remove o vértice
          entities_to_move_set.include?(vertex_info[:container])
        end
        
        # Remove vértices duplicados (mesmo vértice físico)
        @stretch_data[:vertices_to_stretch].uniq! { |info| info[:vertex] }
        
        puts "Após resolução de conflitos:"
        puts "  - Entidades para mover: #{@stretch_data[:entities_to_move].length}"
        puts "  - Vértices para esticar: #{@stretch_data[:vertices_to_stretch].length}"
      end

      def apply_stretch(vector)
        return if vector.nil? || vector.length < 1e-9
        
        entities_to_move = @stretch_data[:entities_to_move]
        vertices_to_stretch = @stretch_data[:vertices_to_stretch]
        
        if entities_to_move.empty? && vertices_to_stretch.empty?
          puts "Nada para transformar."
          return
        end

        @model.start_operation("Stretch#{@bidirectional_mode ? ' Bidirecional' : ''}", true)
        
        begin
          if @bidirectional_mode
            apply_bidirectional_stretch(vector)
          else
            apply_unidirectional_stretch(vector)
          end
          
          @model.commit_operation
          puts "Stretch aplicado com sucesso!"
          
        rescue => e
          puts "Erro durante o stretch: #{e.message}"
          puts e.backtrace.join("\n")
          @model.abort_operation
        end
      end

      def apply_unidirectional_stretch(vector)
        entities_to_move = @stretch_data[:entities_to_move]
        vertices_to_stretch = @stretch_data[:vertices_to_stretch]
        
        # Move entidades completas (agrupadas por contexto)
        unless entities_to_move.empty?
          puts "Movendo #{entities_to_move.length} entidade(s) completa(s)..."
          transform_entities_by_context(entities_to_move, vector)
        end
        
        # Estica vértices individuais
        unless vertices_to_stretch.empty?
          puts "Esticando #{vertices_to_stretch.length} vértice(s)..."
          stretch_vertices(vertices_to_stretch, vector)
        end
      end

      def apply_bidirectional_stretch(vector)
        puts "Aplicando stretch bidirecional..."
        
        # Analisa geometria para ambos os lados
        primary_data = @stretch_data
        opposite_data = analyze_opposite_side
        
        # Aplica stretch no lado principal (expansão)
        unless primary_data[:entities_to_move].empty?
          puts "Expandindo #{primary_data[:entities_to_move].length} entidade(s)..."
          transform_entities_by_context(primary_data[:entities_to_move], vector)
        end
        
        unless primary_data[:vertices_to_stretch].empty?
          puts "Expandindo #{primary_data[:vertices_to_stretch].length} vértice(s)..."
          stretch_vertices(primary_data[:vertices_to_stretch], vector)
        end
        
        # Aplica stretch no lado oposto (contração)
        opposite_vector = vector.reverse.clone
        opposite_vector.length = vector.length * 0.5  # 50% da intensidade
        
        unless opposite_data[:entities_to_move].empty?
          puts "Contraindo #{opposite_data[:entities_to_move].length} entidade(s)..."
          transform_entities_by_context(opposite_data[:entities_to_move], opposite_vector)
        end
        
        unless opposite_data[:vertices_to_stretch].empty?
          puts "Contraindo #{opposite_data[:vertices_to_stretch].length} vértice(s)..."
          stretch_vertices(opposite_data[:vertices_to_stretch], opposite_vector)
        end
      end

      def analyze_opposite_side
        return { entities_to_move: [], vertices_to_stretch: [] } unless @opposite_influence_bb
        
        puts "Analisando lado oposto para contração..."
        opposite_data = { entities_to_move: [], vertices_to_stretch: [] }
        
        @initial_selection.each do |entity|
          analyze_entity_for_area(entity, Geom::Transformation.new, @opposite_influence_bb, opposite_data)
        end
        
        # Remove conflitos (evita que mesmas entidades sejam processadas duas vezes)
        resolve_bidirectional_conflicts(opposite_data)
        
        puts "  -> Entidades opostas para mover: #{opposite_data[:entities_to_move].length}"
        puts "  -> Vértices opostos para esticar: #{opposite_data[:vertices_to_stretch].length}"
        
        opposite_data
      end

      def analyze_entity_for_area(entity, parent_transform, influence_bb, data_storage)
        return unless entity.respond_to?(:bounds)
        
        current_transform = parent_transform * (entity.transformation || Geom::Transformation.new)
        world_bb = get_world_bounding_box(entity, parent_transform)
        
        if influence_bb.contains?(world_bb)
          data_storage[:entities_to_move] << {
            entity: entity,
            parent_transform: parent_transform,
            world_transform: current_transform,
            context: get_entity_context(entity)
          }
          return
        end
        
        if influence_bb.intersect(world_bb).valid?
          make_unique_if_needed(entity)
          analyze_internal_geometry_for_area(entity, current_transform, influence_bb, data_storage)
          
          if entity.respond_to?(:definition)
            nested_entities = entity.definition.entities.select { |e| 
              e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) 
            }
            nested_entities.each do |nested_entity|
              analyze_entity_for_area(nested_entity, current_transform, influence_bb, data_storage)
            end
          end
        end
      end

      def analyze_internal_geometry_for_area(entity, world_transform, influence_bb, data_storage)
        return unless entity.respond_to?(:definition)
        
        definition = entity.definition
        definition.entities.grep(Sketchup::Edge).each do |edge|
          edge.vertices.each do |vertex|
            world_pos = vertex.position.transform(world_transform)
            
            if influence_bb.contains?(world_pos)
              data_storage[:vertices_to_stretch] << {
                vertex: vertex,
                world_transform: world_transform,
                container: entity,
                definition: definition,
                world_position: world_pos
              }
            end
          end
        end
      end

      def resolve_bidirectional_conflicts(opposite_data)
        # Remove entidades que já estão sendo processadas no lado principal
        primary_entities = Set.new(@stretch_data[:entities_to_move].map { |info| info[:entity] })
        primary_vertices = Set.new(@stretch_data[:vertices_to_stretch].map { |info| info[:vertex] })
        
        opposite_data[:entities_to_move].reject! { |info| primary_entities.include?(info[:entity]) }
        opposite_data[:vertices_to_stretch].reject! { |info| primary_vertices.include?(info[:vertex]) }
        
        # Remove duplicatas internas
        opposite_data[:vertices_to_stretch].uniq! { |info| info[:vertex] }
      end

      def transform_entities_by_context(entities_info, global_vector)
        # Agrupa entidades pelo seu contexto pai (parent entities)
        entities_by_context = entities_info.group_by do |info|
          get_entity_context(info[:entity])
        end
        
        puts "Transformando entidades em #{entities_by_context.keys.length} contexto(s) diferente(s):"
        
        entities_by_context.each do |context, entity_infos|
          puts "  -> Contexto: #{context.class} (#{entity_infos.length} entidades)"
          
          # Para cada contexto, calcula o vetor local apropriado
          first_info = entity_infos.first
          local_vector = calculate_local_vector(global_vector, first_info[:parent_transform])
          
          # Aplica a transformação a todas as entidades deste contexto
          entities = entity_infos.map { |info| info[:entity] }
          
          begin
            context.transform_entities(local_vector, entities)
            puts "    ✓ Transformadas #{entities.length} entidades"
          rescue => e
            puts "    ✗ Erro ao transformar entidades neste contexto: #{e.message}"
            
            # Fallback: tenta transformar uma por uma
            entities.each_with_index do |entity, idx|
              begin
                context.transform_entities(local_vector, [entity])
                puts "      ✓ Entidade #{idx + 1} transformada individualmente"
              rescue => individual_error
                puts "      ✗ Falha na entidade #{idx + 1}: #{individual_error.message}"
              end
            end
          end
        end
      end

      def get_entity_context(entity)
        # Retorna o contexto (entities collection) onde a entidade vive
        if entity.respond_to?(:parent) && entity.parent
          if entity.parent.respond_to?(:entities)
            return entity.parent.entities
          elsif entity.parent.is_a?(Sketchup::Model)
            return entity.parent.active_entities
          end
        end
        
        # Fallback para o contexto ativo do modelo
        @model.active_entities
      end

      def calculate_local_vector(global_vector, parent_transform)
        # Se não há transformação pai, o vetor global é o local
        return global_vector if parent_transform.nil? || parent_transform.identity?
        
        # Transforma o vetor global para o espaço local do contexto
        global_vector.transform(parent_transform.inverse)
      end

      def stretch_vertices(vertices_info, global_vector)
        # Agrupa vértices por definição para otimizar transformações
        vertices_by_definition = vertices_info.group_by { |info| info[:definition] }
        
        vertices_by_definition.each do |definition, vertex_infos|
          # Calcula o vetor local para esta definição
          # Usa a transformação do primeiro vértice (todos devem ter a mesma para a mesma definição)
          world_transform = vertex_infos.first[:world_transform]
          local_vector = global_vector.transform(world_transform.inverse)
          
          # Aplica a transformação a todos os vértices desta definição
          vertices = vertex_infos.map { |info| info[:vertex] }
          definition.entities.transform_entities(local_vector, vertices)
          
          puts "  -> Esticados #{vertices.length} vértices na definição #{definition}"
        end
      end

      def draw_grip_feedback(view)
        return unless @grip_info&.[](:points)
        
        view.line_stipple = ""
        view.line_width = 2
        view.drawing_color = "Red"
        view.draw(GL_LINE_LOOP, @grip_info[:points])
        view.drawing_color = [255, 0, 0, 50]
        view.draw(GL_POLYGON, @grip_info[:points])
      end

      def draw_depth_feedback(view)
        return unless @grip_info && @ip.valid?
        
        mouse_vec = @grip_info[:start_point].vector_to(@ip.position)
        depth = mouse_vec.dot(@grip_info[:normal].reverse)
        depth = [depth, 0].max
        
        projected_point = @grip_info[:start_point].offset(@grip_info[:normal].reverse, depth)
        
        view.line_stipple = "-"
        view.line_width = 2
        view.drawing_color = "Green"
        view.draw_line(@grip_info[:start_point], projected_point)
        
        view.line_stipple = ":"
        view.line_width = 1
        view.drawing_color = [150, 150, 150, 100]
        view.draw_line(projected_point, @ip.position)
        
        view.drawing_color = "Green"
        view.draw_points([projected_point], 8, 1, "Green")
      end

      def draw_stretch_feedback(view)
        return unless @grip_info && @ip.valid?
        
        mouse_vec = @grip_info[:start_point].vector_to(@ip.position)
        distance = mouse_vec.dot(@grip_info[:normal])
        
        projected_point = @grip_info[:start_point].offset(@grip_info[:normal], distance)
        
        view.line_stipple = "-"
        view.line_width = 2
        view.drawing_color = "Blue"
        view.draw_line(@grip_info[:start_point], projected_point)
        
        view.line_stipple = ":"
        view.line_width = 1
        view.drawing_color = [150, 150, 150, 80]
        view.draw_line(projected_point, @ip.position)
        
        view.drawing_color = "Blue"
        view.draw_points([projected_point], 6, 1, "Blue")
      end

      def draw_stretch_arrow(view)
        return unless @grip_info && @stretch_vector && @stretch_vector.length > 1e-9
        
        view.line_stipple = ""
        view.line_width = 3
        view.drawing_color = "Blue"
        start_point = @grip_info[:start_point]
        end_point = start_point.offset(@stretch_vector)
        view.draw_line(start_point, end_point)
        
        arrow_size = (@selection_bb.diagonal * 0.02).to_l
        arrow_points = create_arrow_head(start_point, end_point, arrow_size)
        view.draw(GL_TRIANGLES, arrow_points) if arrow_points.length == 3
        
        # Se modo bidirecional, desenha seta oposta
        if @bidirectional_mode && @opposite_influence_bb
          draw_opposite_stretch_arrow(view)
        end
      end

      def draw_opposite_stretch_arrow(view)
        return unless @grip_info && @stretch_vector && @opposite_influence_bb
        
        # Encontra o ponto central da área oposta
        opposite_center = @opposite_influence_bb.center
        
        # Calcula vetor oposto (metade da intensidade)
        opposite_vector = @stretch_vector.reverse.clone
        opposite_vector.length = @stretch_vector.length * 0.5
        
        # Desenha seta de contração
        view.line_stipple = "-"
        view.line_width = 2
        view.drawing_color = "Orange"
        
        start_point = opposite_center
        end_point = start_point.offset(opposite_vector)
        view.draw_line(start_point, end_point)
        
        # Seta menor para indicar contração
        arrow_size = (@selection_bb.diagonal * 0.015).to_l
        arrow_points = create_arrow_head(start_point, end_point, arrow_size)
        view.draw(GL_TRIANGLES, arrow_points) if arrow_points.length == 3
        
        # Desenha área oposta semi-transparente
        view.drawing_color = [255, 165, 0, 60]  # Laranja transparente
        draw_bb(view, @opposite_influence_bb, [255, 165, 0, 60])
      end

      def create_influence_area(grip_info, depth)
        return nil unless grip_info && depth >= 0 && grip_info[:points]
        
        influence_bb = Geom::BoundingBox.new
        
        grip_info[:points].each do |point|
          influence_bb.add(point)
          influence_bb.add(point.offset(grip_info[:normal].reverse, depth))
        end
        
        influence_bb
      end
      
      def create_arrow_head(start_point, end_point, size)
        return [] if start_point.distance(end_point) < 1e-9
        
        direction = start_point.vector_to(end_point)
        return [] if direction.length < 1e-9
        
        direction.normalize!
        
        if direction.parallel?(Z_AXIS)
          perp1 = direction.cross(X_AXIS)
        else
          perp1 = direction.cross(Z_AXIS)
        end
        perp1.normalize!
        perp1.length = size
        
        perp2 = direction.cross(perp1)
        perp2.normalize!
        perp2.length = size
        
        back_direction = direction.reverse
        back_direction.length = size * 2
        arrow_base = end_point.offset(back_direction)
        
        [
          end_point,
          arrow_base.offset(perp1),
          arrow_base.offset(perp2)
        ]
      end
      
      def draw_bb(view, bb, color)
        return unless bb && bb.valid?
        
        view.drawing_color = color
        points = []
        8.times { |i| points << bb.corner(i) }
        view.draw(GL_QUADS, [
          points[0], points[1], points[3], points[2],
          points[4], points[5], points[7], points[6],
          points[0], points[2], points[6], points[4],
          points[1], points[5], points[7], points[3],
          points[0], points[4], points[5], points[1],
          points[2], points[3], points[7], points[6]
        ])
        
        view.line_stipple = ""
        view.line_width = 1
        view.drawing_color = [color[0], color[1], color[2], 255]
        view.draw_lines(points[0], points[1], points[1], points[3], points[3], points[2], points[2], points[0])
        view.draw_lines(points[4], points[5], points[5], points[7], points[7], points[6], points[6], points[4])
        view.draw_lines(points[0], points[4], points[1], points[5], points[2], points[6], points[3], points[7])
      end

    end # class StretchTool
  end # module MockupTools
end # module Rjv