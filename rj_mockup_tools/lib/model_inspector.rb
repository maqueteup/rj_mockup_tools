# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module Rjv
  module MockupTools
    module ModelInspector
      extend self
      
      @dialog = nil
      @selection_observer = nil
      
      def open_dialog
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end
        
        @dialog = UI::HtmlDialog.new(
          {
            :dialog_title => "Model Inspector - RJV",
            :preferences_key => "rjv.model_inspector",
            :scrollable => true,
            :resizable => true,
            :width => 1200,
            :height => 700,
            :min_width => 800,
            :min_height => 500,
            :style => UI::HtmlDialog::STYLE_DIALOG
          }
        )
        
        # Callbacks
        @dialog.add_action_callback("ready") { |action_context|
          send_model_data
        }
        
        @dialog.add_action_callback("refresh") { |action_context|
          send_model_data
        }
        
        @dialog.add_action_callback("select_entity") { |action_context, pid_string|
          select_entity_by_pid(pid_string.to_i)
        }
        
        @dialog.add_action_callback("rename_entity") { |action_context, pid_string, new_name|
          rename_entity(pid_string.to_i, new_name)
        }
        
        @dialog.add_action_callback("zoom_to_entity") { |action_context, pid_string|
          zoom_to_entity(pid_string.to_i)
        }
        
        @dialog.add_action_callback("select_multiple") { |action_context, pids_json|
          pids = JSON.parse(pids_json)
          select_multiple_entities(pids)
        }
        
        @dialog.add_action_callback("export_csv") { |action_context|
          export_to_csv
        }
        
        @dialog.set_html(generate_html)
        @dialog.show
        
        # Observer para atualizar quando a seleção mudar
        setup_selection_observer
      end
      
      def send_model_data
        return unless @dialog
        
        data = collect_model_data
        @dialog.execute_script("updateModelData(#{data.to_json})")
      end
      
      def collect_model_data
        model = Sketchup.active_model
        entities_data = []
        
        # Processa todas as entidades do modelo
        process_entities(model.entities, entities_data, Geom::Transformation.new, "", 0)
        
        # Coleta informações de peças planificadas
        planified_info = collect_planified_info
        
        # Adiciona info de planificação às entidades
        entities_data.each do |entity|
          if entity[:is_makette]
            name = entity[:definition_name]
            if planified_info[name]
              entity[:is_planified] = true
              entity[:planified_in] = planified_info[name]
            end
          end
        end
        
        {
          entities: entities_data,
          planified_info: planified_info,
          total_count: entities_data.length,
          timestamp: Time.now.to_i
        }
      end
      
      def process_entities(entities, result_array, parent_transform, parent_path, level)
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next unless entity.valid?
          
          current_transform = parent_transform * entity.transformation
          
          entity_data = {
            pid: entity.persistent_id,
            type: entity.is_a?(Sketchup::Group) ? "Group" : "Component",
            name: entity.name || "",
            definition_name: entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.name : "",
            layer: entity.layer ? entity.layer.name : "Layer0",
            level: level,
            parent_path: parent_path,
            bounds: get_bounds_info(entity),
            is_makette: false,
            is_mirrored: false,
            is_scaled: false,
            scale_factor: 1.0,
            transformation_type: "Normal",
            quantity: 1,
            is_planified: false,
            planified_in: []
          }
          
          # Verifica se é MakettePro
          if entity.is_a?(Sketchup::ComponentInstance)
            if entity.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
              entity_data[:is_makette] = true
              
              # Analisa transformação usando método Thomas Thomassen
              transform_info = analyze_transformation_thomas_method(current_transform)
              entity_data[:is_mirrored] = transform_info[:is_mirrored]
              entity_data[:is_scaled] = transform_info[:is_scaled]
              entity_data[:scale_factor] = transform_info[:scale_factor]
              entity_data[:transformation_type] = transform_info[:transformation_type]
            end
          end
          
          result_array << entity_data
          
          # Recursão para entidades filhas
          if entity.is_a?(Sketchup::Group)
            new_path = parent_path.empty? ? entity_data[:name] : "#{parent_path} > #{entity_data[:name]}"
            process_entities(entity.entities, result_array, current_transform, new_path, level + 1)
          elsif entity.is_a?(Sketchup::ComponentInstance) && entity.definition
            new_path = parent_path.empty? ? entity_data[:definition_name] : "#{parent_path} > #{entity_data[:definition_name]}"
            process_entities(entity.definition.entities, result_array, current_transform, new_path, level + 1)
          end
        end
      end
      
      def collect_planified_info
        model = Sketchup.active_model
        planified_info = {}
        
        model.entities.grep(Sketchup::Group).each do |group|
          next unless group.valid?
          
          cut_name = group.get_attribute("RJV_Cut", "name")
          if cut_name
            # Este é um grupo de planificação
            report_json = group.get_attribute("RJV_Report", "data")
            if report_json
              begin
                report_data = JSON.parse(report_json)
                
                # Extrai informações sobre as peças planificadas
                if report_data["materials"]
                  report_data["materials"].each do |material|
                    material["parts_list"]&.each do |part|
                      part_name = part["name"]
                      planified_info[part_name] ||= []
                      planified_info[part_name] << {
                        cut_name: cut_name,
                        mode: report_data["layout_mode"],
                        quantity: part["quantity"],
                        material: material["material_name"]
                      }
                    end
                  end
                end
              rescue => e
                puts "Erro ao processar relatório de #{cut_name}: #{e.message}"
              end
            end
          end
        end
        
        planified_info
      end
      
      def get_bounds_info(entity)
        bounds = entity.bounds
        {
          width: (bounds.width / 1.mm).round(1),
          height: (bounds.height / 1.mm).round(1),
          depth: (bounds.depth / 1.mm).round(1)
        }
      end
      
      def analyze_transformation_thomas_method(transform)
        return {
          is_scaled: false,
          is_mirrored: false,
          scale_factor: 1.0,
          transformation_type: "Normal"
        } unless transform
        
        begin
          x_axis = Geom::Vector3d.new(1, 0, 0)
          y_axis = Geom::Vector3d.new(0, 1, 0)
          z_axis = Geom::Vector3d.new(0, 0, 1)
          
          x_scale_raw = x_axis.transform(transform).length
          y_scale_raw = y_axis.transform(transform).length
          z_scale_raw = z_axis.transform(transform).length
          
          unit = 1.to_l
          is_scaled_thomas = !(x_scale_raw == unit && y_scale_raw == unit && z_scale_raw == unit)
          
          x_scale_display = x_scale_raw.to_l.to_f.round(6)
          y_scale_display = y_scale_raw.to_l.to_f.round(6)
          z_scale_display = z_scale_raw.to_l.to_f.round(6)
          
          determinant = transform.xaxis.cross(transform.yaxis).dot(transform.zaxis)
          is_mirrored = determinant < 0
          
          scale_factor = if is_scaled_thomas
            [x_scale_display, y_scale_display, z_scale_display].max
          else
            1.0
          end
          
          transformation_type = case
                               when is_mirrored && is_scaled_thomas
                                 "Espelhada + Escalonada"
                               when is_mirrored && !is_scaled_thomas
                                 "Espelhada"
                               when !is_mirrored && is_scaled_thomas
                                 "Escalonada"
                               else
                                 "Normal"
                               end
          
          {
            is_scaled: is_scaled_thomas,
            is_mirrored: is_mirrored,
            scale_factor: scale_factor.round(3),
            transformation_type: transformation_type
          }
        rescue => e
          {
            is_scaled: false,
            is_mirrored: false,
            scale_factor: 1.0,
            transformation_type: "Erro"
          }
        end
      end
      
      def select_entity_by_pid(pid)
        model = Sketchup.active_model
        entity = model.find_entity_by_persistent_id(pid)
        
        if entity && entity.valid?
          model.selection.clear
          model.selection.add(entity)
          puts "✅ Entidade selecionada: #{entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.name : entity.name}"
        else
          puts "❌ Entidade não encontrada"
        end
      end
      
      def select_multiple_entities(pids)
        model = Sketchup.active_model
        model.selection.clear
        
        pids.each do |pid|
          entity = model.find_entity_by_persistent_id(pid.to_i)
          model.selection.add(entity) if entity && entity.valid?
        end
        
        puts "✅ #{model.selection.length} entidades selecionadas"
      end
      
      def rename_entity(pid, new_name)
        model = Sketchup.active_model
        entity = model.find_entity_by_persistent_id(pid)
        
        if entity && entity.valid?
          model.start_operation("Renomear Entidade", true)
          entity.name = new_name
          model.commit_operation
          
          puts "✅ Entidade renomeada para: #{new_name}"
          send_model_data # Atualiza a interface
        else
          puts "❌ Entidade não encontrada"
        end
      end
      
      def zoom_to_entity(pid)
        model = Sketchup.active_model
        entity = model.find_entity_by_persistent_id(pid)
        
        if entity && entity.valid?
          model.selection.clear
          model.selection.add(entity)
          
          # Zoom para a entidade
          view = model.active_view
          view.zoom(entity)
          
          puts "🔍 Zoom para entidade"
        else
          puts "❌ Entidade não encontrada"
        end
      end
      
      def export_to_csv
        model = Sketchup.active_model
        data = collect_model_data
        
        # Gera CSV
        csv_content = "Nome,Tipo,Layer,MakettePro,Espelhada,Escalonada,Tipo Transformação,Largura(mm),Altura(mm),Profundidade(mm),Caminho\n"
        
        data[:entities].each do |entity|
          name = entity[:name].empty? ? entity[:definition_name] : entity[:name]
          csv_content += [
            name,
            entity[:type],
            entity[:layer],
            entity[:is_makette] ? "Sim" : "Não",
            entity[:is_mirrored] ? "Sim" : "Não",
            entity[:is_scaled] ? "Sim" : "Não",
            entity[:transformation_type],
            entity[:bounds][:width],
            entity[:bounds][:height],
            entity[:bounds][:depth],
            entity[:parent_path]
          ].map { |v| "\"#{v}\"" }.join(",") + "\n"
        end
        
        # Salva arquivo
        path = UI.savepanel("Exportar para CSV", "", "model_inspector_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv")
        if path
          File.write(path, csv_content)
          UI.messagebox("✅ Dados exportados com sucesso!\n\n#{data[:entities].length} entidades exportadas.")
          puts "✅ CSV exportado para: #{path}"
        end
      rescue => e
        UI.messagebox("❌ Erro ao exportar CSV:\n\n#{e.message}")
        puts "❌ Erro ao exportar: #{e.message}"
      end
      
      def setup_selection_observer
        model = Sketchup.active_model
        
        # Remove observer antigo se existir
        if @selection_observer
          model.selection.remove_observer(@selection_observer)
        end
        
        # Cria novo observer
        @selection_observer = SelectionObserver.new(self)
        model.selection.add_observer(@selection_observer)
      end
      
      class SelectionObserver < Sketchup::SelectionObserver
        def initialize(inspector)
          @inspector = inspector
          @last_update = Time.now
        end
        
        def onSelectionBulkChange(selection)
          # Throttle: atualiza no máximo a cada 0.5 segundos
          return if Time.now - @last_update < 0.5
          
          @last_update = Time.now
          update_selection_in_dialog(selection)
        end
        
        private
        
        def update_selection_in_dialog(selection)
          return unless @inspector.instance_variable_get(:@dialog)
          
          selected_pids = selection.map(&:persistent_id)
          dialog = @inspector.instance_variable_get(:@dialog)
          dialog.execute_script("highlightSelectedEntities(#{selected_pids.to_json})")
        end
      end
      
      def generate_html
        <<-HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Model Inspector - RJV</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      background: #f5f7fa;
      color: #2c3e50;
      height: 100vh;
      display: flex;
      flex-direction: column;
    }
    
    /* Header */
    .header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 20px 30px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    
    .header h1 {
      font-size: 24px;
      font-weight: 600;
      margin-bottom: 8px;
    }
    
    .header p {
      opacity: 0.9;
      font-size: 14px;
    }
    
    /* Toolbar */
    .toolbar {
      background: white;
      padding: 15px 30px;
      display: flex;
      gap: 15px;
      align-items: center;
      border-bottom: 1px solid #e1e8ed;
      flex-wrap: wrap;
    }
    
    .search-box {
      flex: 1;
      min-width: 250px;
      position: relative;
    }
    
    .search-box input {
      width: 100%;
      padding: 10px 15px 10px 40px;
      border: 2px solid #e1e8ed;
      border-radius: 8px;
      font-size: 14px;
      transition: all 0.3s;
    }
    
    .search-box input:focus {
      outline: none;
      border-color: #667eea;
      box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
    }
    
    .search-icon {
      position: absolute;
      left: 12px;
      top: 50%;
      transform: translateY(-50%);
      color: #95a5a6;
      font-size: 16px;
    }
    
    .btn {
      padding: 10px 20px;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.3s;
      display: inline-flex;
      align-items: center;
      gap: 8px;
    }
    
    .btn-primary {
      background: #667eea;
      color: white;
    }
    
    .btn-primary:hover {
      background: #5568d3;
      transform: translateY(-1px);
      box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
    }
    
    .btn-secondary {
      background: white;
      color: #667eea;
      border: 2px solid #667eea;
    }
    
    .btn-secondary:hover {
      background: #667eea;
      color: white;
    }
    
    .btn-success {
      background: #2ecc71;
      color: white;
    }
    
    .btn-success:hover {
      background: #27ae60;
    }
    
    /* Stats Bar */
    .stats-bar {
      background: white;
      padding: 15px 30px;
      display: flex;
      gap: 30px;
      border-bottom: 1px solid #e1e8ed;
    }
    
    .stat {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    
    .stat-label {
      font-size: 12px;
      color: #95a5a6;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    
    .stat-value {
      font-size: 20px;
      font-weight: 600;
      color: #2c3e50;
    }
    
    /* Filters */
    .filters {
      background: white;
      padding: 15px 30px;
      display: flex;
      gap: 15px;
      border-bottom: 1px solid #e1e8ed;
      flex-wrap: wrap;
    }
    
    .filter-chip {
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 13px;
      cursor: pointer;
      transition: all 0.3s;
      border: 2px solid #e1e8ed;
      background: white;
    }
    
    .filter-chip:hover {
      border-color: #667eea;
      background: #f8f9ff;
    }
    
    .filter-chip.active {
      background: #667eea;
      color: white;
      border-color: #667eea;
    }
    
    /* Table Container */
    .table-container {
      flex: 1;
      overflow: auto;
      padding: 20px 30px;
    }
    
    table {
      width: 100%;
      background: white;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      border-collapse: separate;
      border-spacing: 0;
    }
    
    thead {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }
    
    th {
      padding: 15px;
      text-align: left;
      font-weight: 600;
      font-size: 13px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      position: sticky;
      top: 0;
      z-index: 10;
      cursor: pointer;
      user-select: none;
    }
    
    th:hover {
      background: rgba(255,255,255,0.1);
    }
    
    td {
      padding: 15px;
      border-bottom: 1px solid #f1f3f5;
      font-size: 14px;
    }
    
    tbody tr {
      transition: all 0.2s;
      cursor: pointer;
    }
    
    tbody tr:hover {
      background: #f8f9ff;
    }
    
    tbody tr.selected {
      background: #e8ebff;
      box-shadow: inset 3px 0 0 #667eea;
    }
    
    /* Badges */
    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.3px;
      white-space: nowrap;
    }
    
    .badge-success {
      background: #d4edda;
      color: #155724;
    }
    
    .badge-danger {
      background: #f8d7da;
      color: #721c24;
    }
    
    .badge-warning {
      background: #fff3cd;
      color: #856404;
    }
    
    .badge-info {
      background: #d1ecf1;
      color: #0c5460;
    }
    
    .badge-secondary {
      background: #e2e3e5;
      color: #383d41;
    }
    
    /* Action Buttons */
    .action-btns {
      display: flex;
      gap: 8px;
    }
    
    .action-btn {
      padding: 6px 12px;
      border: none;
      border-radius: 6px;
      font-size: 12px;
      cursor: pointer;
      transition: all 0.2s;
      background: #f8f9fa;
      color: #495057;
    }
    
    .action-btn:hover {
      background: #667eea;
      color: white;
      transform: scale(1.05);
    }
    
    /* Empty State */
    .empty-state {
      text-align: center;
      padding: 60px 20px;
      color: #95a5a6;
    }
    
    .empty-state-icon {
      font-size: 64px;
      margin-bottom: 20px;
      opacity: 0.5;
    }
    
    .empty-state h3 {
      font-size: 20px;
      margin-bottom: 10px;
    }
    
    .empty-state p {
      font-size: 14px;
    }
    
    /* Loading */
    .loading {
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 40px;
      font-size: 16px;
      color: #667eea;
    }
    
    .spinner {
      border: 3px solid #f3f3f3;
      border-top: 3px solid #667eea;
      border-radius: 50%;
      width: 40px;
      height: 40px;
      animation: spin 1s linear infinite;
      margin-right: 15px;
    }
    
    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }
    
    /* Scrollbar */
    ::-webkit-scrollbar {
      width: 10px;
      height: 10px;
    }
    
    ::-webkit-scrollbar-track {
      background: #f1f1f1;
    }
    
    ::-webkit-scrollbar-thumb {
      background: #667eea;
      border-radius: 5px;
    }
    
    ::-webkit-scrollbar-thumb:hover {
      background: #5568d3;
    }
    
    /* Editable name */
    .editable-name {
      cursor: text;
      padding: 4px 8px;
      border-radius: 4px;
      transition: background 0.2s;
    }
    
    .editable-name:hover {
      background: #f0f0f0;
    }
    
    .name-input {
      width: 100%;
      padding: 4px 8px;
      border: 2px solid #667eea;
      border-radius: 4px;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>🔍 Model Inspector</h1>
    <p>Analise e gerencie todos os objetos do seu modelo</p>
  </div>
  
  <div class="toolbar">
    <div class="search-box">
      <span class="search-icon">🔎</span>
      <input type="text" id="searchInput" placeholder="Buscar por nome, layer ou tipo...">
    </div>
    <button class="btn btn-primary" onclick="refreshData()">
      🔄 Atualizar
    </button>
    <button class="btn btn-success" onclick="exportCSV()">
      📊 Exportar CSV
    </button>
    <button class="btn btn-secondary" onclick="selectAll()">
      ✅ Selecionar Todos
    </button>
  </div>
  
  <div class="stats-bar">
    <div class="stat">
      <span class="stat-label">Total</span>
      <span class="stat-value" id="totalCount">0</span>
    </div>
    <div class="stat">
      <span class="stat-label">MakettePro</span>
      <span class="stat-value" id="maketteCount">0</span>
    </div>
    <div class="stat">
      <span class="stat-label">Espelhadas</span>
      <span class="stat-value" id="mirroredCount">0</span>
    </div>
    <div class="stat">
      <span class="stat-label">Escalonadas</span>
      <span class="stat-value" id="scaledCount">0</span>
    </div>
    <div class="stat">
      <span class="stat-label">Selecionadas</span>
      <span class="stat-value" id="selectedCount">0</span>
    </div>
  </div>
  
  <div class="filters">
    <div class="filter-chip active" data-filter="all" onclick="setFilter('all')">
      🌐 Todos
    </div>
    <div class="filter-chip" data-filter="makette" onclick="setFilter('makette')">
      ⚙️ MakettePro
    </div>
    <div class="filter-chip" data-filter="mirrored" onclick="setFilter('mirrored')">
      🪞 Espelhadas
    </div>
    <div class="filter-chip" data-filter="scaled" onclick="setFilter('scaled')">
      📏 Escalonadas
    </div>
    <div class="filter-chip" data-filter="planified" onclick="setFilter('planified')">
      📋 Planificadas
    </div>
  </div>
  
  <div class="table-container">
    <div id="loadingState" class="loading">
      <div class="spinner"></div>
      <span>Carregando dados do modelo...</span>
    </div>
    <table id="dataTable" style="display: none;">
      <thead>
        <tr>
          <th style="width: 40px;">
            <input type="checkbox" id="selectAllCheckbox" onchange="toggleSelectAll()">
          </th>
          <th onclick="sortTable('name')">Nome 📝</th>
          <th onclick="sortTable('type')">Tipo</th>
          <th>Layer</th>
          <th>MakettePro</th>
          <th>Transformação</th>
          <th>Dimensões (mm)</th>
          <th>Planificada</th>
          <th style="width: 120px;">Ações</th>
        </tr>
      </thead>
      <tbody id="tableBody">
      </tbody>
    </table>
    <div id="emptyState" class="empty-state" style="display: none;">
      <div class="empty-state-icon">📭</div>
      <h3>Nenhum objeto encontrado</h3>
      <p>Tente ajustar os filtros ou fazer uma nova busca</p>
    </div>
  </div>
  
  <script>
    let allData = [];
    let filteredData = [];
    let currentFilter = 'all';
    let currentSort = { column: null, ascending: true };
    let selectedRows = new Set();
    
    // Inicialização
    window.onload = function() {
      sketchup.ready();
    };
    
    document.getElementById('searchInput').addEventListener('input', function(e) {
      filterData();
    });
    
    function updateModelData(data) {
      console.log('Received data:', data);
      allData = data.entities || [];
      
      updateStats(data);
      filterData();
      
      document.getElementById('loadingState').style.display = 'none';
      document.getElementById('dataTable').style.display = 'table';
    }
    
    function updateStats(data) {
      document.getElementById('totalCount').textContent = data.total_count || 0;
      
      const maketteCount = allData.filter(e => e.is_makette).length;
      const mirroredCount = allData.filter(e => e.is_mirrored).length;
      const scaledCount = allData.filter(e => e.is_scaled).length;
      
      document.getElementById('maketteCount').textContent = maketteCount;
      document.getElementById('mirroredCount').textContent = mirroredCount;
      document.getElementById('scaledCount').textContent = scaledCount;
    }
    
    function filterData() {
      const searchTerm = document.getElementById('searchInput').value.toLowerCase();
      
      filteredData = allData.filter(entity => {
        // Filtro de busca
        const name = (entity.name || entity.definition_name || '').toLowerCase();
        const layer = (entity.layer || '').toLowerCase();
        const type = entity.type.toLowerCase();
        const matchesSearch = name.includes(searchTerm) || layer.includes(searchTerm) || type.includes(searchTerm);
        
        if (!matchesSearch) return false;
        
        // Filtro de tipo
        switch(currentFilter) {
          case 'makette':
            return entity.is_makette;
          case 'mirrored':
            return entity.is_mirrored;
          case 'scaled':
            return entity.is_scaled;
          case 'planified':
            return entity.is_planified;
          case 'all':
          default:
            return true;
        }
      });
      
      renderTable();
    }
    
    function renderTable() {
      const tbody = document.getElementById('tableBody');
      tbody.innerHTML = '';
      
      if (filteredData.length === 0) {
        document.getElementById('dataTable').style.display = 'none';
        document.getElementById('emptyState').style.display = 'block';
        return;
      }
      
      document.getElementById('dataTable').style.display = 'table';
      document.getElementById('emptyState').style.display = 'none';
      
      filteredData.forEach(entity => {
        const row = document.createElement('tr');
        row.dataset.pid = entity.pid;
        
        if (selectedRows.has(entity.pid)) {
          row.classList.add('selected');
        }
        
        const displayName = entity.name || entity.definition_name || '(sem nome)';
        const indent = '&nbsp;&nbsp;'.repeat(entity.level);
        
        row.innerHTML = `
          <td>
            <input type="checkbox" ${selectedRows.has(entity.pid) ? 'checked' : ''} 
                   onchange="toggleRowSelection(${entity.pid}, this.checked)">
          </td>
          <td>
            ${indent}<span class="editable-name" onclick="makeEditable(this, ${entity.pid})">${displayName}</span>
          </td>
          <td>
            <span class="badge ${entity.type === 'Component' ? 'badge-info' : 'badge-secondary'}">
              ${entity.type === 'Component' ? '🔷 Component' : '📦 Group'}
            </span>
          </td>
          <td>${entity.layer}</td>
          <td>
            ${entity.is_makette 
              ? '<span class="badge badge-success">✅ Sim</span>' 
              : '<span class="badge badge-secondary">—</span>'}
          </td>
          <td>
            ${getTransformationBadge(entity)}
          </td>
          <td>
            <small>${entity.bounds.width} × ${entity.bounds.height} × ${entity.bounds.depth}</small>
          </td>
          <td>
            ${entity.is_planified 
              ? '<span class="badge badge-warning">📋 Sim</span>' 
              : '<span class="badge badge-secondary">—</span>'}
          </td>
          <td>
            <div class="action-btns">
              <button class="action-btn" onclick="selectEntity(${entity.pid})" title="Selecionar">
                👆
              </button>
              <button class="action-btn" onclick="zoomToEntity(${entity.pid})" title="Zoom">
                🔍
              </button>
            </div>
          </td>
        `;
        
        tbody.appendChild(row);
      });
      
      updateSelectedCount();
    }
    
    function getTransformationBadge(entity) {
      if (entity.is_mirrored && entity.is_scaled) {
        return '<span class="badge badge-danger">🪞📏 Espelhada + Escalonada</span>';
      } else if (entity.is_mirrored) {
        return '<span class="badge badge-warning">🪞 Espelhada</span>';
      } else if (entity.is_scaled) {
        return '<span class="badge badge-info">📏 Escalonada (×' + entity.scale_factor + ')</span>';
      } else {
        return '<span class="badge badge-success">✅ Normal</span>';
      }
    }
    
    function setFilter(filter) {
      currentFilter = filter;
      
      // Atualiza UI dos filtros
      document.querySelectorAll('.filter-chip').forEach(chip => {
        chip.classList.remove('active');
      });
      document.querySelector(`[data-filter="${filter}"]`).classList.add('active');
      
      filterData();
    }
    
    function sortTable(column) {
      if (currentSort.column === column) {
        currentSort.ascending = !currentSort.ascending;
      } else {
        currentSort.column = column;
        currentSort.ascending = true;
      }
      
      filteredData.sort((a, b) => {
        let valA, valB;
        
        switch(column) {
          case 'name':
            valA = (a.name || a.definition_name || '').toLowerCase();
            valB = (b.name || b.definition_name || '').toLowerCase();
            break;
          case 'type':
            valA = a.type;
            valB = b.type;
            break;
          default:
            return 0;
        }
        
        if (valA < valB) return currentSort.ascending ? -1 : 1;
        if (valA > valB) return currentSort.ascending ? 1 : -1;
        return 0;
      });
      
      renderTable();
    }
    
    function toggleRowSelection(pid, checked) {
      if (checked) {
        selectedRows.add(pid);
      } else {
        selectedRows.delete(pid);
      }
      
      const row = document.querySelector(`tr[data-pid="${pid}"]`);
      if (row) {
        if (checked) {
          row.classList.add('selected');
        } else {
          row.classList.remove('selected');
        }
      }
      
      updateSelectedCount();
    }
    
    function toggleSelectAll() {
      const checkbox = document.getElementById('selectAllCheckbox');
      const checkboxes = document.querySelectorAll('tbody input[type="checkbox"]');
      
      checkboxes.forEach(cb => {
        cb.checked = checkbox.checked;
        const pid = parseInt(cb.closest('tr').dataset.pid);
        toggleRowSelection(pid, checkbox.checked);
      });
    }
    
    function selectAll() {
      const pids = filteredData.map(e => e.pid);
      sketchup.select_multiple(JSON.stringify(pids));
    }
    
    function updateSelectedCount() {
      document.getElementById('selectedCount').textContent = selectedRows.size;
    }
    
    function selectEntity(pid) {
      sketchup.select_entity(pid.toString());
    }
    
    function zoomToEntity(pid) {
      sketchup.zoom_to_entity(pid.toString());
    }
    
    function makeEditable(element, pid) {
      const currentName = element.textContent.trim();
      const input = document.createElement('input');
      input.type = 'text';
      input.className = 'name-input';
      input.value = currentName;
      
      input.onblur = function() {
        const newName = input.value.trim();
        if (newName && newName !== currentName) {
          sketchup.rename_entity(pid.toString(), newName);
        }
        element.textContent = newName || currentName;
        element.style.display = 'inline';
        input.remove();
      };
      
      input.onkeydown = function(e) {
        if (e.key === 'Enter') {
          input.blur();
        } else if (e.key === 'Escape') {
          element.textContent = currentName;
          element.style.display = 'inline';
          input.remove();
        }
      };
      
      element.style.display = 'none';
      element.parentNode.insertBefore(input, element);
      input.focus();
      input.select();
    }
    
    function refreshData() {
      document.getElementById('loadingState').style.display = 'flex';
      document.getElementById('dataTable').style.display = 'none';
      selectedRows.clear();
      sketchup.refresh();
    }
    
    function exportCSV() {
      sketchup.export_csv();
    }
    
    function highlightSelectedEntities(pids) {
      // Destaca as entidades selecionadas no SketchUp
      document.querySelectorAll('tbody tr').forEach(row => {
        const pid = parseInt(row.dataset.pid);
        if (pids.includes(pid)) {
          row.classList.add('selected');
          selectedRows.add(pid);
          const checkbox = row.querySelector('input[type="checkbox"]');
          if (checkbox) checkbox.checked = true;
        } else {
          row.classList.remove('selected');
          selectedRows.delete(pid);
          const checkbox = row.querySelector('input[type="checkbox"]');
          if (checkbox) checkbox.checked = false;
        }
      });
      
      updateSelectedCount();
    }
    
    // Atalhos de teclado
    document.addEventListener('keydown', function(e) {
      // Ctrl/Cmd + A: Selecionar todos
      if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
        e.preventDefault();
        selectAll();
      }
      
      // Ctrl/Cmd + F: Focar na busca
      if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
        e.preventDefault();
        document.getElementById('searchInput').focus();
      }
      
      // F5: Atualizar
      if (e.key === 'F5') {
        e.preventDefault();
        refreshData();
      }
    });
  </script>
</body>
</html>
        HTML
      end
      
    end
  end
end