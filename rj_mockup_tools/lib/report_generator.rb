# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'set'

module Rjv
  module MockupTools
    module ReportGenerator
      extend self
      
      @report_dialog = nil
      
      CONFIG_KEY = "RJV_ProjectConfig".freeze
      
      DEFAULT_PROJECT_CONFIG = {
        "project_name" => "Novo Projeto",
        "designer" => "N/A",
        "workshop" => "RJV Maquetaria",
        "scale" => "1:100"
      }.freeze

      # --- MÉTODOS PÚBLICOS ---

      def generate_layout_report
        model = Sketchup.active_model
        selection = model.selection
        
        # NOVO: Se não há seleção, busca TODOS os cortes no modelo
        if selection.empty?
          puts "🔍 Nenhuma seleção. Buscando todos os cortes planificados no modelo..."
          all_cuts = find_all_cuts_in_model(model)
          
          if all_cuts.empty?
            UI.messagebox("Nenhum corte planificado encontrado no modelo.\n\nDica: Execute o Planifier primeiro ou selecione um grupo de corte específico.")
            return
          end
          
          # Pergunta se quer todos ou escolher específicos
          choice = UI.messagebox("Encontrados #{all_cuts.length} cortes planificados:\n\n#{all_cuts.map(&:name).join(', ')}\n\nDeseja gerar relatório de todos os cortes?", MB_YESNOCANCEL)
          
          case choice
          when IDYES
            report_groups = all_cuts
            puts "📊 Gerando relatório de todos os #{all_cuts.length} cortes"
          when IDNO
            # Permite escolher quais cortes
            selected_cuts = choose_specific_cuts(all_cuts)
            return if selected_cuts.empty?
            report_groups = selected_cuts
          else
            return # Cancelado
          end
          
        else
          # Verifica seleção atual
          report_groups = selection.grep(Sketchup::Group).select { |g| g.get_attribute("RJV_Report", "data") }
          
          if report_groups.empty?
            UI.messagebox("Nenhum grupo com dados de planificação encontrado na seleção.\n\nSelecione um ou mais grupos de corte planificado.")
            return
          end
        end
        
        project_config = get_or_request_project_config(model)
        return unless project_config
        
        # NOVO: Processa múltiplos cortes
        if report_groups.length == 1
          # Relatório de corte único (mantém compatibilidade)
          puts "📋 Gerando relatório de corte único: #{report_groups.first.name}"
          processed_data = process_single_cut(report_groups.first)
        else
          # Relatório de múltiplos cortes
          puts "📋 Gerando relatório de múltiplos cortes: #{report_groups.length} cortes"
          processed_data = process_multiple_cuts(report_groups)
        end
        
        processed_data["project_config"] = project_config
        processed_data["generated_at"] = Time.now.strftime("%d/%m/%Y")
        processed_data["is_multi_cut"] = report_groups.length > 1
        
        show_report_dialog(processed_data)
      end

      def configure_project
        model = Sketchup.active_model
        
        current_config_json = model.get_attribute(CONFIG_KEY, "data")
        current_config = if current_config_json
          JSON.parse(current_config_json) rescue DEFAULT_PROJECT_CONFIG.dup
        else
          DEFAULT_PROJECT_CONFIG.dup
        end

        prompts = ["Nome do Projeto:", "Desenhista:", "Maquetaria:", "Escala:"]
        defaults = [
          current_config["project_name"],
          current_config["designer"],
          current_config["workshop"],
          current_config["scale"]
        ]
        
        results = UI.inputbox(prompts, defaults, "Editar Configurações do Projeto")
        
        if results
          new_config = {
            "project_name" => results[0],
            "designer" => results[1],
            "workshop" => results[2],
            "scale" => results[3]
          }
          model.set_attribute(CONFIG_KEY, "data", JSON.generate(new_config))
          UI.messagebox("Configurações do projeto foram atualizadas com sucesso!")
        end
      end

      # --- MÉTODOS PRIVADOS ---
      private

      # NOVO: Encontra todos os cortes no modelo
      def find_all_cuts_in_model(model)
        cuts = []
        
        model.entities.grep(Sketchup::Group).each do |group|
          # Verifica se tem dados de relatório E nome do corte
          if group.get_attribute("RJV_Report", "data") && group.get_attribute("RJV_Cut", "name")
            cuts << group
          end
        end
        
        cuts.sort_by { |cut| cut.get_attribute("RJV_Cut", "created_at") || "0" }
      end

      # CORRIGIDO: Permite escolher cortes específicos usando dropdown
      def choose_specific_cuts(all_cuts)
        if all_cuts.length <= 5
          # Para poucos cortes, usa inputbox com dropdowns
          return choose_cuts_with_dropdowns(all_cuts)
        else
          # Para muitos cortes, usa listbox
          return choose_cuts_with_listbox(all_cuts)
        end
      end
      
      # Método para poucos cortes (até 5) usando dropdowns
      def choose_cuts_with_dropdowns(all_cuts)
        cut_names = all_cuts.map { |cut| 
          cut_name = cut.get_attribute("RJV_Cut", "name") || cut.name
          mode = cut.get_attribute("RJV_Cut", "mode") || "N/A"
          created = cut.get_attribute("RJV_Cut", "created_at") || "N/A"
          "#{cut_name} (#{mode}) - #{created}"
        }
        
        prompts = cut_names.map.with_index { |name, i| "#{i+1}. #{name}:" }
        defaults = Array.new(cut_names.length, "Não")
        lists = Array.new(cut_names.length, "Sim|Não")
        
        results = UI.inputbox(prompts, defaults, lists, "Escolher Cortes para Relatório")
        return [] if results == false
        
        selected_cuts = []
        results.each_with_index do |choice, index|
          selected_cuts << all_cuts[index] if choice == "Sim"
        end
        
        if selected_cuts.empty?
          UI.messagebox("Nenhum corte foi selecionado.")
          return []
        end
        
        puts "DEBUG: Selecionados #{selected_cuts.length} cortes: #{selected_cuts.map(&:name).join(', ')}"
        selected_cuts
      end
      
      # Método para muitos cortes usando UI.listbox
      def choose_cuts_with_listbox(all_cuts)
        cut_names = all_cuts.map.with_index { |cut, i| 
          cut_name = cut.get_attribute("RJV_Cut", "name") || cut.name
          mode = cut.get_attribute("RJV_Cut", "mode") || "N/A"
          created = cut.get_attribute("RJV_Cut", "created_at") || "N/A"
          "#{i+1}. #{cut_name} (#{mode}) - #{created}"
        }
        
        selected_indices = UI.listbox(cut_names, false, "Escolher Cortes para Relatório")
        return [] if selected_indices.nil? || selected_indices.empty?
        
        selected_cuts = selected_indices.map { |index| all_cuts[index] }
        
        puts "DEBUG: Selecionados #{selected_cuts.length} cortes via listbox"
        selected_cuts
      end

      # NOVO: Processa um único corte (mantém compatibilidade)
      def process_single_cut(group)
        report_json = group.get_attribute("RJV_Report", "data")
        
        begin
          raw_data = JSON.parse(report_json)
        rescue JSON::ParserError => e
          puts "Erro ao ler dados do corte #{group.name}: #{e.message}"
          return {}
        end
        
        # Adiciona informações do corte
        cut_info = {
          "cut_name" => group.get_attribute("RJV_Cut", "name") || raw_data["cut_name"] || group.name,
          "cut_mode" => group.get_attribute("RJV_Cut", "mode") || raw_data["layout_mode"] || "N/A",
          "cut_created_at" => group.get_attribute("RJV_Cut", "created_at") || "N/A"
        }
        
        processed_data = process_and_group_data(raw_data)
        processed_data.merge!(cut_info)
        processed_data["cuts"] = [cut_info.merge(processed_data)]  # Para compatibilidade com template
        
        processed_data
      end

      # NOVO: Processa múltiplos cortes
      def process_multiple_cuts(groups)
        all_cuts_data = []
        combined_materials = {}
        total_summary = { "total_materials" => 0, "total_parts" => 0, "total_boards" => 0 }
        
        groups.each do |group|
          report_json = group.get_attribute("RJV_Report", "data")
          
          begin
            raw_data = JSON.parse(report_json)
          rescue JSON::ParserError => e
            puts "Erro ao ler dados do corte #{group.name}: #{e.message}"
            next
          end
          
          # Informações do corte
          cut_info = {
            "cut_name" => group.get_attribute("RJV_Cut", "name") || raw_data["cut_name"] || group.name,
            "cut_mode" => group.get_attribute("RJV_Cut", "mode") || raw_data["layout_mode"] || "N/A",
            "cut_created_at" => group.get_attribute("RJV_Cut", "created_at") || "N/A"
          }
          
          # Processa dados do corte
          processed_cut = process_and_group_data(raw_data)
          processed_cut.merge!(cut_info)
          
          all_cuts_data << processed_cut
          
          # Combina materiais de todos os cortes
          (processed_cut["materials"] || []).each do |material|
            layer_name = material["layer_name"]
            
            if combined_materials[layer_name]
              # Soma pranchas e peças
              combined_materials[layer_name]["boards_count"] += material["boards_count"]
              combined_materials[layer_name]["parts_count"] += material["parts_count"]
              
              # Combina listas de peças
              existing_parts = combined_materials[layer_name]["parts_list"]
              new_parts = material["parts_list"]
              
              parts_hash = {}
              (existing_parts + new_parts).each do |part|
                key = part[:name] || part["name"]
                parts_hash[key] = (parts_hash[key] || 0) + (part[:quantity] || part["quantity"])
              end
              
              combined_materials[layer_name]["parts_list"] = parts_hash.map { |name, qty| { name: name, quantity: qty } }
              
            else
              combined_materials[layer_name] = material.dup
            end
          end
          
          # Soma totais
          cut_summary = processed_cut["summary"] || {}
          total_summary["total_parts"] += cut_summary["total_parts"] || 0
          total_summary["total_boards"] += cut_summary["total_boards"] || 0
        end
        
        total_summary["total_materials"] = combined_materials.length
        
        {
          "cuts" => all_cuts_data,
          "materials" => combined_materials.values,
          "summary" => total_summary,
          "cut_name" => "Múltiplos Cortes (#{groups.length})",
          "cut_mode" => "Consolidado",
          "cuts_count" => groups.length
        }
      end

      def show_report_dialog(data)
        @report_dialog&.close if @report_dialog && @report_dialog.visible?
        
        dialog_options = {
          dialog_title: "Ficha de Corte - RJV Mockup Tools",
          preferences_key: "RjvMockupTools_CutSheetCompact",
          scrollable: true, resizable: true,
          width: 1200, height: 800,
          style: UI::HtmlDialog::STYLE_DIALOG
        }
        
        @report_dialog = UI::HtmlDialog.new(dialog_options)
        
        html_template = get_html_template_content
        json_data = data.to_json
        
        html_com_dados = html_template.sub('// %%DATA_PLACEHOLDER%%', "const reportData = #{json_data};")
        
        @report_dialog.set_html(html_com_dados)
        
        @report_dialog.add_action_callback("export_html") do |_|
          export_to_file(data)
        end
        
        @report_dialog.add_action_callback("get_file_path") do |_|
          model = Sketchup.active_model
          file_path = model.path
          if file_path && !file_path.empty?
            file_name = File.basename(file_path)
            @report_dialog.execute_script("document.getElementById('file-location').textContent = '#{file_name}';")
          else
            @report_dialog.execute_script("document.getElementById('file-location').textContent = 'documento não salvo';")
          end
        end
        
        @report_dialog.show
      end

      def get_or_request_project_config(model)
        config_json = model.get_attribute(CONFIG_KEY, "data")
        
        if config_json
          begin
            return JSON.parse(config_json)
          rescue
          end
        end
        
        prompts = ["Nome do Projeto:", "Desenhista:", "Maquetaria:", "Escala:"]
        defaults = [DEFAULT_PROJECT_CONFIG["project_name"], DEFAULT_PROJECT_CONFIG["designer"], DEFAULT_PROJECT_CONFIG["workshop"], DEFAULT_PROJECT_CONFIG["scale"]]
        
        results = UI.inputbox(prompts, defaults, "Configurações do Projeto (Primeira Vez)")
        return nil unless results
        
        new_config = {
          "project_name" => results[0],
          "designer" => results[1],
          "workshop" => results[2],
          "scale" => results[3]
        }
        
        model.set_attribute(CONFIG_KEY, "data", JSON.generate(new_config))
        
        return new_config
      end
      
      def process_and_group_data(raw_data)
        processed_materials = (raw_data["materials"] || []).map do |material|
          parts_aggregator = Hash.new(0)
          
          (material["parts_list"] || []).each do |part|
            display_name = format_part_name(part)
            parts_aggregator[display_name] += part["quantity"]
          end
          
          grouped_parts_list = parts_aggregator.map do |name, quantity|
            { name: name, quantity: quantity }
          end.sort_by { |part| part[:name] }
          
          {
            "layer_name" => material["layer_name"],
            "boards_count" => material["boards_count"],
            "parts_count" => grouped_parts_list.sum { |p| p[:quantity] },
            "parts_list" => grouped_parts_list
          }
        end

        total_parts = processed_materials.sum { |m| m["parts_count"] }
        total_boards = processed_materials.sum { |m| m["boards_count"] }
        
        summary = {
          "total_materials" => processed_materials.length,
          "total_parts" => total_parts,
          "total_boards" => total_boards
        }
        
        { "materials" => processed_materials, "summary" => summary }
      end
      
      def format_part_name(part)
        base_name = part["name"]
        type = part["transformation_type"]
        
        # NOVO: Calcula dimensões reais considerando escala
        dimensions = ""
        if part["dimensions"]
          dims_parts = part["dimensions"].split('x')
          if dims_parts.length >= 2
            # Dimensões originais (em mm, remove "mm" se houver)
            x_original = dims_parts[0].strip.gsub(/mm$/, '').to_f
            y_original = dims_parts[1].strip.gsub(/mm$/, '').to_f
            
            # Aplica escala se a peça for escalonada
            if type.include?("Escalonada") && part["scale_details"]
              scale_x = part.dig("scale_details", "x") || 1.0
              scale_y = part.dig("scale_details", "y") || 1.0
              
              # Calcula dimensões reais (escalonadas)
              x_real = (x_original * scale_x).round(1)
              y_real = (y_original * scale_y).round(1)
              
              dimensions = " (#{x_real.to_i}×#{y_real.to_i})"
            else
              # Dimensões normais (sem escala)
              dimensions = " (#{x_original.to_i}×#{y_original.to_i})"
            end
          end
        end
        
        # NOVO: Só ícones, sem texto explicativo
        case type
        when "Normal" 
          "#{base_name}#{dimensions}"
        when "Espelhada" 
          "#{base_name}#{dimensions} 🪞"
        when "Escalonada"
          "#{base_name}#{dimensions} 📏"
        when "Espelhada e Escalonada"
          "#{base_name}#{dimensions} 🪞📏"
        else 
          "#{base_name}#{dimensions}"
        end
      end
      
      def export_to_file(data)
        cut_name = data["cut_name"] || "relatorio"
        safe_name = cut_name.gsub(/[^\w\s\-]/, '').strip.gsub(/\s+/, '_')
        
        save_path = UI.savepanel("Exportar Ficha de Corte", "", "corte_#{safe_name}.html")
        return unless save_path
        
        html_template_content = get_html_template_content
        
        export_html = html_template_content.gsub(/<div class="action-bar">.*?<\/div>/m, '')
        export_html.sub!(
          '// %%DATA_PLACEHOLDER%%',
          "const reportData = #{data.to_json};"
        )
        
        File.write(save_path, export_html, encoding: 'UTF-8')
        UI.messagebox("Relatório exportado com sucesso para:\n#{save_path}")
      end

      # ======================================================================
      # ================== TEMPLATE HTML ATUALIZADO ========================
      # ======================================================================
      def get_html_template_content
        %{<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ficha de Corte</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
            --bg-main: #eef2f9;
            --bg-card: #ffffff;
            --text-dark: #1e293b;
            --text-light: #64748b;
            --border-color: #cbd5e1;
            --header-bg: #0f172a;
            --accent-color: #0ea5e9;
            --shadow: 0 4px 6px -1px rgba(0,0,0,0.07), 0 2px 4px -2px rgba(0,0,0,0.07);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: var(--font-family); background-color: var(--bg-main); color: var(--text-dark); line-height: 1.5; font-size: 13px; }
        .page-container { max-width: 210mm; margin: 15px auto; }
        .action-bar { display: flex; gap: 8px; padding: 10px; background-color: #fff; border-radius: 8px; box-shadow: var(--shadow); margin-bottom: 15px; }
        .btn { display: inline-flex; align-items: center; gap: 8px; background-color: var(--header-bg); color: white; border: none; padding: 8px 14px; border-radius: 6px; font-weight: 600; font-size: 12px; cursor: pointer; transition: background-color 0.2s; }
        .btn:hover { background-color: #334155; }
        .btn.secondary { background-color: #f1f5f9; color: var(--text-dark); }
        .btn.secondary:hover { background-color: #e2e8f0; }

        .cut-sheet { background: var(--bg-card); border-radius: 8px; box-shadow: var(--shadow); overflow: hidden; }
        .header { background: var(--header-bg); color: white; padding: 15px 20px; display: flex; justify-content: space-between; align-items: center; }
        .header h1 { font-size: 18px; font-weight: 700; }
        .header-details { font-size: 12px; opacity: 0.8; text-align: right; }
        
        /* NOVO: Seção do corte */
        .cut-info { background-color: #f8fafc; border-bottom: 1px solid var(--border-color); padding: 12px 20px; }
        .cut-info h2 { font-size: 16px; font-weight: 600; color: var(--header-bg); margin-bottom: 4px; }
        .cut-meta { display: flex; gap: 20px; font-size: 12px; color: var(--text-light); }
        .cut-meta span { display: flex; align-items: center; gap: 4px; }
        
        /* NOVO: Para múltiplos cortes */
        .multi-cuts-header { background-color: #fef3c7; border-bottom: 1px solid #f59e0b; padding: 12px 20px; }
        .multi-cuts-header h2 { color: #92400e; font-size: 16px; }
        .cuts-list { margin-top: 8px; display: flex; flex-wrap: wrap; gap: 8px; }
        .cut-tag { background-color: #fbbf24; color: #92400e; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 500; }

        .summary-bar { display: grid; grid-template-columns: repeat(4, 1fr); background-color: #f8fafc; border-bottom: 1px solid var(--border-color); }
        .summary-item { padding: 10px; text-align: center; border-right: 1px solid var(--border-color); }
        .summary-item:last-child { border-right: none; }
        .summary-item .value { font-size: 20px; font-weight: 700; }
        .summary-item .label { font-size: 10px; text-transform: uppercase; color: var(--text-light); }

        .main-content { padding: 20px; }
        .materials-grid { display: grid; grid-template-columns: 1fr; gap: 20px; }
        .material-card { border: 1px solid var(--border-color); border-radius: 8px; overflow: hidden; }
        .material-header { background-color: #f8fafc; padding: 10px 15px; border-bottom: 1px solid var(--border-color); display: flex; justify-content: space-between; align-items: center; }
        .material-name { font-size: 15px; font-weight: 600; }
        .material-stats { font-size: 12px; color: var(--text-light); }
        .material-stats strong { color: var(--text-dark); }
        
        .parts-list { padding: 15px; column-count: 4; column-gap: 20px; }
        .part-item { display: flex; justify-content: space-between; align-items: center; padding: 6px 8px; border-bottom: 1px solid #f1f5f9; page-break-inside: avoid; }
        .part-item .name { font-weight: 600; color: var(--text-dark); }
        .part-item .dimensions { font-size: 10px; color: var(--text-light); margin-left: 6px; }
        .part-item .qty { font-weight: 700; background-color: #f1f5f9; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
        
        /* NOVO: Footer com créditos */
        .footer { background-color: #f8fafc; border-top: 1px solid var(--border-color); padding: 8px 20px; font-size: 10px; color: var(--text-light); display: flex; justify-content: space-between; align-items: center; }
        .footer .credits { font-weight: 500; }
        .footer .file-path { font-family: monospace; background-color: #e2e8f0; padding: 2px 6px; border-radius: 3px; }
        
        @media print {
            body { background: white; font-size: 9pt; }
            .page-container { margin: 0; max-width: 100%; }
            .action-bar, .cut-sheet { box-shadow: none; }
            .cut-sheet { border: 1px solid #ccc; border-radius: 0; }
            .material-card { page-break-inside: avoid; }
            .parts-list { column-count: 4; }
            .footer { border-top: 1px solid #ccc; }
        }
    </style>
</head>
<body>
    <div class="page-container">
        <div class="action-bar">
            <button class="btn" onclick="window.print()"><i class="fas fa-print"></i> Imprimir / PDF</button>
            <button class="btn secondary" onclick="callAction('export_html')"><i class="fas fa-file-export"></i> Exportar HTML</button>
            <button class="btn secondary" onclick="window.close()" style="margin-left: auto;"><i class="fas fa-times"></i> Fechar</button>
        </div>

        <div class="cut-sheet">
            <header class="header">
                <div>
                    <h1>Ficha de Corte: <span id="project-name"></span></h1>
                </div>
                <div class="header-details">
                    <div id="designer"></div>
                    <div id="workshop-scale"></div>
                </div>
            </header>
            
            <!-- NOVO: Informações do corte -->
            <div id="cut-info-section"></div>
            
            <div class="summary-bar">
                <div class="summary-item"><div class="value" id="total-materials">0</div><div class="label">Materiais</div></div>
                <div class="summary-item"><div class="value" id="total-variations">0</div><div class="label">Variações</div></div>
                <div class="summary-item"><div class="value" id="total-parts">0</div><div class="label">Peças Totais</div></div>
                <div class="summary-item"><div class="value" id="total-boards">0</div><div class="label">Pranchas</div></div>
            </div>
            <main class="main-content">
                <div class="materials-grid" id="materials-grid">
                    <!-- Gerado por JS -->
                </div>
            </main>
            
            <!-- NOVO: Footer com créditos -->
            <footer class="footer">
                <div class="credits">
                    <i class="fas fa-code"></i> Desenvolvido por Roberto Jackson Vieira
                </div>
                <div class="file-path" id="file-path">
                    <i class="fas fa-file-alt"></i> <span id="file-location">documento não salvo</span>
                </div>
            </footer>
        </div>
    </div>

    <script>
        // %%DATA_PLACEHOLDER%%
        
        function callAction(action) {
            if (action === 'export_html') {
                if (typeof sketchup !== 'undefined' && typeof sketchup.call === 'function') {
                    sketchup.call(action);
                } else {
                    alert('Funcionalidade de exportar apenas disponível no SketchUp.');
                }
            }
        }

        function renderReport(data) {
            if (!data) {
                document.body.innerHTML = "<h1>Erro ao carregar dados.</h1>";
                return;
            }
            
            const config = data.project_config || {};
            document.getElementById('project-name').textContent = config.project_name || 'Projeto';
            document.getElementById('designer').textContent = `Desenhista: \${config.designer || 'N/A'}`;
            document.getElementById('workshop-scale').textContent = `\${config.workshop || 'Maquetaria'} | Escala: \${config.scale || 'N/A'}`;
            
            // NOVO: Renderiza informações do corte
            renderCutInfo(data);
            
            const summary = data.summary || {};
            document.getElementById('total-materials').textContent = summary.total_materials || 0;
            document.getElementById('total-parts').textContent = summary.total_parts || 0;
            document.getElementById('total-boards').textContent = summary.total_boards || 0;
            const uniqueVariations = new Set((data.materials || []).flatMap(m => (m.parts_list || []).map(p => p.name))).size;
            document.getElementById('total-variations').textContent = uniqueVariations;

            const materialsContainer = document.getElementById('materials-grid');
            materialsContainer.innerHTML = '';
            (data.materials || []).forEach(material => {
                const card = document.createElement('div');
                card.className = 'material-card';
                const materialName = (material.layer_name || "Material").replace(/^MU_/, '').replace(/_/g, ' ');
                
                const partsListHTML = (material.parts_list || [])
                    .map(part => {
                        // NOVO: Separa nome e dimensões
                        const fullName = part.name;
                        const dimensionsMatch = fullName.match(/\s+\((\d+×\d+)\)(\s*[🪞📏]*)?$/);
                        
                        if (dimensionsMatch) {
                            const name = fullName.substring(0, dimensionsMatch.index);
                            const dimensions = dimensionsMatch[1];
                            const icons = dimensionsMatch[2] || '';
                            return `<div class="part-item">
                                <div>
                                    <span class="name">${name}${icons}</span>
                                    <span class="dimensions">${dimensions}</span>
                                </div>
                                <span class="qty">${part.quantity}</span>
                            </div>`;
                        } else {
                            return `<div class="part-item">
                                <span class="name">${fullName}</span>
                                <span class="qty">${part.quantity}</span>
                            </div>`;
                        }
                    })
                    .join('');
                
                card.innerHTML = \`
                    <div class="material-header">
                        <h2 class="material-name">\${materialName}</h2>
                        <div class="material-stats">
                            <span>Pranchas: <strong>\${material.boards_count || 0}</strong></span>
                        </div>
                    </div>
                    <div class="parts-list">\${partsListHTML || '<p>Nenhuma peça.</p>'}</div>
                \`;
                materialsContainer.appendChild(card);
            });
        }

        // NOVO: Renderiza informações do corte
        function renderCutInfo(data) {
            const cutInfoSection = document.getElementById('cut-info-section');
            
            if (data.is_multi_cut) {
                // Múltiplos cortes
                cutInfoSection.innerHTML = \`
                    <div class="multi-cuts-header">
                        <h2><i class="fas fa-layer-group"></i> \${data.cuts_count} Cortes Consolidados</h2>
                        <div class="cuts-list">
                            \${(data.cuts || []).map(cut => \`<span class="cut-tag">\${cut.cut_name}</span>\`).join('')}
                        </div>
                    </div>
                \`;
            } else {
                // Corte único
                const cutName = data.cut_name || 'N/A';
                const cutMode = data.cut_mode || 'N/A';
                const cutDate = data.cut_created_at || 'N/A';
                
                cutInfoSection.innerHTML = \`
                    <div class="cut-info">
                        <h2><i class="fas fa-cut"></i> \${cutName}</h2>
                        <div class="cut-meta">
                            <span><i class="fas fa-cogs"></i> Modo: \${cutMode}</span>
                            <span><i class="fas fa-calendar-alt"></i> Criado: \${cutDate}</span>
                        </div>
                    </div>
                \`;
            }
        }

        // NOVO: Atualiza caminho do arquivo (se disponível via SketchUp)
        function updateFilePath() {
            if (typeof sketchup !== 'undefined') {
                try {
                    sketchup.call('get_file_path');
                } catch (e) {
                    document.getElementById('file-location').textContent = 'documento não salvo';
                }
            } else {
                document.getElementById('file-location').textContent = 'visualização externa';
            }
        }

        document.addEventListener('DOMContentLoaded', () => {
            if (typeof reportData !== 'undefined') {
                renderReport(reportData);
                updateFilePath();
            } else {
                document.body.innerHTML = '<h1 style="font-family: sans-serif; text-align: center; padding: 50px; color: red;">Erro: Falha ao carregar dados do SketchUp.</h1>';
            }
        });
    </script>
</body>
</html>}
      end

    end # Fim do módulo ReportGenerator
  end # Fim do módulo MockupTools
end # Fim do módulo Rjv