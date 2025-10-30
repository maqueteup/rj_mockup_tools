# lib/stretch_face_tool.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    class StretchFaceTool
      # Constantes de vetores de eixo
      X_AXIS = Geom::Vector3d.new(1, 0, 0).freeze
      Y_AXIS = Geom::Vector3d.new(0, 1, 0).freeze
      Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze

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
        @selection_bb = calculate_selection_bounding_box(@initial_selection)
        unless @selection_bb&.valid?
          UI.messagebox("Erro: Não foi possível calcular a bounding box da seleção.")
          @model.select_tool(nil)
          return
        end
        
        puts "StretchFaceTool ativada. Seleção: #{@initial_selection.length} entidades"
        puts "BoundingBox da seleção: #{@selection_bb.min} -> #{@selection_bb.max}"
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(reason, view)
        # ✅ NÃO RESETA COMPLETAMENTE - PERMITE REUTILIZAÇÃO
        if @state == :defining_stretch_vector
          # Se está no último estado, volta para selecionar face
          @state = :selecting_face
          @selected_face_info = nil
          @reference_normal = nil
          @reference_center = nil
          @influence_bb = nil
          @influence_area_points = nil
          Sketchup.set_status_text("1. Clique em uma FACE para definir o PLANO de referência")
        else
          # Se está no início, sai da ferramenta
          reset_tool
        end
        view.invalidate
      end

      def reset_tool
        @state = :selecting_face
        @ip = Sketchup::InputPoint.new
        
        # Variáveis para detecção de faces
        @hovered_face = nil
        @hovered_transformation = nil
        @selected_face_info = nil
        
        @influence_depth = 0
        @stretch_data = { entities_to_move: [], vertices_to_stretch: [] }
        @stretch_vector = Geom::Vector3d.new(0,0,0)
        @selection_bb = nil
        
        # Plano de referência baseado na face
        @reference_plane = nil
        @reference_normal = nil
        @reference_center = nil
        
        # Controles específicos da face tool
        @bilateral_mode = false
        @bidirectional_mode = false
        @influence_bb = nil  # Área única que pode ser para frente ou trás
        @influence_area_points = nil  # Pontos da caixa alinhada à face

        Sketchup.set_status_text("1. Clique em uma FACE para definir o PLANO de referência")
      end
      
      def enableVCB?
        return true if @state == :defining_depth || @state == :defining_stretch_vector
        false
      end

      def onUserText(text, view)
        return unless text.is_a?(String) && !text.empty?
        begin; value = text.to_l; rescue; UI.beep; return; end

        if @state == :defining_depth
          @influence_depth = value.abs  # Sempre positivo
          create_plane_based_influence_area
          advance_to_stretch_vector_state(view)
        elsif @state == :defining_stretch_vector
          if @reference_normal
            vector = @reference_normal.clone
            if vector.length > 1e-9
              vector.length = value.abs
              vector.reverse! if value < 0
              apply_stretch(vector)
              # ✅ VOLTA PARA O INÍCIO EM VEZ DE SAIR
              return_to_face_selection(view)
            else
              UI.beep
            end
          end
        end
      end

      def onMouseMove(flags, x, y, view)
        # Detecta modificadores
        @bilateral_mode = (flags & MK_ALT) != 0
        @bidirectional_mode = (flags & MK_CONTROL) != 0
        
        case @state
        when :selecting_face
          detect_face_at_cursor_paint_style(x, y, view)
          update_status_for_face_selection
          view.invalidate
          
        when :defining_depth
          @ip.pick(view, x, y)
          
          if @reference_center && @reference_normal
            mouse_vec = @reference_center.vector_to(@ip.position)
            depth_signed = mouse_vec.dot(@reference_normal)
            @influence_depth = depth_signed.abs
            @influence_direction = depth_signed >= 0 ? @reference_normal : @reference_normal.reverse
            
            create_plane_based_influence_area
            Sketchup.vcb_value = depth_signed.to_s
            view.invalidate
          end
          
        when :defining_stretch_vector
          @ip.pick(view, x, y)
          
          if @reference_center && @reference_normal
            mouse_vec = @reference_center.vector_to(@ip.position)
            distance = mouse_vec.dot(@reference_normal)
            
            if distance.abs > 1e-9
              @stretch_vector = @reference_normal.clone
              @stretch_vector.length = distance.abs
              @stretch_vector.reverse! if distance < 0
            else
              @stretch_vector = Geom::Vector3d.new(0,0,0)
            end
            
            update_status_for_stretch_mode
            Sketchup.vcb_value = distance.to_s
            view.invalidate
          end
        end
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when :selecting_face
          if @hovered_face && @hovered_face.is_a?(Sketchup::Face)
            if face_belongs_to_selection?(@hovered_face)
              create_reference_plane_from_face
              @state = :defining_depth
              update_status_for_depth_definition
              puts "Plano de referência criado com normal: #{@reference_normal}"
              view.invalidate
            else
              puts "Face não pertence à seleção inicial"
              UI.beep
            end
          else
            puts "Nenhuma face detectada no clique"
            UI.beep
          end
          
        when :defining_depth
          advance_to_stretch_vector_state(view)
        when :defining_stretch_vector
          if @stretch_vector.length > 1e-9
            apply_stretch(@stretch_vector)
            # ✅ VOLTA PARA SELEÇÃO DE FACE EM VEZ DE SAIR
            return_to_face_selection(view)
          else
            UI.beep
          end
        end
      end

      def draw(view)
        case @state
        when :selecting_face
          draw_face_highlight_paint_style(view)
          
        when :defining_depth
          draw_reference_plane_feedback(view)
          draw_influence_area(view)
          draw_depth_feedback(view)
          
        when :defining_stretch_vector
          draw_reference_plane_feedback(view)
          draw_influence_area(view)
          draw_stretch_feedback(view)
          draw_stretch_arrow(view)
        end
        
        @ip.draw(view) if @ip && @ip.valid?
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        if @hovered_face && @hovered_face.valid? && @hovered_transformation
          local_bb = @hovered_face.bounds
          world_bb = Geom::BoundingBox.new
          (0..7).each do |i|
            corner_point = local_bb.corner(i)
            transformed_point = corner_point.transform(@hovered_transformation)
            world_bb.add(transformed_point)
          end
          bb.add(world_bb)
        end
        return bb
      end
      
      private

      # ============================================================================
      # ✅ MÉTODO PARA REUTILIZAÇÃO CONTÍNUA
      # ============================================================================

      def return_to_face_selection(view)
        @state = :selecting_face
        @selected_face_info = nil
        @reference_normal = nil
        @reference_center = nil
        @influence_bb = nil
        @influence_area_points = nil
        @stretch_data = { entities_to_move: [], vertices_to_stretch: [] }
        @stretch_vector = Geom::Vector3d.new(0,0,0)
        
        Sketchup.set_status_text("1. Clique em uma FACE para definir o PLANO de referência (ESC para sair)")
        view.invalidate
        puts "Pronto para novo stretch!"
      end

      # ============================================================================
      # DETECÇÃO DE FACES (MANTIDO)
      # ============================================================================

      def detect_face_at_cursor_paint_style(x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        new_hovered_face = ph.leaf_at(0)
        
        if new_hovered_face != @hovered_face
          if new_hovered_face.is_a?(Sketchup::Face)
            @hovered_face = new_hovered_face
            @hovered_transformation = ph.transformation_at(0)
          else
            @hovered_face = nil
            @hovered_transformation = nil
          end
        end
      end

      def face_belongs_to_selection?(face)
        @initial_selection.each do |entity|
          if face_in_entity?(face, entity)
            puts "Face encontrada em: #{entity.class}"
            return true
          end
        end
        
        if @model.active_entities.include?(face) && @initial_selection.include?(face)
          puts "Face selecionada diretamente no contexto principal"
          return true
        end
        
        false
      end

      def face_in_entity?(face, entity)
        case entity
        when Sketchup::Group
          return entity.entities.include?(face) || 
                 entity.entities.any? { |sub_entity| face_in_entity?(face, sub_entity) }
        when Sketchup::ComponentInstance
          return entity.definition.entities.include?(face) ||
                 entity.definition.entities.any? { |sub_entity| face_in_entity?(face, sub_entity) }
        when Sketchup::Face
          return entity == face
        else
          return false
        end
      end

      # ============================================================================
      # CRIAÇÃO DO PLANO DE REFERÊNCIA (MANTIDO)
      # ============================================================================

      def create_reference_plane_from_face
        return unless @hovered_face && @hovered_transformation
        
        local_normal = @hovered_face.normal
        local_center = @hovered_face.bounds.center
        
        @reference_normal = local_normal.transform(@hovered_transformation)
        @reference_normal.normalize! if @reference_normal.length > 0
        @reference_center = local_center.transform(@hovered_transformation)
        
        create_extended_reference_plane
        
        puts "Plano de referência criado:"
        puts "  Normal: #{@reference_normal}"
        puts "  Centro: #{@reference_center}"
      end

      def create_extended_reference_plane
        return unless @selection_bb && @reference_normal && @reference_center
        
        selection_center = @selection_bb.center
        to_selection_center = @reference_center.vector_to(selection_center)
        distance_to_plane = to_selection_center.dot(@reference_normal)
        projected_selection_center = selection_center.offset(@reference_normal, -distance_to_plane)
        @reference_center = projected_selection_center
        
        puts "Centro do plano ajustado para: #{@reference_center}"
      end

      # ============================================================================
      # ✅ ÁREA DE INFLUÊNCIA CORRIGIDA PARA ALINHAMENTO REAL AO PLANO
      # ============================================================================

      def create_plane_based_influence_area
        return unless @reference_normal && @reference_center && @influence_depth >= 0
        
        direction = @influence_direction || @reference_normal
        @influence_bb = create_face_aligned_influence_area(direction, @influence_depth)
        
        puts "Área de influência criada:"
        puts "  Direção: #{direction}"
        puts "  Profundidade: #{@influence_depth}"
        puts "  Válida: #{@influence_bb&.valid?}"
      end

      def create_face_aligned_influence_area(direction_normal, depth)
        return nil unless @hovered_face && @hovered_transformation && depth > 0

        # ✅ ABORDAGEM SIMPLES: Usa a face como base e estende na direção da normal
        face_vertices_world = @hovered_face.vertices.map do |vertex|
          vertex.position.transform(@hovered_transformation)
        end

        # Projeta todos os cantos da seleção no plano da face
        projected_points = []
        if @selection_bb
          8.times do |i|
            corner = @selection_bb.corner(i)
            projected = project_point_to_plane(corner, @reference_center, @reference_normal)
            projected_points << projected
          end
        end

        # Combina vértices da face com pontos projetados da seleção
        all_points_on_plane = face_vertices_world + projected_points

        # Encontra os limites expandidos no plano da face usando a própria geometria
        bounds = calculate_oriented_bounds(all_points_on_plane, @reference_center, @reference_normal)

        # Adiciona margem
        margin = @selection_bb ? @selection_bb.diagonal * 0.1 : 0

        # Cria 4 pontos da base expandida no plano da face
        base_points = expand_base_rectangle(bounds, margin)

        # Cria os 8 pontos: 4 na base + 4 estendidos
        @influence_area_points = []

        # Adiciona os 4 pontos da base
        base_points.each { |pt| @influence_area_points << pt }

        # Adiciona os 4 pontos estendidos na direção especificada
        base_points.each do |pt|
          extended_pt = pt.offset(direction_normal, depth)
          @influence_area_points << extended_pt
        end

        puts "✅ Área criada ALINHADA à face selecionada (#{@influence_area_points.length} pontos)"

        # Cria BoundingBox para compatibilidade
        influence_bb = Geom::BoundingBox.new
        @influence_area_points.each { |pt| influence_bb.add(pt) }
        influence_bb
      end

      # Calcula limites no plano orientado da face
      def calculate_oriented_bounds(points, center, normal)
        return nil if points.empty?

        # Cria dois vetores perpendiculares no plano da face
        # Estes serão nossos "eixos X e Y" locais
        if normal.z.abs < 0.9
          u_axis = normal.cross(Z_AXIS).normalize
        else
          u_axis = normal.cross(X_AXIS).normalize
        end
        v_axis = normal.cross(u_axis).normalize

        # Projeta todos os pontos nos eixos U e V
        u_values = []
        v_values = []

        points.each do |pt|
          vec = center.vector_to(pt)
          u_values << vec.dot(u_axis)
          v_values << vec.dot(v_axis)
        end

        # Retorna os limites e os eixos
        {
          u_min: u_values.min,
          u_max: u_values.max,
          v_min: v_values.min,
          v_max: v_values.max,
          u_axis: u_axis,
          v_axis: v_axis,
          center: center
        }
      end

      # Cria um retângulo expandido no plano da face
      def expand_base_rectangle(bounds, margin)
        return [] unless bounds

        u_min = bounds[:u_min] - margin
        u_max = bounds[:u_max] + margin
        v_min = bounds[:v_min] - margin
        v_max = bounds[:v_max] + margin

        center = bounds[:center]
        u_axis = bounds[:u_axis]
        v_axis = bounds[:v_axis]

        # Cria os 4 cantos do retângulo
        [
          center.offset(u_axis, u_min).offset(v_axis, v_min),
          center.offset(u_axis, u_max).offset(v_axis, v_min),
          center.offset(u_axis, u_max).offset(v_axis, v_max),
          center.offset(u_axis, u_min).offset(v_axis, v_max)
        ]
      end

      def calculate_face_bounds(face_vertices)
        return nil if face_vertices.empty?
        
        # Usa os próprios vértices da face como limites
        min_x = face_vertices.map(&:x).min
        max_x = face_vertices.map(&:x).max
        min_y = face_vertices.map(&:y).min
        max_y = face_vertices.map(&:y).max
        min_z = face_vertices.map(&:z).min
        max_z = face_vertices.map(&:z).max
        
        {
          min_point: Geom::Point3d.new(min_x, min_y, min_z),
          max_point: Geom::Point3d.new(max_x, max_y, max_z),
          vertices: face_vertices
        }
      end

      def expand_bounds_to_cover_selection(face_bounds, face_vertices)
        return face_bounds unless @selection_bb
        
        # Projeta todos os pontos da seleção no plano da face
        projected_selection_points = []
        8.times do |i|
          corner = @selection_bb.corner(i)
          projected_point = project_point_to_plane(corner, @reference_center, @reference_normal)
          projected_selection_points << projected_point
        end
        
        # Calcula um retângulo que engloba tanto a face quanto a seleção projetada
        all_points = face_vertices + projected_selection_points
        
        min_x = all_points.map(&:x).min
        max_x = all_points.map(&:x).max
        min_y = all_points.map(&:y).min
        max_y = all_points.map(&:y).max
        min_z = all_points.map(&:z).min
        max_z = all_points.map(&:z).max
        
        # Adiciona margem para garantir cobertura completa
        margin = @selection_bb.diagonal * 0.1
        
        # Cria vértices expandidos no plano
        expanded_vertices = [
          Geom::Point3d.new(min_x - margin, min_y - margin, min_z),
          Geom::Point3d.new(max_x + margin, min_y - margin, min_z),
          Geom::Point3d.new(max_x + margin, max_y + margin, max_z),
          Geom::Point3d.new(min_x - margin, max_y + margin, max_z)
        ]
        
        {
          min_point: Geom::Point3d.new(min_x - margin, min_y - margin, min_z),
          max_point: Geom::Point3d.new(max_x + margin, max_y + margin, max_z),
          vertices: expanded_vertices
        }
      end

      def create_expanded_face_area(bounds, direction_normal, depth, influence_bb)
        return unless bounds && bounds[:vertices]
        
        # Adiciona os vértices da base (no plano)
        bounds[:vertices].each { |vertex| influence_bb.add(vertex) }
        
        # Adiciona os vértices estendidos na direção especificada
        bounds[:vertices].each do |vertex|
          extended_vertex = vertex.offset(direction_normal, depth)
          influence_bb.add(extended_vertex)
        end
        
        puts "Área expandida criada com #{bounds[:vertices].length} vértices base"
      end

      def project_point_to_plane(point, plane_center, plane_normal)
        to_point = plane_center.vector_to(point)
        distance_to_plane = to_point.dot(plane_normal)
        point.offset(plane_normal, -distance_to_plane)
      end

      # ============================================================================
      # ANÁLISE INTERNA DA GEOMETRIA (MANTIDO)
      # ============================================================================

      def advance_to_stretch_vector_state(view)
        @state = :defining_stretch_vector
        analyze_geometry_internal
        update_status_for_stretch_mode
      end

      def analyze_geometry_internal
        puts "\n=== ANÁLISE INTERNA DA GEOMETRIA ==="
        
        @stretch_data = { entities_to_move: [], vertices_to_stretch: [] }
        
        return unless @influence_bb&.valid?
        
        @initial_selection.each do |entity|
          puts "Analisando #{entity.class}..."
          
          case entity
          when Sketchup::Group
            make_unique_if_needed(entity)
            analyze_group_internal_geometry(entity, entity.transformation)
          when Sketchup::ComponentInstance
            make_unique_if_needed(entity)
            analyze_component_internal_geometry(entity, entity.transformation)
          else
            analyze_loose_entity(entity)
          end
        end
        
        puts "Resultado da análise interna:"
        puts "  - Entidades para mover: #{@stretch_data[:entities_to_move].length}"
        puts "  - Vértices para esticar: #{@stretch_data[:vertices_to_stretch].length}"
        puts "=== FIM DA ANÁLISE INTERNA ===\n"
      end

      def analyze_group_internal_geometry(group, group_transform)
        group.entities.each do |entity|
          case entity
          when Sketchup::Edge
            analyze_edge_vertices(entity, group_transform, group)
          when Sketchup::Face
            analyze_face_vertices(entity, group_transform, group)
          when Sketchup::Group, Sketchup::ComponentInstance
            nested_transform = group_transform * entity.transformation
            analyze_nested_entity(entity, nested_transform)
          end
        end
      end

      def analyze_component_internal_geometry(component, component_transform)
        component.definition.entities.each do |entity|
          case entity
          when Sketchup::Edge
            analyze_edge_vertices(entity, component_transform, component)
          when Sketchup::Face
            analyze_face_vertices(entity, component_transform, component)
          when Sketchup::Group, Sketchup::ComponentInstance
            nested_transform = component_transform * entity.transformation
            analyze_nested_entity(entity, nested_transform)
          end
        end
      end

      def analyze_edge_vertices(edge, parent_transform, container)
        edge.vertices.each do |vertex|
          world_pos = vertex.position.transform(parent_transform)
          
          if @influence_bb.contains?(world_pos)
            @stretch_data[:vertices_to_stretch] << {
              vertex: vertex,
              world_position: world_pos,
              container: container,
              parent_transform: parent_transform
            }
            puts "  -> Vértice de aresta adicionado: #{world_pos}"
          end
        end
      end

      def analyze_face_vertices(face, parent_transform, container)
        face.vertices.each do |vertex|
          world_pos = vertex.position.transform(parent_transform)
          
          if @influence_bb.contains?(world_pos)
            @stretch_data[:vertices_to_stretch] << {
              vertex: vertex,
              world_position: world_pos,
              container: container,
              parent_transform: parent_transform
            }
            puts "  -> Vértice de face adicionado: #{world_pos}"
          end
        end
      end

      def analyze_nested_entity(entity, nested_transform)
        case entity
        when Sketchup::Group
          analyze_group_internal_geometry(entity, nested_transform)
        when Sketchup::ComponentInstance
          analyze_component_internal_geometry(entity, nested_transform)
        end
      end

      def analyze_loose_entity(entity)
        case entity
        when Sketchup::Edge
          analyze_edge_vertices(entity, Geom::Transformation.new, nil)
        when Sketchup::Face
          analyze_face_vertices(entity, Geom::Transformation.new, nil)
        end
      end

      def make_unique_if_needed(entity)
        if entity.is_a?(Sketchup::ComponentInstance) && 
           entity.definition.count_instances > 1
          puts "    -> Tornando componente único (#{entity.definition.count_instances} instâncias)"
          entity.make_unique
        end
      end

      # ============================================================================
      # APLICAÇÃO DO STRETCH (MANTIDO)
      # ============================================================================

      def apply_stretch(vector)
        return if vector.nil? || vector.length < 1e-9
        
        vertices_to_stretch = @stretch_data[:vertices_to_stretch]
        
        if vertices_to_stretch.empty?
          puts "Nenhum vértice encontrado na área de influência."
          UI.messagebox("Nenhuma geometria foi encontrada na área de influência.\nTente aumentar a profundidade ou verificar a direção.")
          return
        end

        operation_name = "Stretch Vértices"

        @model.start_operation(operation_name, true)
        
        begin
          puts "Aplicando stretch a #{vertices_to_stretch.length} vértices..."
          
          vertices_by_container = vertices_to_stretch.group_by { |v_info| v_info[:container] }
          
          vertices_by_container.each do |container, vertex_infos|
            if container
              puts "Esticando #{vertex_infos.length} vértices em #{container.class}"
              
              parent_transform = vertex_infos.first[:parent_transform]
              local_vector = calculate_local_vector(vector, parent_transform)
              vertices = vertex_infos.map { |v_info| v_info[:vertex] }
              
              begin
                if container.is_a?(Sketchup::Group)
                  container.entities.transform_entities(local_vector, vertices)
                elsif container.is_a?(Sketchup::ComponentInstance)
                  container.definition.entities.transform_entities(local_vector, vertices)
                end
                puts "  ✓ #{vertices.length} vértices transformados"
              rescue => e
                puts "  ✗ Erro ao transformar vértices: #{e.message}"
                vertices.each_with_index do |vertex, idx|
                  begin
                    new_pos = vertex.position.offset(local_vector)
                    vertex.position = new_pos
                    puts "    ✓ Vértice #{idx + 1} movido individualmente"
                  rescue => individual_error
                    puts "    ✗ Falha no vértice #{idx + 1}: #{individual_error.message}"
                  end
                end
              end
            else
              vertex_infos.each do |v_info|
                vertex = v_info[:vertex]
                new_pos = vertex.position.offset(vector)
                vertex.position = new_pos
                puts "  ✓ Vértice solto movido"
              end
            end
          end
          
          @model.commit_operation
          puts "#{operation_name} aplicado com sucesso!"
          
        rescue => e
          puts "Erro durante o stretch: #{e.message}"
          puts e.backtrace.first(5).join("\n")
          @model.abort_operation
        end
      end

      def calculate_local_vector(global_vector, parent_transform)
        return global_vector if parent_transform.nil? || parent_transform.identity?
        global_vector.transform(parent_transform.inverse)
      end

      # ============================================================================
      # MÉTODOS DE STATUS E FEEDBACK
      # ============================================================================

      def update_status_for_face_selection
        Sketchup.set_status_text("1. Clique em uma FACE para definir plano de referência (ESC volta ao início)")
      end

      def update_status_for_depth_definition
        Sketchup.set_status_text("2. Mova para FRENTE ou TRÁS do plano para definir área de influência")
      end

      def update_status_for_stretch_mode
        if @bidirectional_mode
          Sketchup.set_status_text("3. [CTRL] Stretch bidirecional dos vértices (ESC cancela)")
        else
          Sketchup.set_status_text("3. Stretch dos vértices perpendicular ao plano (ESC cancela)")
        end
      end

      # ============================================================================
      # MÉTODOS DE DESENHO
      # ============================================================================

      def draw_face_highlight_paint_style(view)
        return unless @hovered_face && @hovered_face.valid? && @hovered_transformation
        
        view.line_stipple = ""
        view.line_width = 8
        view.drawing_color = Sketchup::Color.new(255, 255, 0)
        
        @hovered_face.loops.each do |loop|
          local_points = loop.vertices.map(&:position)
          world_points = local_points.map { |point| point.transform(@hovered_transformation) }
          view.draw(GL_LINE_LOOP, world_points)
        end
        
        if @hovered_face.loops.first
          local_points = @hovered_face.loops.first.vertices.map(&:position)
          world_points = local_points.map { |point| point.transform(@hovered_transformation) }
          view.drawing_color = [255, 255, 0, 120]
          view.draw(GL_POLYGON, world_points)
        end
        
        if @selection_bb && @selection_bb.valid?
          local_center = @hovered_face.bounds.center
          world_center = local_center.transform(@hovered_transformation)
          local_normal = @hovered_face.normal
          world_normal = local_normal.transform(@hovered_transformation)
          world_normal.normalize!
          
          normal_end = world_center.offset(world_normal, @selection_bb.diagonal * 0.1)
          view.line_width = 3
          view.drawing_color = "Blue"
          view.draw_line(world_center, normal_end)
          
          view.drawing_color = "Red"
          view.draw_points([world_center], 8, 1, "Red")
        end
      end

      def draw_reference_plane_feedback(view)
        return unless @reference_center && @reference_normal && @selection_bb
        
        view.line_stipple = ""
        view.line_width = 3
        view.drawing_color = "Green"
        
        normal_end = @reference_center.offset(@reference_normal, @selection_bb.diagonal * 0.15)
        view.draw_line(@reference_center, normal_end)
        
        plane_size = @selection_bb.diagonal * 0.1
        draw_plane_indicator(view, @reference_center, @reference_normal, plane_size)
        
        view.drawing_color = "Green"
        view.draw_points([@reference_center], 10, 1, "Green")
      end

      def draw_plane_indicator(view, center, normal, size)
        if normal.parallel?(Z_AXIS)
          u_vector = normal.cross(X_AXIS)
        else
          u_vector = normal.cross(Z_AXIS)
        end
        u_vector.normalize!
        u_vector.length = size
        
        v_vector = normal.cross(u_vector)
        v_vector.normalize!
        v_vector.length = size
        
        corner1 = center.offset(u_vector).offset(v_vector)
        corner2 = center.offset(u_vector.reverse).offset(v_vector)
        corner3 = center.offset(u_vector.reverse).offset(v_vector.reverse)
        corner4 = center.offset(u_vector).offset(v_vector.reverse)
        
        view.drawing_color = [0, 255, 0, 100]
        view.draw(GL_QUADS, [corner1, corner2, corner3, corner4])
        
        view.line_width = 2
        view.drawing_color = "DarkGreen"
        view.draw(GL_LINE_LOOP, [corner1, corner2, corner3, corner4])
      end

      def draw_influence_area(view)
        if @influence_bb&.valid?
          color = if @influence_direction == @reference_normal
            [0, 255, 0, 60]  # Verde para frente
          else
            [255, 165, 0, 60]  # Laranja para trás
          end

          # Usa pontos alinhados à face se disponíveis, senão usa BoundingBox padrão
          if @influence_area_points && @influence_area_points.length == 8
            draw_aligned_box(view, @influence_area_points, color)
          else
            draw_bb(view, @influence_bb, color)
          end

          # ✅ DESENHA CONTORNO DA FACE BASE PARA MOSTRAR ALINHAMENTO
          if @hovered_face && @hovered_transformation
            draw_aligned_face_outline(view)
          end
        end
      end

      def draw_aligned_face_outline(view)
        return unless @hovered_face && @hovered_transformation
        
        # Desenha a face selecionada com cor especial para mostrar alinhamento
        view.line_stipple = "-"
        view.line_width = 3
        view.drawing_color = "Cyan"
        
        @hovered_face.loops.each do |loop|
          local_points = loop.vertices.map(&:position)
          world_points = local_points.map { |point| point.transform(@hovered_transformation) }
          view.draw(GL_LINE_LOOP, world_points)
        end
        
        # Desenha preenchimento ciano transparente
        if @hovered_face.loops.first
          local_points = @hovered_face.loops.first.vertices.map(&:position)
          world_points = local_points.map { |point| point.transform(@hovered_transformation) }
          view.drawing_color = [0, 255, 255, 60]
          view.draw(GL_POLYGON, world_points)
        end
      end

      def draw_depth_feedback(view)
        return unless @reference_center && @reference_normal && @ip.valid?
        
        mouse_vec = @reference_center.vector_to(@ip.position)
        depth_signed = mouse_vec.dot(@reference_normal)
        depth = depth_signed.abs
        direction = depth_signed >= 0 ? @reference_normal : @reference_normal.reverse
        
        projected_point = @reference_center.offset(direction, depth)
        
        view.line_stipple = "-"
        view.line_width = 2
        color = depth_signed >= 0 ? "Green" : "Orange"
        view.drawing_color = color
        view.draw_line(@reference_center, projected_point)
        
        view.drawing_color = color
        view.draw_points([projected_point], 6, 1, color)
        
        # Linha guia do mouse
        view.line_stipple = ":"
        view.line_width = 1
        view.drawing_color = [150, 150, 150, 100]
        view.draw_line(@reference_center, @ip.position)
      end

      def draw_stretch_feedback(view)
        return unless @reference_center && @reference_normal && @ip.valid?
        
        mouse_vec = @reference_center.vector_to(@ip.position)
        distance = mouse_vec.dot(@reference_normal)
        
        projected_point = @reference_center.offset(@reference_normal, distance)
        
        view.line_stipple = "-"
        view.line_width = 3
        view.drawing_color = "Purple"
        view.draw_line(@reference_center, projected_point)
        
        view.line_stipple = ":"
        view.line_width = 1
        view.drawing_color = [150, 150, 150, 80]
        view.draw_line(projected_point, @ip.position)
        
        view.drawing_color = "Purple"
        view.draw_points([projected_point], 8, 1, "Purple")
      end

      def draw_stretch_arrow(view)
        return unless @reference_center && @stretch_vector && @stretch_vector.length > 1e-9
        
        view.line_stipple = ""
        view.line_width = 4
        view.drawing_color = "Purple"
        
        start_point = @reference_center
        end_point = start_point.offset(@stretch_vector)
        view.draw_line(start_point, end_point)
        
        if @selection_bb && @selection_bb.valid?
          arrow_size = (@selection_bb.diagonal * 0.03).to_l
          arrow_points = create_arrow_head(start_point, end_point, arrow_size)
          view.draw(GL_TRIANGLES, arrow_points) if arrow_points.length == 3
        end
      end

      # ============================================================================
      # MÉTODOS AUXILIARES
      # ============================================================================

      def calculate_selection_bounding_box(selection)
        bb = Geom::BoundingBox.new
        selection.each do |entity|
          bb.add(entity.bounds) if entity.respond_to?(:bounds)
        end
        bb.valid? ? bb : nil
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

      # Desenha uma caixa alinhada à face usando 8 pontos personalizados
      # Points 0-3: base (no plano da face)
      # Points 4-7: topo (estendidos na direção da normal)
      def draw_aligned_box(view, points, color)
        return unless points && points.length == 8

        view.drawing_color = color

        # Desenha as 6 faces da caixa como quads
        view.draw(GL_QUADS, [
          # Base (pontos 0,1,2,3)
          points[0], points[1], points[2], points[3],
          # Topo (pontos 4,5,6,7)
          points[4], points[5], points[6], points[7],
          # Laterais
          points[0], points[1], points[5], points[4],
          points[1], points[2], points[6], points[5],
          points[2], points[3], points[7], points[6],
          points[3], points[0], points[4], points[7]
        ])

        # Desenha as arestas
        view.line_stipple = ""
        view.line_width = 1
        view.drawing_color = [color[0], color[1], color[2], 255]

        # Arestas da base
        view.draw_lines(
          points[0], points[1],
          points[1], points[2],
          points[2], points[3],
          points[3], points[0]
        )

        # Arestas do topo
        view.draw_lines(
          points[4], points[5],
          points[5], points[6],
          points[6], points[7],
          points[7], points[4]
        )

        # Arestas verticais
        view.draw_lines(
          points[0], points[4],
          points[1], points[5],
          points[2], points[6],
          points[3], points[7]
        )
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

    end # class StretchFaceTool
  end # module MockupTools
end # module Rjv