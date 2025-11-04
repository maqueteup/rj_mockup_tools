# lib/panel_divider_tool.rb
# encoding: UTF-8

require 'sketchup.rb'

module Rjv
  module MockupTools
    
    # Ferramenta auxiliar dedicada apenas a selecionar uma face.
    class FaceSelectorTool
      def initialize(parent_tool)
        @parent = parent_tool
        Sketchup.set_status_text("Clique em uma face para selecioná-la. Pressione Esc para cancelar.")
      end

      def onLButtonDown(flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        face = ph.best_picked
        
        if face.is_a?(Sketchup::Face)
          @parent.set_selected_face(face, ph.transformation_at(0))
          # --- CORREÇÃO: Reativa a ferramenta principal em vez de desativar tudo ---
          Sketchup.active_model.select_tool(@parent)
        end
      end
      
      def onCancel(reason, view)
        # --- CORREÇÃO: Reativa a ferramenta principal também ao cancelar ---
        Sketchup.active_model.select_tool(@parent)
        Sketchup.set_status_text("Seleção cancelada.")
      end
      
      # Adicionado para evitar que o cursor padrão apareça
      def onSetCursor
        UI.set_cursor(633) # Cursor de seleção padrão do SketchUp
      end
    end

    # A ferramenta principal que gerencia o diálogo e a criação da geometria.
    class PanelDividerTool
      def initialize
        @model = Sketchup.active_model
        @dialog = nil
        @params = load_saved_parameters || {
          rows: 3, cols: 4, opening_width: 50.mm, opening_height: 50.mm,
          rotation: 0.0, has_frame: true, frame_width: 50.mm,
          use_divider_measurements: false
        }
        @selected_face = nil
        @instance_transform = nil
        @state = :idle
      end

      def activate
        show_dialog
        Sketchup.set_status_text("Use o diálogo para selecionar uma face e configurar a tela.")
      end

      # --- CORREÇÃO: Removida a linha que fechava o diálogo ---
      # A desativação agora apenas limpa a tela, o diálogo permanece aberto
      # até que o usuário o feche.
      def deactivate(view)
        view.invalidate
      end
      
      def onCancel(reason, view)
        deactivate(view)
      end
      
      def onReturn(view)
        create_panel_geometry_safe(view) if @state == :previewing && @selected_face
      end

      def draw(view)
        if @state == :previewing && @selected_face && @selected_face.valid?
          draw_enhanced_preview(view, @selected_face, @params, @instance_transform)
        end
      end
      
      def set_selected_face(face, transform)
        @selected_face = face
        @instance_transform = transform
        @state = :previewing
        @dialog.bring_to_front
        Sketchup.set_status_text("Ajuste os parâmetros. Clique em 'Aplicar' para finalizar.")
        @model.active_view.invalidate
      end

      private

      def show_dialog
        return if @dialog && @dialog.visible?
        html = create_dialog_html
        
        @dialog = UI::HtmlDialog.new(
          dialog_title: "Gerador de Telas Perfuradas",
          scrollable: false, resizable: true, width: 380, height: 650,
          left: 200, top: 200, style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(html)
        
        @dialog.add_action_callback("select_face") do |_,_|
          Sketchup.active_model.select_tool(FaceSelectorTool.new(self))
          true
        end
        
        @dialog.add_action_callback("run_apply") do |_,_|
          create_panel_geometry_safe(@model.active_view) if @state == :previewing && @selected_face
          true
        end
        
        @dialog.add_action_callback("update_params") do |_, params_json|
          begin
            new_params = JSON.parse(params_json)
            converted_params = {}
            new_params.each do |key, value|
              case key.to_s
              when 'rows', 'cols' then converted_params[key.to_sym] = value.to_i
              when 'opening_width', 'opening_height', 'frame_width' then converted_params[key.to_sym] = value.to_f.mm
              when 'rotation' then converted_params[key.to_sym] = value.to_f
              when 'has_frame', 'use_divider_measurements' then converted_params[key.to_sym] = !!value
              end
            end
            @params.merge!(converted_params)
            save_parameters
            @model.active_view.invalidate if @selected_face
          end
        end
        
        @dialog.add_action_callback("get_current_params") do |_|
          params_with_values = {}
          @params.each do |key, value|
            case key.to_s
            when 'opening_width', 'opening_height', 'frame_width'
              params_with_values[key] = (value / 1.mm).round(1)
            else params_with_values[key] = value end
          end
          @dialog.execute_script("updateParams(#{params_with_values.to_json})")
        end
        
        # Quando o usuário fecha o diálogo pelo 'X', a ferramenta é desativada
        @dialog.set_on_closed { @model.select_tool(nil) }
        @dialog.show
      end

      def create_dialog_html
        <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>Gerador de Telas</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
          .container { background: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
          h2 { color: #333; margin-top: 0; text-align: center; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
          .param-group { margin-bottom: 15px; padding: 15px; background: #f9f9f9; border-radius: 5px; border-left: 4px solid #007acc; }
          .param-group h3 { margin-top: 0; color: #555; font-size: 14px; font-weight: bold; }
          .param-row { display: flex; align-items: center; margin-bottom: 10px; }
          label { display: inline-block; width: 140px; font-weight: bold; color: #666; font-size: 12px; }
          input[type="number"], input[type="range"] { flex: 1; margin-left: 10px; padding: 5px; border: 1px solid #ddd; border-radius: 3px; }
          input[type="range"] { margin-right: 10px; }
          .value-display { min-width: 60px; text-align: right; font-weight: bold; color: #007acc; font-size: 12px; }
          .radio-group { display: flex; gap: 15px; }
          .action-buttons { text-align: center; margin-top: 20px; display: flex; justify-content: space-around; gap: 15px; }
          .action-buttons button { padding: 10px 0; width: 100%; border: none; border-radius: 5px; cursor: pointer; font-size: 14px; font-weight: bold; }
          #select-face-button { background: #007acc; color: white; margin-bottom: 15px; width: 100%; padding: 12px; font-size: 16px; }
          #apply-button { background: #28a745; color: white; }
        </style>
        </head><body>
        <div class="container">
          <h2>Gerador de Telas Perfuradas</h2>
          <button id="select-face-button" onclick="selectFace()">1. Selecionar Face de Trabalho</button>
          <div class="param-group">
            <h3>Grade</h3>
            <div class="param-row"><label>Linhas:</label><input type="range" id="rows" min="1" max="100" value="3" oninput="updateParam('rows', this.value)"><span class="value-display" id="rows-value">3</span></div>
            <div class="param-row"><label>Colunas:</label><input type="range" id="cols" min="1" max="100" value="4" oninput="updateParam('cols', this.value)"><span class="value-display" id="cols-value">4</span></div>
          </div>
          <div class="param-group">
            <h3>Medidas (mm)</h3>
            <div class="param-row"><label>Tipo de medida:</label><div class="radio-group"><div class="radio-item"><input type="radio" id="measure_opening" name="measure_type" value="false" checked onchange="updateParam('use_divider_measurements', this.value)"><label for="measure_opening">Abertura</label></div><div class="radio-item"><input type="radio" id="measure_divider" name="measure_type" value="true" onchange="updateParam('use_divider_measurements', this.value)"><label for="measure_divider">Divisor</label></div></div></div>
            <div class="param-row"><label id="width-label">Largura da abertura:</label><input type="number" id="opening_width" min="1" max="1000" step="1" value="50" onchange="updateParam('opening_width', this.value)"></div>
            <div class="param-row"><label id="height-label">Altura da abertura:</label><input type="number" id="opening_height" min="1" max="1000" step="1" value="50" onchange="updateParam('opening_height', this.value)"></div>
          </div>
          <div class="param-group">
            <h3>Moldura e Rotação</h3>
            <div class="param-row"><label><input type="checkbox" id="has_frame" checked onchange="updateParam('has_frame', this.checked)"> Criar moldura</label></div>
            <div class="param-row" id="frame-width-row"><label>Largura da moldura:</label><input type="number" id="frame_width" min="0" max="500" value="50" onchange="updateParam('frame_width', this.value)"></div>
            <div class="param-row"><label>Rotação (°):</label><input type="range" id="rotation" min="-90" max="90" step="5" value="0" oninput="updateParam('rotation', this.value)"><span class="value-display" id="rotation-value">0°</span></div>
          </div>
          <div class="action-buttons"><button id="apply-button" onclick="runApply()">2. Aplicar na Face</button></div>
        </div>
        <script>
          let currentParams = {};
          function updateParam(key, value) {
            if (key === 'has_frame') { currentParams[key] = value; toggleFrameControls(value); }
            else if (key === 'use_divider_measurements') { currentParams[key] = (value === 'true'); updateMeasurementLabels(value === 'true'); }
            else { currentParams[key] = parseFloat(value); }
            const displayElement = document.getElementById(key + '-value');
            if (displayElement) { displayElement.textContent = (key === 'rotation') ? value + '°' : value; }
            if (window.sketchup) { sketchup.update_params(JSON.stringify(currentParams)); }
          }
          function toggleFrameControls(hasFrame) { document.getElementById('frame-width-row').style.display = hasFrame ? 'flex' : 'none'; }
          function updateMeasurementLabels(useDivider) {
            document.getElementById('width-label').textContent = useDivider ? 'Largura do divisor:' : 'Largura da abertura:';
            document.getElementById('height-label').textContent = useDivider ? 'Altura do divisor:' : 'Altura da abertura:';
          }
          function updateParams(params) {
            currentParams = params;
            for (let key in params) {
              const element = document.getElementById(key);
              if (element) {
                if (element.type === 'radio') {
                  if (element.value == String(params[key])) { element.checked = true; }
                } else if (element.type === 'checkbox') {
                  element.checked = params[key];
                } else {
                  element.value = params[key];
                }
                const displayElement = document.getElementById(key + '-value');
                if (displayElement) {
                  displayElement.textContent = (key === 'rotation') ? params[key] + '°' : params[key];
                }
              }
            }
            if (params.use_divider_measurements !== undefined) {
              const radios = document.querySelectorAll('input[name="measure_type"]');
              radios.forEach(radio => { radio.checked = (radio.value === String(params.use_divider_measurements)); });
              updateMeasurementLabels(params.use_divider_measurements);
            }
            if (params.has_frame !== undefined) {
              toggleFrameControls(params.has_frame);
            }
          }
          function selectFace() { if (window.sketchup) { sketchup.select_face(); } }
          function runApply() { if (window.sketchup) { sketchup.run_apply(); } }
        </script></body></html>
        HTML
      end

      def load_saved_parameters
        begin
          dict = @model.attribute_dictionary("PanelDividerTool", false)
          return nil unless dict
          params = {}
          dict.each_pair do |key, value|
            case key
            when 'rows', 'cols' then params[key.to_sym] = value.to_i
            when 'opening_width', 'opening_height', 'frame_width' then params[key.to_sym] = value.to_f.mm
            when 'rotation' then params[key.to_sym] = value.to_f
            when 'has_frame', 'use_divider_measurements' then params[key.to_sym] = !!value
            end
          end
          params
        rescue
          nil
        end
      end

      def save_parameters
        begin
          dict = @model.attribute_dictionary("PanelDividerTool", true)
          @params.each do |key, value|
            case key.to_s
            when 'opening_width', 'opening_height', 'frame_width'
              dict[key.to_s] = value / 1.mm
            else
              dict[key.to_s] = value
            end
          end
        rescue; end
      end

      def create_panel_geometry_safe(view)
        return unless @selected_face && @selected_face.valid?
        
        validation_error = validate_parameters(@selected_face, @params)
        if validation_error
          UI.messagebox("Parâmetros inválidos: #{validation_error}")
          return
        end
        
        @model.start_operation("Criar Tela Perfurada", true)
        begin
          create_flat_screen(@selected_face, @params)
          @model.commit_operation
        rescue => e
          @model.abort_operation
          UI.messagebox("Erro ao criar tela: #{e.message}\n#{e.backtrace.first}")
        ensure
          @selected_face = nil
          @instance_transform = nil
          @state = :idle
          Sketchup.set_status_text("Use o diálogo para selecionar uma nova face.")
          view.invalidate if view
        end
      end

      def create_flat_screen(face, params)
        opening_positions = calculate_opening_positions(face, params)
        return unless opening_positions && !opening_positions.empty?
        target_entities = face.parent.entities
        opening_width, opening_height = calculate_opening_dimensions(face, params)
        rotation_angle = -@params[:rotation].to_f.degrees
        opening_positions.each do |position|
          create_flat_opening(target_entities, position[:center], opening_width, opening_height, rotation_angle, face)
        end
      end

      def create_flat_opening(entities, center, width, height, angle, original_face)
        return false if width <= 0 || height <= 0
        half_w, half_h = width / 2.0, height / 2.0
        points = [
          Geom::Point3d.new(-half_w, -half_h, 0), Geom::Point3d.new( half_w, -half_h, 0),
          Geom::Point3d.new( half_w,  half_h, 0), Geom::Point3d.new(-half_w,  half_h, 0)
        ]
        rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, angle)
        align_to_face = Geom::Transformation.new(center, original_face.normal)
        world_points = points.map { |p| p.transform(align_to_face * rotation) }
        
        begin
          opening_face = entities.add_face(world_points)
          opening_face.erase! if opening_face && opening_face.valid?
        rescue ArgumentError; end
      end
      
      def calculate_opening_dimensions(face, params)
        face_coords = get_face_coordinate_system(face)
        return [0, 0] unless face_coords
        
        frame_width = params[:has_frame] ? params[:frame_width].to_f : 0
        usable_width = face_coords[:width] - 2 * frame_width
        usable_height = face_coords[:height] - 2 * frame_width
        
        if params[:use_divider_measurements]
          rows, cols = params[:rows].to_i, params[:cols].to_i
          divisor_width = params[:opening_width].to_f
          divisor_height = params[:opening_height].to_f
          opening_width = (usable_width - (cols - 1) * divisor_width) / cols
          opening_height = (usable_height - (rows - 1) * divisor_height) / rows
          [opening_width, opening_height]
        else
          [params[:opening_width].to_f, params[:opening_height].to_f]
        end
      end

      def validate_parameters(face, params)
        face_coords = get_face_coordinate_system(face)
        return "Erro ao ler a geometria da face" unless face_coords
        
        if params[:has_frame]
          frame_width = params[:frame_width].to_f
          usable_width = face_coords[:width] - 2 * frame_width
          usable_height = face_coords[:height] - 2 * frame_width
          return "A moldura é maior que a própria face" if usable_width < 1.mm || usable_height < 1.mm
        end
        
        opening_width, opening_height = calculate_opening_dimensions(face, params)
        return "A dimensão da abertura resultou em um valor negativo ou zero. Verifique os tamanhos dos divisores e da moldura." if opening_width < 0.1.mm || opening_height < 0.1.mm
        
        nil
      end

      def get_face_coordinate_system(face)
        begin
          vertices = face.outer_loop.vertices.map(&:position)
          return nil if vertices.length < 3
          u_axis = (vertices[1] - vertices[0]).normalize
          v_axis = face.normal.cross(u_axis).normalize
          
          origin = vertices.first
          min_u, max_u, min_v, max_v = 0, 0, 0, 0
          
          vertices.each do |vertex|
            local_vec = vertex - origin
            u_coord, v_coord = local_vec.dot(u_axis), local_vec.dot(v_axis)
            min_u, max_u = [min_u, u_coord].min, [max_u, u_coord].max
            min_v, max_v = [min_v, v_coord].min, [max_v, v_coord].max
          end
          
          actual_origin = origin.offset(u_axis, min_u).offset(v_axis, min_v)
          { origin: actual_origin, u_axis: u_axis, v_axis: v_axis, width: max_u - min_u, height: max_v - min_v, normal: face.normal }
        rescue
          nil
        end
      end
      
      def calculate_opening_positions(face, params)
        face_coords = get_face_coordinate_system(face)
        return [] unless face_coords
        
        frame_w = params[:has_frame] ? params[:frame_width].to_f : 0
        usable_width = face_coords[:width] - 2 * frame_w
        usable_height = face_coords[:height] - 2 * frame_w
        return [] if usable_width <= 0 || usable_height <= 0
        
        opening_width, opening_height = calculate_opening_dimensions(face, params)
        return [] if opening_width <= 0 || opening_height <= 0
        
        rows, cols = params[:rows].to_i, params[:cols].to_i
        div_w = params[:use_divider_measurements] ? params[:opening_width].to_f : (usable_width - cols * opening_width) / [cols - 1, 1].max
        div_h = params[:use_divider_measurements] ? params[:opening_height].to_f : (usable_height - rows * opening_height) / [rows - 1, 1].max
        step_u, step_v = opening_width + div_w, opening_height + div_h
        return [] if step_u < 0.1.mm || step_v < 0.1.mm

        diagonal = Math.sqrt(usable_width**2 + usable_height**2)
        cols_needed = (diagonal / step_u).ceil + 2
        rows_needed = (diagonal / step_v).ceil + 2
        
        usable_area_center = face_coords[:origin].offset(face_coords[:u_axis], frame_w + usable_width/2.0).offset(face_coords[:v_axis], frame_w + usable_height/2.0)
        rotation_angle = -params[:rotation].to_f.degrees
        rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, rotation_angle)
        
        positions = []
        (-rows_needed/2..rows_needed/2).each do |row|
          (-cols_needed/2..cols_needed/2).each do |col|
            local_point = Geom::Point3d.new(col * step_u, row * step_v, 0)
            rotated_point = local_point.transform(rotation)
            world_point = usable_area_center.offset(face_coords[:u_axis], rotated_point.x).offset(face_coords[:v_axis], rotated_point.y)
            
            if is_point_in_usable_area?(world_point, face, frame_w)
              positions << { center: world_point }
            end
          end
        end
        positions
      end
      
      def is_point_in_usable_area?(point, face, frame_width)
        return false unless point_inside_original_face?(point, face)
        return true if frame_width <= 0.001
        
        face.outer_loop.edges.each do |edge|
          dist = point.distance_to_line(edge.line)
          return false if dist < frame_width
        end
        true
      end
      
      def draw_enhanced_preview(view, face, params, transform)
        return if !face.valid? || !transform
        view.line_stipple = ""
        view.line_width = 2
        view.drawing_color = [255, 0, 0, 200]
        outer_loop_points = face.outer_loop.vertices.map { |v| v.position.transform(transform) }
        view.draw(GL_LINE_LOOP, outer_loop_points)
        draw_screen_openings_preview(view, face, params, transform)
      end

      def draw_screen_openings_preview(view, face, params, transform)
        opening_positions = calculate_opening_positions(face, params)
        return unless opening_positions && !opening_positions.empty?
        
        opening_width, opening_height = calculate_opening_dimensions(face, params)
        return if opening_width <= 0 || opening_height <= 0
        
        view.line_width = 2
        view.drawing_color = [0, 255, 0, 255]
        
        face_coords = get_face_coordinate_system(face)
        return unless face_coords
        
        rotation_angle = -params[:rotation].to_f.degrees
        rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, rotation_angle)
        
        opening_positions.each do |position|
          center = position[:center]
          half_w, half_h = opening_width / 2.0, opening_height / 2.0
          points = [
            Geom::Point3d.new(-half_w, -half_h, 0), Geom::Point3d.new(half_w, -half_h, 0),
            Geom::Point3d.new(half_w, half_h, 0), Geom::Point3d.new(-half_w, half_h, 0)
          ]
          align_to_face = Geom::Transformation.new(center, face_coords[:normal])
          world_points = points.map { |p| p.transform(align_to_face * rotation).transform(transform) }
          view.draw(GL_LINE_LOOP, world_points)
        end
        
        draw_frame_preview(view, face, params, transform)
      end

      def draw_frame_preview(view, face, params, transform)
        return unless params[:has_frame]
        frame_width = params[:frame_width].to_f
        return if frame_width <= 0
        
        view.line_width = 1
        view.line_stipple = "-"
        view.drawing_color = [255, 0, 0, 150]
        
        face_coords = get_face_coordinate_system(face)
        return unless face_coords
        
        inner_points = [
          face_coords[:origin].offset(face_coords[:u_axis], frame_width).offset(face_coords[:v_axis], frame_width),
          face_coords[:origin].offset(face_coords[:u_axis], face_coords[:width] - frame_width).offset(face_coords[:v_axis], frame_width),
          face_coords[:origin].offset(face_coords[:u_axis], face_coords[:width] - frame_width).offset(face_coords[:v_axis], face_coords[:height] - frame_width),
          face_coords[:origin].offset(face_coords[:u_axis], frame_width).offset(face_coords[:v_axis], face_coords[:height] - frame_width)
        ]
        
        world_inner_points = inner_points.map { |pt| pt.transform(transform) }
        view.draw(GL_LINE_LOOP, world_inner_points)
      end

      def point_inside_original_face?(point, face)
        begin
          return false unless face.valid?
          plane = face.plane
          projected_point = point.project_to_plane(plane)
          result = face.classify_point(projected_point)
          [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(result)
        rescue
          false
        end
      end
    end

    def self.activate_panel_divider_tool
      Sketchup.active_model.select_tool(PanelDividerTool.new)
    end
  end
end