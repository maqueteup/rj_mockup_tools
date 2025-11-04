# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'set'

module Rjv
  module MockupTools
    module Planifier
      extend self
      
      # Configurações padrão
      DEFAULT_SETTINGS = {
        "part_spacing" => 2.0,      # mm - espaçamento entre peças
        "board_margin" => 5.0,      # mm - margem da borda da prancha
        "board_spacing" => 50.0,    # mm - espaçamento entre pranchas
        "material_spacing" => 200.0 # mm - espaçamento entre materiais
      }.freeze
      
      BOARD_LAYER_NAME = "RJV_Board".freeze
      BOARD_COLOR = "Yellow".freeze
      
      # Caminhos usando método do SketchUp
      PROPERTIES_JSON_PATH = File.join(Sketchup.find_support_file("Plugins"), "rj_mockup_tools", "data", "properties.json")
      USER_SETTINGS_PATH = File.join(Sketchup.find_support_file("Plugins"), "rj_mockup_tools", "data", "user_settings.json")
      
      # Método principal chamado pelo menu/toolbar
      def run
        planificar
      end
      
      def planificar
        mod = Sketchup.active_model
        sel = mod.selection
        SKETCHUP_CONSOLE.clear
        
        if sel.empty?
          UI.messagebox("Selecione as peças para planificar")
          return
        end
        
        # GUARDA a seleção ANTES de sair do contexto
        selected_entities = sel.to_a.dup
        
        # FORÇAR SAÍDA PARA RAIZ DO MODELO
        if mod.active_path && !mod.active_path.empty?
          puts "⚠️ Saindo de contexto aninhado..."
          while mod.active_path && !mod.active_path.empty?
            mod.close_active
          end
          puts "✅ Agora na raiz do modelo"
          
          # RESTAURA a seleção após sair do contexto
          sel.clear
          selected_entities.each { |e| sel.add(e) if e.valid? }
        end
        
        # VERIFICAÇÃO DE COLISÕES
        check_collisions = UI.messagebox(
          "Deseja verificar colisões antes de planificar?\n\n" +
          "⚠️ A verificação pode levar alguns segundos em modelos grandes.\n\n" +
          "• SIM: Verifica colisões (recomendado)\n" +
          "• NÃO: Pula verificação (mais rápido)",
          MB_YESNO,
          "Verificação de Colisões"
        )
        
        if check_collisions == IDYES
          puts "🔍 Verificando colisões na seleção..."
          collision_results = check_collisions_in_selection(mod.selection)
          
          if collision_results[:has_collisions]
            collision_count = collision_results[:collision_pairs].length
            internal_collisions = collision_results[:collision_pairs].select { |pair| pair[:collision_type] == "interna" }
            external_collisions = collision_results[:collision_pairs].select { |pair| pair[:collision_type] == "externa" }
            
            collision_message = "⚠️ COLISÕES DETECTADAS!\n\n"
            collision_message += "Foram encontradas #{collision_count} colisão(ões):\n\n"
            
            if internal_collisions.any?
              collision_message += "🔴 Colisões entre peças selecionadas (#{internal_collisions.length}):\n"
              internal_collisions.first(5).each_with_index do |pair, index|
                collision_message += "   #{index + 1}. #{pair[:name1]} ↔ #{pair[:name2]}\n"
              end
              collision_message += "   ... e mais #{internal_collisions.length - 5}\n" if internal_collisions.length > 5
              collision_message += "\n"
            end
            
            if external_collisions.any?
              collision_message += "🟡 Colisões com peças do modelo (#{external_collisions.length}):\n"
              external_collisions.first(5).each_with_index do |pair, index|
                collision_message += "   #{index + 1}. #{pair[:name1]} ⚡ #{pair[:name2]}\n"
              end
              collision_message += "   ... e mais #{external_collisions.length - 5}\n" if external_collisions.length > 5
              collision_message += "\n"
            end
            
            collision_message += "Deseja continuar com a planificação mesmo assim?\n\n"
            collision_message += "• SIM: Continua a planificação\n"
            collision_message += "• NÃO: Abre o analisador de colisões para revisar"
            
            result = UI.messagebox(collision_message, MB_YESNO, "Colisões Detectadas")
            
            if result == IDNO
              puts "📋 Usuário escolheu revisar colisões. Abrindo analisador..."
              colliding_instances = get_colliding_instances(collision_results[:collision_pairs], collision_results[:all_instances])
              open_collision_analyzer_with_selection(colliding_instances)
              return
            else
              puts "▶️ Usuário escolheu continuar mesmo com colisões."
            end
          else
            puts "✅ Nenhuma colisão detectada. Prosseguindo com a planificação."
          end
        else
          puts "⏭️ Verificação de colisões ignorada pelo usuário."
        end
        
        # Solicita configurações do usuário
        mode_and_settings = show_configuration_dialog
        return if mode_and_settings.nil?
        
        mode = mode_and_settings[:mode]
        settings = mode_and_settings[:settings]
        
        # Carrega propriedades dos materiais (para modos Com Veios e Nesting)
        materials_data = load_materials_data
        
        mod.start_operation("Planificar - #{mode}", true)
        
        begin
          puts "=" * 60
          puts "🔍 EXTRAINDO INSTÂNCIAS MAKETTEPRO"
          puts "=" * 60
          
          # 1. Extrai APENAS MakettePro
          all_instances = extract_makettepro_instances(sel)
          
          if all_instances.empty?
            UI.messagebox("Nenhuma peça 'MakettePro' encontrada")
            mod.abort_operation
            return
          end
          
          puts "📦 Encontradas #{all_instances.length} peças MakettePro"
          
          # 2. CLASSIFICA por tipo E por layer (material)
          puts "=" * 60
          puts "🔍 CLASSIFICANDO PEÇAS"
          puts "=" * 60
          
          classified = classify_instances(all_instances)
          
          puts "  ✓ Normais: #{classified[:normal].length}"
          puts "  ✓ Espelhadas: #{classified[:mirrored].length}"
          puts "  ✓ Escalonadas: #{classified[:scaled].length}"
          puts "  ✓ Escalonadas + Espelhadas: #{classified[:scaled_mirrored].length}"
          
          # 3. Agrupa por layer (material)
          data_by_layer = {}
          [:normal, :mirrored, :scaled, :scaled_mirrored].each do |type|
            classified[type].each do |data|
              layer = data[:layer]
              data_by_layer[layer] ||= { normal: [], mirrored: [], scaled: [], scaled_mirrored: [] }
              data_by_layer[layer][type] << data
            end
          end
          
          # 4. PLANIFICA cada material separadamente
          all_groups = []
          org = Geom::Point3d.new(0, 0, 0)
          material_spacing = settings["material_spacing"].mm
          
          # Setup layers
          setup_layers(mod)
          
          data_by_layer.each do |layer, types_hash|
            next unless layer
            
            puts "=" * 60
            puts "📐 PROCESSANDO MATERIAL: #{layer.name}"
            puts "=" * 60
            
            # Encontra propriedades do material
            material_info = find_material_by_layer(materials_data, layer.name)
            
            # Processa cada tipo de transformação
            [:normal, :mirrored, :scaled, :scaled_mirrored].each do |type|
              next if types_hash[type].empty?
              
              type_name = case type
                         when :normal then "Normais"
                         when :mirrored then "Espelhadas"
                         when :scaled then "Escalonadas"
                         when :scaled_mirrored then "Escalonadas_Espelhadas"
                         end
              
              apply_mirror = [:mirrored, :scaled_mirrored].include?(type)
              apply_scale = [:scaled, :scaled_mirrored].include?(type)
              
              puts "🔧 Tipo: #{type_name}"
              
              group = planify_type(
                mod, 
                types_hash[type], 
                type_name, 
                org, 
                layer.name,
                material_info,
                mode,
                settings,
                apply_mirror: apply_mirror, 
                apply_scale: apply_scale
              )
              
              if group
                all_groups << group
                org.x = group.bounds.max.x + material_spacing
              end
            end
          end
          
          # 5. AGRUPA TUDO NO FINAL
          puts "=" * 60
          puts "📦 CRIANDO GRUPO MASTER"
          puts "=" * 60
          
          master_group = nil
          if all_groups.any?
            master_group = mod.entities.add_group(all_groups)
            master_group.name = "Planificação_#{mode}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
            puts "  ✓ Grupo master criado: #{master_group.name}"
            
            # SALVA DADOS DO RELATÓRIO
            save_layout_report_data(master_group, mode, settings, data_by_layer, materials_data, all_instances)
          end
          
          mod.commit_operation
          
          # Seleciona grupo master
          UI.start_timer(0.1, false) do
            mod.selection.clear
            mod.selection.add(master_group) if master_group && master_group.valid?
          end
          
          puts "=" * 60
          puts "✅ PLANIFICAÇÃO CONCLUÍDA!"
          puts "=" * 60
          
          UI.messagebox("✅ Planificação '#{mode}' concluída com sucesso!", MB_OK)
          
        rescue => e
          puts "❌ ERRO: #{e.message}"
          puts e.backtrace.first(10)
          mod.abort_operation
          UI.messagebox("❌ Erro: #{e.message}", MB_OK)
        end
      end
      
      # ========== CONFIGURAÇÃO ==========
      def show_configuration_dialog
        # Carrega configurações salvas
        settings = load_user_settings
        
        prompts = [
          "Modo de arranjo:",
          "Espaçamento entre peças (mm):",
          "Margem da borda (mm):",
          "Espaçamento entre pranchas (mm):",
          "Espaçamento entre materiais (mm):"
        ]
        
        defaults = [
          "Linear",
          settings["part_spacing"].to_s,
          settings["board_margin"].to_s,
          settings["board_spacing"].to_s,
          settings["material_spacing"].to_s
        ]
        
        list = [
          "Linear|Com Veios|Nesting",
          "",
          "",
          "",
          ""
        ]
        
        results = UI.inputbox(prompts, defaults, list, "Configuração de Planificação")
        return nil if results == false
        
        mode = results[0]
        settings = {
          "part_spacing" => results[1].to_f,
          "board_margin" => results[2].to_f,
          "board_spacing" => results[3].to_f,
          "material_spacing" => results[4].to_f
        }
        
        # Salva configurações
        save_user_settings(settings)
        
        {
          mode: mode,
          settings: settings
        }
      end
      
      def load_user_settings
        begin
          if File.exist?(USER_SETTINGS_PATH)
            json_content = File.read(USER_SETTINGS_PATH)
            user_settings = JSON.parse(json_content)
            settings = DEFAULT_SETTINGS.dup
            settings.merge!(user_settings)
            puts "✅ Configurações carregadas de: #{USER_SETTINGS_PATH}"
            return settings
          else
            puts "ℹ️ Usando configurações padrão (arquivo user_settings.json não encontrado)"
          end
        rescue => e
          puts "⚠️ Erro ao carregar configurações: #{e.message}"
        end
        
        DEFAULT_SETTINGS.dup
      end
      
      def save_user_settings(settings)
        begin
          data_dir = File.dirname(USER_SETTINGS_PATH)
          
          # Cria a pasta data se não existir
          Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
          
          File.open(USER_SETTINGS_PATH, 'w') do |file|
            file.write(JSON.pretty_generate(settings))
          end
          
          puts "✅ Configurações salvas em: #{USER_SETTINGS_PATH}"
        rescue => e
          puts "⚠️ Erro ao salvar configurações: #{e.message}"
        end
      end
      
      def load_materials_data
        begin
          puts "🔍 Procurando properties.json em: #{PROPERTIES_JSON_PATH}"
          
          if File.exist?(PROPERTIES_JSON_PATH)
            json_content = File.read(PROPERTIES_JSON_PATH)
            puts "✅ Arquivo properties.json carregado com sucesso!"
            return JSON.parse(json_content)
          else
            puts "⚠️ Arquivo properties.json não encontrado em: #{PROPERTIES_JSON_PATH}"
            return nil
          end
          
        rescue => e
          puts "❌ Erro ao carregar properties.json: #{e.message}"
          puts "   Backtrace: #{e.backtrace.first}"
          nil
        end
      end
      
      def find_material_by_layer(materials_data, layer_name)
        return nil unless materials_data && materials_data["materials"]
        
        material = materials_data["materials"].find { |mat| mat["layer"] == layer_name }
        return material if material
        
        # Tenta com material base (sem acabamento)
        if layer_name.include?(" - ")
          base_layer = layer_name.split(" - ").first
          return materials_data["materials"].find { |mat| mat["layer"] == base_layer }
        end
        
        nil
      end
      
      def setup_layers(model)
        board_layer = model.layers[BOARD_LAYER_NAME]
        unless board_layer
          board_layer = model.layers.add(BOARD_LAYER_NAME)
          board_layer.color = BOARD_COLOR
        end
      end
      
      # ========== EXTRAÇÃO E CLASSIFICAÇÃO ==========
      def extract_makettepro_instances(selection)
        instances = []
        
        find_proc = ->(entities, parent_transform = Geom::Transformation.new) do
          entities.each do |ent|
            begin
              next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
              next unless ent && ent.valid?
              
              current_transform = parent_transform * ent.transformation
              
              if ent.is_a?(Sketchup::ComponentInstance)
                next unless ent.definition && ent.definition.valid?
                
                if ent.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
                  instances << {
                    instance: ent,
                    world_transform: current_transform,
                    layer: ent.layer
                  }
                  puts "    Encontrada: #{ent.definition.name}"
                end
                
                if ent.definition.entities && ent.definition.entities.any?
                  find_proc.call(ent.definition.entities, current_transform)
                end
                
              elsif ent.is_a?(Sketchup::Group)
                if ent.entities && ent.entities.any?
                  find_proc.call(ent.entities, current_transform)
                end
              end
            rescue => e
              # Silencioso
            end
          end
        end
        
        selection.each do |entity|
          begin
            next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            next unless entity && entity.valid?
            
            if entity.is_a?(Sketchup::ComponentInstance)
              next unless entity.definition && entity.definition.valid?
              
              if entity.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
                instances << {
                  instance: entity,
                  world_transform: entity.transformation,
                  layer: entity.layer
                }
                puts "    Encontrada: #{entity.definition.name}"
              end
              
              if entity.definition.entities && entity.definition.entities.any?
                find_proc.call(entity.definition.entities, entity.transformation)
              end
              
            elsif entity.is_a?(Sketchup::Group)
              if entity.entities && entity.entities.any?
                find_proc.call(entity.entities, entity.transformation)
              end
            end
          rescue => e
            puts "  ⚠️ Erro: #{e.message}"
          end
        end
        
        instances
      end
      
      def classify_instances(instances)
        normal = []
        mirrored = []
        scaled = []
        scaled_mirrored = []
        
        instances.each do |data|
          scale_info = analyze_scale(data[:world_transform])
          
          if scale_info[:is_scaled] && scale_info[:is_mirrored]
            scaled_mirrored << data
          elsif scale_info[:is_scaled]
            scaled << data
          elsif scale_info[:is_mirrored]
            mirrored << data
          else
            normal << data
          end
        end
        
        { 
          normal: normal, 
          mirrored: mirrored, 
          scaled: scaled,
          scaled_mirrored: scaled_mirrored
        }
      end
      
      def analyze_scale(transform)
        x_axis = Geom::Vector3d.new(1, 0, 0)
        y_axis = Geom::Vector3d.new(0, 1, 0)
        z_axis = Geom::Vector3d.new(0, 0, 1)

        x_scale = x_axis.transform(transform).length.to_f
        y_scale = y_axis.transform(transform).length.to_f
        z_scale = z_axis.transform(transform).length.to_f

        # ✅ ARREDONDA para 6 casas decimais
        x_scale = x_scale.round(6)
        y_scale = y_scale.round(6)
        z_scale = z_scale.round(6)

        unit = 1.0
        tolerance = 1e-4  # Tolerância realista (0.01%)

        is_scaled = !((x_scale - unit).abs < tolerance &&
                      (y_scale - unit).abs < tolerance &&
                      (z_scale - unit).abs < tolerance)

        determinant = transform.xaxis.cross(transform.yaxis).dot(transform.zaxis)
        is_mirrored = determinant < 0

        { is_scaled: is_scaled, is_mirrored: is_mirrored }
      end
      
      # ========== PLANIFICAÇÃO POR TIPO ==========
      def planify_type(model, instances_data, type_name, start_org, layer_name, material_info, mode, settings, apply_mirror: false, apply_scale: false)
        return nil if instances_data.empty?
        
        # Copia para a RAIZ
        copied_with_info = []
        
        instances_data.each do |data|
          new_instance = model.entities.add_instance(
            data[:instance].definition,
            data[:world_transform]
          )
          # Coloca na Layer 0 imediatamente
          new_instance.layer = model.layers[0]
          
          copied_with_info << {
            instance: new_instance,
            original_transform: data[:world_transform],
            definition: data[:instance].definition
          }
        end
        
        # Planifica (move para origem, rotaciona, etc)
        planified_parts = []
        
        copied_with_info.each do |info|
          ci = info[:instance]
          original_transform = info[:original_transform]
          
          # Extrai escala/espelhamento
          scale_info = extract_scale_and_mirror_from_transform(original_transform)
          
          puts "  #{ci.definition.name} - Escala: #{scale_info[:scale_factor].round(6)} | Espelhado: #{scale_info[:is_mirrored]}"
          
          # PASSO 1: Zera transformação
          ci.transform! ci.transformation.inverse
          
          # PASSO 2: Move para ORIGEM
          bounds = ci.bounds
          offset_to_origin = Geom::Vector3d.new(-bounds.min.x, -bounds.min.y, -bounds.min.z)
          ci.transform! Geom::Transformation.translation(offset_to_origin)
          
          # PASSO 3: Rotaciona se width > height
          bounds = ci.bounds
          if bounds.width > bounds.height
            center = bounds.center
            ci.transform! Geom::Transformation.rotation(center, Z_AXIS, 90.degrees)
          end
          
          # PASSO 4: Deita se depth for maior
          bounds = ci.bounds
          if bounds.depth > bounds.width && bounds.depth > bounds.height
            center = bounds.center
            ci.transform! Geom::Transformation.rotation(center, X_AXIS, 90.degrees)
          end
          
          # PASSO 5: Garante face Z+ para cima
          bounds = ci.bounds
          if bounds.min.z < -0.001
            center = bounds.center
            ci.transform! Geom::Transformation.rotation(center, X_AXIS, 180.degrees)
          end
          
          # PASSO 6: Move para Z=0
          bounds = ci.bounds
          if bounds.min.z.abs > 0.001
            ci.transform! Geom::Transformation.translation([0, 0, -bounds.min.z])
          end
          
          # PASSO 7: REAPLICA ESCALA
          if apply_scale
            # Guarda dimensões originais da definição para validação
            original_bounds = info[:definition].bounds
            original_width = original_bounds.width * scale_info[:scale_x].abs
            original_height = original_bounds.height * scale_info[:scale_y].abs
            original_depth = original_bounds.depth * scale_info[:scale_z].abs

            bounds = ci.bounds
            center = bounds.center

            scale_transform = Geom::Transformation.scaling(
              center,
              scale_info[:scale_x].abs,
              scale_info[:scale_y].abs,
              scale_info[:scale_z].abs
            )

            ci.transform!(scale_transform)

            # ✅ VALIDAÇÃO: Verifica se as dimensões finais estão corretas
            final_bounds = ci.bounds
            tolerance_mm = 0.01.mm  # Tolerância de 0.01mm

            width_diff = (final_bounds.width - original_width).abs
            height_diff = (final_bounds.height - original_height).abs
            depth_diff = (final_bounds.depth - original_depth).abs

            if width_diff > tolerance_mm || height_diff > tolerance_mm || depth_diff > tolerance_mm
              # Calcula fator de correção necessário
              correction_x = original_width / final_bounds.width
              correction_y = original_height / final_bounds.height
              correction_z = original_depth / final_bounds.depth

              # Aplica correção
              correction_transform = Geom::Transformation.scaling(
                final_bounds.center,
                correction_x,
                correction_y,
                correction_z
              )
              ci.transform!(correction_transform)

              puts "    ✓ Escala reaplicada + corrigida (dif: #{(width_diff/1.mm).round(3)}mm)"
            else
              puts "    ✓ Escala reaplicada (precisão OK)"
            end
          end
          
          # PASSO 8: REAPLICA ESPELHAMENTO
          if apply_mirror
            bounds = ci.bounds
            center = bounds.center
            mirror = Geom::Transformation.scaling(center, -1, 1, 1)
            ci.transform!(mirror)
            puts "    ✓ Espelhamento reaplicado"
          end
          
          planified_parts << {
            instance: ci,
            definition: info[:definition],
            original_name: info[:definition].name
          }
        end
        
        # Organiza conforme o MODO escolhido
        puts "=" * 60
        puts "📐 ORGANIZANDO: #{type_name} - Modo: #{mode}"
        puts "=" * 60
        
        layout_objects = case mode
                        when "Linear"
                          arrange_linear(planified_parts, "#{layer_name}_#{type_name}", model, start_org.x, settings)
                        when "Com Veios"
                          arrange_with_grain(planified_parts, material_info, "#{layer_name}_#{type_name}", model, start_org.x, settings)
                        when "Nesting"
                          arrange_nesting(planified_parts, material_info, "#{layer_name}_#{type_name}", model, start_org.x, settings)
                        else
                          arrange_linear(planified_parts, "#{layer_name}_#{type_name}", model, start_org.x, settings)
                        end
        
        puts "  ✓ Todas as peças colocadas na Layer 0"
        
        # Cria grupo final
        if layout_objects.any?
          group = model.entities.add_group(layout_objects)
          group.name = "#{type_name}_#{Time.now.strftime('%H%M%S')}"
          puts "  ✓ Grupo '#{group.name}' criado"
          return group
        end
        
        nil
      end
      
      # ========== MODOS DE ORGANIZAÇÃO ==========
      
      # MODO 1: LINEAR - Em linha reta
      def arrange_linear(planified_parts, layer_name, model, global_x_offset = 0, settings)
        layout_objects = []
        current_x = global_x_offset
        spc = settings["part_spacing"].mm
        
        # Ordena por nome da definição
        parts_sorted = planified_parts.sort_by { |p| p[:definition].name }
        
        parts_sorted.each do |part_data|
          ci = part_data[:instance]
          
          # Garante que está na Layer 0
          ci.layer = model.layers[0]
          
          # Posiciona usando bounding box
          bounds = ci.bounds
          target_position = Geom::Point3d.new(current_x, 0, 0)
          offset = target_position - bounds.min
          ci.transform! Geom::Transformation.translation(offset)
          
          bounds = ci.bounds
          current_x = bounds.max.x + spc
          
          layout_objects << ci
        end
        
        # Adiciona texto do grupo
        board_layer = model.layers[BOARD_LAYER_NAME]
        text_group = model.entities.add_group
        text_3d = text_group.entities.add_3d_text(
          layer_name.sub(/^MU_/, ''), 
          TextAlignLeft, 
          "1CamBam_Stick_1", 
          false, false, 10.mm, 0, 0, false, 0
        )
        text_group.entities.each { |ent| ent.layer = board_layer if ent.respond_to?(:layer=) }
        text_group.transform!(Geom::Transformation.translation([global_x_offset, -50.mm, 0]))
        
        layout_objects << text_group
        layout_objects
      end
      
      # MODO 2: COM VEIOS - Organiza em pranchas respeitando o veio da madeira
      def arrange_with_grain(planified_parts, material_info, layer_name, model, global_x_offset = 0, settings)
        # Se não tem info do material, usa linear
        return arrange_linear(planified_parts, layer_name, model, global_x_offset, settings) unless material_info
        
        board_width = material_info["boardLength"].to_f.mm
        board_length = material_info["boardWidth"].to_f.mm
        margin = settings["board_margin"].mm
        part_spacing = settings["part_spacing"].mm
        
        puts "  Prancha: #{board_width/1.mm}x#{board_length/1.mm}mm"
        
        # Prepara peças (SEM rotação para preservar veios)
        parts_with_dims = []
        parts_that_dont_fit = []
        
        planified_parts.each do |part_data|
          ci = part_data[:instance]
          bounds = ci.bounds
          
          width = bounds.width
          height = bounds.height
          
          # Verifica se cabe na prancha
          if width > board_width - 2*margin || height > board_length - 2*margin
            puts "    ⚠️ Peça #{part_data[:original_name]} não cabe - será linear"
            parts_that_dont_fit << part_data
          else
            parts_with_dims << {
              part_data: part_data,
              width: width,
              height: height,
              can_rotate: false,  # NUNCA rotaciona
              rotated: false,
              final_width: width,
              final_height: height,
              area: width * height
            }
          end
        end
        
        layout_objects = []
        
        # Processa peças que cabem (Com Veios) - ALGORITMO OTIMIZADO
        if parts_with_dims.any?
          # Ordena por área (maiores primeiro)
          parts_with_dims.sort_by! { |item| -item[:area] }
          
          boards = []
          current_board = nil
          
          # Marca peças já colocadas
          placed_items = Set.new
          
          # Loop principal - continua até todas as peças serem colocadas
          while placed_items.size < parts_with_dims.size
            parts_with_dims.each_with_index do |item, index|
              # Pula se já foi colocada
              next if placed_items.include?(index)
              
              placed = false
              
              # Tenta colocar na prancha atual
              if current_board
                placed = try_place_on_board(current_board, item, board_width, board_length, margin, part_spacing)
                
                if placed
                  placed_items.add(index)
                  puts "    ✓ Peça #{index + 1}/#{parts_with_dims.size} colocada na prancha atual"
                  next
                end
              end
              
              # Se não tem prancha atual ou não coube em nenhuma prateleira existente,
              # tenta criar nova prateleira na prancha atual
              if current_board
                # Simula criar nova prateleira
                temp_next_y = if current_board[:shelves].empty?
                                margin
                              else
                                last_shelf = current_board[:shelves].last
                                last_shelf[:y] + last_shelf[:height] + part_spacing
                              end
                
                part_h = item[:final_height] + part_spacing
                
                # Se cabe uma nova prateleira, tenta colocar
                if temp_next_y + part_h <= board_length - margin
                  placed = try_place_on_board(current_board, item, board_width, board_length, margin, part_spacing)
                  
                  if placed
                    placed_items.add(index)
                    puts "    ✓ Peça #{index + 1}/#{parts_with_dims.size} colocada em nova prateleira"
                    next
                  end
                end
              end
              
              # Se chegou aqui, não coube na prancha atual
              # Mas ANTES de criar nova prancha, testa se alguma das PRÓXIMAS peças cabe
              if current_board
                found_smaller = false
                
                parts_with_dims.each_with_index do |smaller_item, smaller_index|
                  # Pula se já foi colocada ou se é a peça atual
                  next if placed_items.include?(smaller_index) || smaller_index == index
                  
                  # Tenta colocar esta peça menor
                  if try_place_on_board(current_board, smaller_item, board_width, board_length, margin, part_spacing)
                    placed_items.add(smaller_index)
                    found_smaller = true
                    puts "    ✓ Peça menor #{smaller_index + 1}/#{parts_with_dims.size} coube no espaço disponível"
                    break  # Encontrou uma, volta ao loop principal
                  end
                end
                
                # Se encontrou uma peça menor que coube, continua o loop
                next if found_smaller
              end
              
              # Nenhuma peça cabe mais na prancha atual - cria nova prancha
              unless placed_items.include?(index)
                current_board = create_new_board(board_width, board_length, margin)
                boards << current_board
                
                placed = try_place_on_board(current_board, item, board_width, board_length, margin, part_spacing)
                
                if placed
                  placed_items.add(index)
                  puts "    ✓ Nova prancha #{boards.size} criada para peça #{index + 1}/#{parts_with_dims.size}"
                end
              end
            end
            
            # Segurança: se não conseguiu colocar nenhuma peça nesta iteração, sai do loop
            break if placed_items.size == 0
          end
          
          board_objects = create_board_groups(boards, layer_name, model, board_width, board_length, global_x_offset, settings)
          layout_objects.concat(board_objects)
          
          puts "  📊 Resumo: #{placed_items.size} peças em #{boards.size} prancha(s)"
        end
        
        # Processa peças que não cabem (Linear)
        if parts_that_dont_fit.any?
          last_x = layout_objects.any? ? layout_objects.map { |obj| obj.bounds.max.x }.max : global_x_offset
          offset_for_linear = last_x + settings["board_spacing"].mm
          
          linear_objects = arrange_linear(parts_that_dont_fit, "#{layer_name}_Grandes", model, offset_for_linear, settings)
          layout_objects.concat(linear_objects)
        end
        
        layout_objects
      end
      
      # MODO 3: NESTING - Organiza em pranchas com rotação para otimizar espaço
      def arrange_nesting(planified_parts, material_info, layer_name, model, global_x_offset = 0, settings)
        # Se não tem info do material, usa linear
        return arrange_linear(planified_parts, layer_name, model, global_x_offset, settings) unless material_info
        
        board_width = material_info["boardLength"].to_f.mm
        board_length = material_info["boardWidth"].to_f.mm
        margin = settings["board_margin"].mm
        part_spacing = settings["part_spacing"].mm
        
        puts "  Prancha: #{board_width/1.mm}x#{board_length/1.mm}mm"
        
        # Prepara peças (COM análise de rotação)
        parts_with_dims = []
        parts_that_dont_fit = []
        
        planified_parts.each do |part_data|
          ci = part_data[:instance]
          bounds = ci.bounds
          
          width = bounds.width
          height = bounds.height
          
          # Verifica se cabe normal ou rotacionado
          fits_normal = width <= board_width - 2*margin && height <= board_length - 2*margin
          fits_rotated = height <= board_width - 2*margin && width <= board_length - 2*margin
          
          if !fits_normal && !fits_rotated
            puts "    ⚠️ Peça #{part_data[:original_name]} não cabe - será linear"
            parts_that_dont_fit << part_data
            next
          end
          
          should_rotate = false
          if !fits_normal && fits_rotated
            should_rotate = true
          elsif fits_normal && fits_rotated
            # Escolhe o que desperdiça menos espaço
            remaining_normal = (board_width - width) * (board_length - height)
            remaining_rotated = (board_width - height) * (board_length - width)
            should_rotate = remaining_rotated > remaining_normal
          end
          
          if should_rotate
            parts_with_dims << {
              part_data: part_data,
              width: width,
              height: height,
              can_rotate: true,
              rotated: true,
              final_width: height,
              final_height: width,
              area: width * height
            }
          else
            parts_with_dims << {
              part_data: part_data,
              width: width,
              height: height,
              can_rotate: false,
              rotated: false,
              final_width: width,
              final_height: height,
              area: width * height
            }
          end
        end
        
        layout_objects = []
        
        # Processa peças que cabem (Nesting) - ALGORITMO OTIMIZADO
        if parts_with_dims.any?
          # Ordena por área (maiores primeiro)
          parts_with_dims.sort_by! { |item| -item[:area] }
          
          boards = []
          current_board = nil
          
          # Marca peças já colocadas
          placed_items = Set.new
          
          # Loop principal - continua até todas as peças serem colocadas
          while placed_items.size < parts_with_dims.size
            parts_with_dims.each_with_index do |item, index|
              # Pula se já foi colocada
              next if placed_items.include?(index)
              
              placed = false
              
              # Tenta colocar na prancha atual
              if current_board
                placed = try_place_on_board(current_board, item, board_width, board_length, margin, part_spacing)
                
                if placed
                  placed_items.add(index)
                  puts "    ✓ Peça #{index + 1}/#{parts_with_dims.size} colocada na prancha atual"
                  next
                end
              end
              
              # Se não tem prancha atual ou não coube em nenhuma prateleira existente,
              # tenta criar nova prateleira na prancha atual
              if current_board
                # Simula criar nova prateleira
                temp_next_y = if current_board[:shelves].empty?
                                margin
                              else
                                last_shelf = current_board[:shelves].last
                                last_shelf[:y] + last_shelf[:height] + part_spacing
                              end
                
                part_h = item[:final_height] + part_spacing
                
                # Se cabe uma nova prateleira, tenta colocar
                if temp_next_y + part_h <= board_length - margin
                  placed = try_place_on_board(current_board, item, board_width, board_length, margin, part_spacing)
                  
                  if placed
                    placed_items.add(index)
                    puts "    ✓ Peça #{index + 1}/#{parts_with_dims.size} colocada em nova prateleira"
                    next
                  end
                end
              end
              
              # Se chegou aqui, não coube na prancha atual
              # Mas ANTES de criar nova prancha, testa se alguma das PRÓXIMAS peças cabe
              if current_board
                found_smaller = false
                
                parts_with_dims.each_with_index do |smaller_item, smaller_index|
                  # Pula se já foi colocada ou se é a peça atual
                  next if placed_items.include?(smaller_index) || smaller_index == index
                  
                  # Tenta colocar esta peça menor
                  if try_place_on_board(current_board, smaller_item, board_width, board_length, margin, part_spacing)
                    placed_items.add(smaller_index)
                    found_smaller = true
                    puts "    ✓ Peça menor #{smaller_index + 1}/#{parts_with_dims.size} coube no espaço disponível"
                    break  # Encontrou uma, volta ao loop principal
                  end
                end
                
                # Se encontrou uma peça menor que coube, continua o loop
                next if found_smaller
              end
              
              # Nenhuma peça cabe mais na prancha atual - cria nova prancha
              unless placed_items.include?(index)
                current_board = create_new_board(board_width, board_length, margin)
                boards << current_board
                
                placed = try_place_on_board(current_board, item, board_width, board_length, margin, part_spacing)
                
                if placed
                  placed_items.add(index)
                  puts "    ✓ Nova prancha #{boards.size} criada para peça #{index + 1}/#{parts_with_dims.size}"
                end
              end
            end
            
            # Segurança: se não conseguiu colocar nenhuma peça nesta iteração, sai do loop
            break if placed_items.size == 0
          end
          
          board_objects = create_board_groups(boards, layer_name, model, board_width, board_length, global_x_offset, settings)
          layout_objects.concat(board_objects)
          
          puts "  📊 Resumo: #{placed_items.size} peças em #{boards.size} prancha(s)"
        end
        
        # Processa peças que não cabem (Linear)
        if parts_that_dont_fit.any?
          last_x = layout_objects.any? ? layout_objects.map { |obj| obj.bounds.max.x }.max : global_x_offset
          offset_for_linear = last_x + settings["board_spacing"].mm
          
          linear_objects = arrange_linear(parts_that_dont_fit, "#{layer_name}_Grandes", model, offset_for_linear, settings)
          layout_objects.concat(linear_objects)
        end
        
        layout_objects
      end
      
      # ========== FUNÇÕES AUXILIARES PARA PRANCHAS ==========
      
      def try_place_on_board(board, item, board_width, board_length, margin, spacing)
        shelves = board[:shelves]
        part_w = item[:final_width] + spacing
        part_h = item[:final_height] + spacing
        
        # Tenta colocar em prateleira existente
        shelves.each do |shelf|
          if shelf[:current_x] + part_w <= board_width - margin && shelf[:height] >= part_h
            item[:x] = shelf[:current_x] + spacing/2
            item[:y] = shelf[:y] + spacing/2
            item[:board] = board
            
            shelf[:current_x] += part_w
            shelf[:parts] << item
            
            return true
          end
        end
        
        # Tenta criar nova prateleira
        next_y = shelves.empty? ? margin : shelves.last[:y] + shelves.last[:height] + spacing
        
        if next_y + part_h <= board_length - margin
          new_shelf = {
            y: next_y,
            height: part_h,
            current_x: margin + part_w,
            parts: [item]
          }
          
          item[:x] = margin + spacing/2
          item[:y] = next_y + spacing/2
          item[:board] = board
          
          shelves << new_shelf
          return true
        end
        
        false
      end
      
      def create_new_board(board_width, board_length, margin)
        {
          width: board_width,
          length: board_length,
          shelves: [],
          parts: []
        }
      end
      
      def create_board_groups(boards, layer_name, model, board_width, board_length, global_x_offset, settings)
        layout_objects = []
        board_spacing = settings["board_spacing"].mm
        current_x = global_x_offset
        
        board_layer = model.layers[BOARD_LAYER_NAME]
        
        boards.each_with_index do |board, board_index|
          board_group = model.entities.add_group
          board_group.name = "#{layer_name.sub(/^MU_/, '')} - Prancha #{board_index + 1}"
          
          # Desenha contorno da prancha
          pts = [
            [0, 0, 0],
            [board_width, 0, 0],
            [board_width, board_length, 0],
            [0, board_length, 0]
          ]
          
          board_outline = board_group.entities.add_face(pts)
          board_outline.layer = board_layer
          board_outline.edges.each { |edge| edge.layer = board_layer }
          
          # Material cinza para prancha
          materials = model.materials
          board_material = materials["Prancha_Cinza"]
          unless board_material
            board_material = materials.add("Prancha_Cinza")
            board_material.color = [200, 200, 200]
            board_material.alpha = 0.3
          end
          
          board_outline.material = board_material
          board_outline.back_material = board_material
          
          # Adiciona as peças
          board[:shelves].each do |shelf|
            shelf[:parts].each do |item|
              part_data = item[:part_data]
              ci = part_data[:instance]
              
              # Rotaciona se necessário
              if item[:rotated]
                bounds = ci.bounds
                rot = Geom::Transformation.rotation(bounds.center, [0,0,1], 90.degrees)
                ci.transform!(rot)
              end
              
              # Posiciona
              bounds = ci.bounds
              move_vector = Geom::Vector3d.new(
                item[:x] - bounds.min.x,
                item[:y] - bounds.min.y,
                0.1.mm - bounds.min.z
              )
              ci.transform!(Geom::Transformation.translation(move_vector))
              
              # Adiciona instância no grupo da prancha e garante Layer 0
              new_instance = board_group.entities.add_instance(ci.definition, ci.transformation)
              new_instance.layer = model.layers[0]
              
              ci.erase!
            end
          end
          
          # Adiciona texto
          text_group = model.entities.add_group
          text_3d = text_group.entities.add_3d_text(
            board_group.name, 
            TextAlignCenter, 
            "1CamBam_Stick_1", 
            false, false, 30.mm, 0, 0, false, 0
          )
          text_group.entities.each { |ent| ent.layer = board_layer if ent.respond_to?(:layer=) }
          text_group.transform!(Geom::Transformation.translation([0, -80.mm, 0]))
          
          # Agrupa prancha + texto
          board_with_text = model.entities.add_group([board_group, text_group])
          board_with_text.name = board_group.name
          board_with_text.transform!(Geom::Transformation.translation([current_x, 0, 0]))
          
          current_x += board_width + board_spacing
          layout_objects << board_with_text
        end
        
        # Se múltiplas pranchas, cria grupo master
        if layout_objects.length > 1
          material_master = model.entities.add_group(layout_objects)
          material_master.name = "#{layer_name.sub(/^MU_/, '')} - #{layout_objects.length} Pranchas"
          return [material_master]
        end
        
        layout_objects
      end
      
      # ========== EXTRAÇÃO DE ESCALA ==========
      
      def extract_scale_and_mirror_from_transform(transform)
        x_axis = Geom::Vector3d.new(1, 0, 0)
        y_axis = Geom::Vector3d.new(0, 1, 0)
        z_axis = Geom::Vector3d.new(0, 0, 1)

        x_scale = x_axis.transform(transform).length.to_f
        y_scale = y_axis.transform(transform).length.to_f
        z_scale = z_axis.transform(transform).length.to_f

        # ✅ ARREDONDA para 6 casas decimais para evitar acúmulo de erros
        x_scale = x_scale.round(6)
        y_scale = y_scale.round(6)
        z_scale = z_scale.round(6)

        unit = 1.0
        tolerance = 1e-4  # Tolerância mais realista (0.01%)

        is_scaled = !((x_scale - unit).abs < tolerance &&
                      (y_scale - unit).abs < tolerance &&
                      (z_scale - unit).abs < tolerance)

        determinant = transform.xaxis.cross(transform.yaxis).dot(transform.zaxis)
        is_mirrored = determinant < 0

        scale_factor = [x_scale, y_scale, z_scale].max

        {
          is_scaled: is_scaled,
          is_mirrored: is_mirrored,
          scale_factor: scale_factor,
          scale_x: x_scale,
          scale_y: y_scale,
          scale_z: z_scale
        }
      end
      
      # ========== VERIFICAÇÃO DE COLISÕES ==========
      
      def check_collisions_in_selection(selection)
        return { has_collisions: false, collision_pairs: [], all_instances: [] } if selection.empty?
        
        model = Sketchup.active_model
        
        # Encontra todas as instâncias MakettePro na seleção
        selected_instances_data = []
        
        find_proc = ->(entities_collection, parent_transform = Geom::Transformation.new) do
          entities_collection.each do |ent|
            next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
            next unless ent.valid?
            
            current_transform = parent_transform * ent.transformation
            if ent.is_a?(Sketchup::ComponentInstance)
              next unless ent.definition && ent.definition.valid?
              
              if ent.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
                selected_instances_data << { 
                  instance: ent, 
                  transformation: current_transform
                }
              end
            end
            
            if ent.respond_to?(:definition) && ent.definition && ent.definition.valid?
              find_proc.call(ent.definition.entities, current_transform)
            elsif ent.respond_to?(:entities)
              find_proc.call(ent.entities, current_transform)
            end
          end
        end
        
        begin
          find_proc.call(selection)
        rescue => e
          puts "⚠️ Erro ao buscar instâncias selecionadas: #{e.message}"
          return { has_collisions: false, collision_pairs: [], all_instances: [] }
        end
        
        # Encontra TODAS as instâncias MakettePro do modelo
        all_model_instances_data = []
        find_proc_model = ->(entities_collection, parent_transform = Geom::Transformation.new) do
          entities_collection.each do |ent|
            next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
            next unless ent.valid?
            
            current_transform = parent_transform * ent.transformation
            if ent.is_a?(Sketchup::ComponentInstance)
              next unless ent.definition && ent.definition.valid?
              
              if ent.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
                all_model_instances_data << { 
                  instance: ent, 
                  transformation: current_transform
                }
              end
            end
            
            if ent.respond_to?(:definition) && ent.definition && ent.definition.valid?
              find_proc_model.call(ent.definition.entities, current_transform)
            elsif ent.respond_to?(:entities)
              find_proc_model.call(ent.entities, current_transform)
            end
          end
        end
        
        begin
          find_proc_model.call(model.active_entities)
        rescue => e
          puts "⚠️ Erro ao buscar instâncias do modelo: #{e.message}"
        end
        
        return { has_collisions: false, collision_pairs: [], all_instances: selected_instances_data } if selected_instances_data.empty?
        
        collision_pairs = []
        selected_pids = Set.new(selected_instances_data.map { |data| data[:instance].persistent_id })
        
        puts "🔍 Verificando colisões entre #{selected_instances_data.length} peças selecionadas e #{all_model_instances_data.length} peças totais..."
        
        # 1. Verifica colisões ENTRE peças selecionadas
        if selected_instances_data.length > 1
          selected_instances_data.combination(2) do |data1, data2|
            inst1 = data1[:instance]
            inst2 = data2[:instance]
            transform1 = data1[:transformation]
            transform2 = data2[:transformation]
            
            next unless inst1 && inst2 && inst1.valid? && inst2.valid?
            
            # Teste de bounding box
            bb1_world = transform_bounding_box(inst1.definition.bounds, transform1)
            bb2_world = transform_bounding_box(inst2.definition.bounds, transform2)
            
            if bb1_world.intersect(bb2_world).valid?
              if solids_intersect?(inst1, transform1, inst2, transform2)
                collision_pairs << {
                  pid1: inst1.persistent_id,
                  pid2: inst2.persistent_id,
                  name1: inst1.definition.name,
                  name2: inst2.definition.name,
                  collision_type: "interna"
                }
              end
            end
          end
        end
        
        # 2. Verifica colisões com o resto do modelo
        selected_instances_data.each do |selected_data|
          all_model_instances_data.each do |model_data|
            next if selected_data[:instance].persistent_id == model_data[:instance].persistent_id
            next if selected_pids.include?(model_data[:instance].persistent_id)
            
            inst1 = selected_data[:instance]
            inst2 = model_data[:instance]
            transform1 = selected_data[:transformation]
            transform2 = model_data[:transformation]
            
            next unless inst1 && inst2 && inst1.valid? && inst2.valid?
            
            bb1_world = transform_bounding_box(inst1.definition.bounds, transform1)
            bb2_world = transform_bounding_box(inst2.definition.bounds, transform2)
            
            if bb1_world.intersect(bb2_world).valid?
              if solids_intersect?(inst1, transform1, inst2, transform2)
                collision_pairs << {
                  pid1: inst1.persistent_id,
                  pid2: inst2.persistent_id,
                  name1: inst1.definition.name,
                  name2: inst2.definition.name,
                  collision_type: "externa"
                }
              end
            end
          end
        end
        
        {
          has_collisions: collision_pairs.any?,
          collision_pairs: collision_pairs,
          all_instances: selected_instances_data
        }
      end
      
      def get_colliding_instances(collision_pairs, all_instances)
        model = Sketchup.active_model
        
        colliding_pids = Set.new
        collision_pairs.each do |pair|
          colliding_pids << pair[:pid1]
          colliding_pids << pair[:pid2]
        end
        
        colliding_instances = all_instances.select do |instance_data|
          colliding_pids.include?(instance_data[:instance].persistent_id)
        end
        
        selected_pids = Set.new(all_instances.map { |data| data[:instance].persistent_id })
        
        collision_pairs.each do |pair|
          if pair[:collision_type] == "externa"
            [pair[:pid1], pair[:pid2]].each do |pid|
              unless selected_pids.include?(pid)
                external_instance = model.find_entity_by_persistent_id(pid)
                if external_instance && external_instance.valid?
                  unless colliding_instances.any? { |data| data[:instance].persistent_id == pid }
                    colliding_instances << {
                      instance: external_instance,
                      transformation: external_instance.transformation
                    }
                  end
                end
              end
            end
          end
        end
        
        colliding_instances
      end
      
      def open_collision_analyzer_with_selection(instances_data)
        begin
          if defined?(Rjv::MockupTools::CollisionAnalyzer)
            pids = instances_data.map { |data| data[:instance].persistent_id }
            
            Rjv::MockupTools::CollisionAnalyzer.open_dialog
            
            UI.start_timer(1.0, false) do
              Rjv::MockupTools::CollisionAnalyzer.send(:enter_focus_mode, pids)
            end
          else
            UI.messagebox("Analisador de colisões não disponível. Verifique se o módulo CollisionAnalyzer está carregado.")
          end
        rescue => e
          puts "Erro ao abrir analisador de colisões: #{e.message}"
          UI.messagebox("Erro ao abrir analisador de colisões: #{e.message}")
        end
      end
      
      def transform_bounding_box(local_bb, world_transform)
        world_bb = Geom::BoundingBox.new
        (0..7).each { |i| world_bb.add(local_bb.corner(i).transform(world_transform)) }
        world_bb
      end
      
      def solids_intersect?(instance1, transform1, instance2, transform2)
        model = Sketchup.active_model
        collision_found = false
        temp_entities_to_erase = []
        
        begin
          model.start_operation("CollisionTest", true, false, true)
          
          ents = model.active_entities
          temp_group1 = create_merged_solid_group(ents, instance1, transform1)
          temp_group2 = create_merged_solid_group(ents, instance2, transform2)
          
          unless temp_group1 && temp_group2
            return false
          end
          
          temp_entities_to_erase.concat([temp_group1, temp_group2].compact)
          
          result_group = temp_group1.intersect(temp_group2)
          temp_entities_to_erase << result_group if result_group.is_a?(Sketchup::Entity)
          
          collision_found = result_group.is_a?(Sketchup::Group) && result_group.entities.length > 0
          
        rescue => e
          collision_found = false
          
        ensure
          begin
            valid_temps = temp_entities_to_erase.select { |e| e && e.valid? }
            ents.erase_entities(valid_temps) if valid_temps.any?
          rescue => cleanup_error
            # Silencioso
          end
          
          begin
            model.commit_operation
          rescue => op_error
            begin
              model.abort_operation
            rescue
              # Silencioso
            end
          end
        end
        
        collision_found
      end
      
      def create_merged_solid_group(entities_context, instance, transform)
        return nil unless instance && instance.valid?
        return nil unless instance.definition && instance.definition.valid?
        
        novo_grupo = entities_context.add_group
        faces_para_copiar = instance.definition.entities.grep(Sketchup::Face)
        return nil if faces_para_copiar.empty?
        
        begin
          faces_para_copiar.each do |face|
            next unless face && face.valid?
            
            new_face = novo_grupo.entities.add_face(face.outer_loop.vertices.map(&:position))
            if face.loops.length > 1
              face.loops.drop(1).each do |loop|
                hole_face = novo_grupo.entities.add_face(loop.vertices.map(&:position))
                hole_face.erase! if hole_face && hole_face.valid?
              end
            end
          end
          
          edges_to_erase = novo_grupo.entities.grep(Sketchup::Edge).select { |e| e.faces.length == 2 && e.faces[0].normal.parallel?(e.faces[1].normal) }
          novo_grupo.entities.erase_entities(edges_to_erase) if edges_to_erase.any?
          novo_grupo.transformation = transform
          
        rescue => e
          novo_grupo.erase! if novo_grupo && novo_grupo.valid?
          return nil
        end
        
        novo_grupo
      end
      
      # ========== GERAÇÃO DE RELATÓRIOS ==========
      
      def save_layout_report_data(master_group, mode, settings, data_by_layer, materials_data, all_instances)
        materials_info = []
        total_parts = 0
        total_boards = 0
        total_area_used = 0.0
        total_area_boards = 0.0
        
        data_by_layer.each do |layer, types_hash|
          next unless layer
          
          material_info = find_material_by_layer(materials_data, layer.name)
          
          # Conta todas as peças deste material
          parts_count = 0
          [:normal, :mirrored, :scaled, :scaled_mirrored].each do |type|
            parts_count += types_hash[type].length
          end
          
          # Conta pranchas
          boards_count = count_boards_from_layout(master_group, material_info, layer.name)
          
          area_used = 0.0
          area_total = 0.0
          
          if material_info
            board_length = material_info["boardLength"]&.to_f || 0.0
            board_width = material_info["boardWidth"]&.to_f || 0.0
            
            if board_length > 0 && board_width > 0
              board_area = (board_length * board_width) / 1_000_000.0  # m²
              area_total = board_area * boards_count
              
              # Calcula área usada pelas peças (com escala aplicada)
              [:normal, :mirrored, :scaled, :scaled_mirrored].each do |type|
                types_hash[type].each do |data|
                  begin
                    original_def = data[:instance]&.definition
                    next unless original_def && original_def.valid?

                    face_area_mm2 = calculate_top_faces_area(original_def)

                    # ✅ APLICA ESCALA NA ÁREA
                    transform_info = extract_scale_and_mirror_from_transform(data[:world_transform])
                    real_area_mm2 = face_area_mm2 * transform_info[:scale_x].abs * transform_info[:scale_y].abs

                    area_used += (real_area_mm2 || 0.0) / 1_000_000.0
                  rescue => e
                    # Silencioso
                  end
                end
              end
            end
          end
          
          efficiency = (area_total > 0 && area_used > 0) ? (area_used / area_total * 100).round(1) : 0.0
          
          material_data = {
            "layer_name" => layer.name,
            "material_name" => material_info ? material_info["name"] : layer.name,
            "thickness" => material_info ? material_info["thickness"] : "N/A",
            "board_dimensions" => material_info ? "#{material_info['boardLength']}x#{material_info['boardWidth']}mm" : "N/A",
            "parts_count" => parts_count,
            "boards_count" => boards_count,
            "area_used_m2" => area_used.round(3),
            "area_total_m2" => area_total.round(3),
            "efficiency_percent" => efficiency,
            "parts_list" => []
          }
          
          # Agrupa peças por nome e transformação
          parts_by_name = {}

          [:normal, :mirrored, :scaled, :scaled_mirrored].each do |type|
            types_hash[type].each do |data|
              begin
                original_def = data[:instance]&.definition
                next unless original_def && original_def.valid?

                bounds = original_def.bounds
                next unless bounds&.valid?

                face_area_mm2 = calculate_top_faces_area(original_def) || 0.0

                # ✅ EXTRAI ESCALA COMPLETA DA TRANSFORMAÇÃO
                transform_info = extract_scale_and_mirror_from_transform(data[:world_transform])

                # ✅ CALCULA DIMENSÕES REAIS (com escala aplicada)
                real_width = bounds.width * transform_info[:scale_x].abs
                real_height = bounds.height * transform_info[:scale_y].abs
                real_depth = bounds.depth * transform_info[:scale_z].abs
                real_area_mm2 = face_area_mm2 * transform_info[:scale_x].abs * transform_info[:scale_y].abs

                grouping_key = "#{original_def.name}_#{type}"

                if parts_by_name[grouping_key]
                  parts_by_name[grouping_key]["quantity"] += 1
                else
                  # Monta string de transformação legível
                  transformation_label = case type
                    when :normal then "Normal"
                    when :mirrored then "Espelhada"
                    when :scaled then "Escalonada #{transform_info[:scale_factor].round(3)}x"
                    when :scaled_mirrored then "Escalonada #{transform_info[:scale_factor].round(3)}x + Espelhada"
                  end

                  piece_data = {
                    "name" => original_def.name,
                    "dimensions_original" => "#{(bounds.width/1.mm).round(1)}x#{(bounds.height/1.mm).round(1)}x#{(bounds.depth/1.mm).round(1)}mm",
                    "dimensions_real" => "#{(real_width/1.mm).round(1)}x#{(real_height/1.mm).round(1)}x#{(real_depth/1.mm).round(1)}mm",
                    "area_mm2" => real_area_mm2.round(2),
                    "quantity" => 1,
                    "is_mirrored" => transform_info[:is_mirrored],
                    "is_scaled" => transform_info[:is_scaled],
                    "scale_factor" => transform_info[:scale_factor].round(6),
                    "scale_xyz" => "#{transform_info[:scale_x].round(3)}, #{transform_info[:scale_y].round(3)}, #{transform_info[:scale_z].round(3)}",
                    "transformation_type" => type.to_s,
                    "transformation_label" => transformation_label
                  }

                  parts_by_name[grouping_key] = piece_data
                end
              rescue => e
                # Silencioso
              end
            end
          end
          
          material_data["parts_list"] = parts_by_name.values
          
          materials_info << material_data
          
          total_parts += parts_count
          total_boards += boards_count
          total_area_used += area_used
          total_area_boards += area_total
        end
        
        overall_efficiency = (total_area_boards > 0 && total_area_used > 0) ? (total_area_used / total_area_boards * 100).round(1) : 0.0
        
        report_data = {
          "generated_at" => Time.now.strftime("%d/%m/%Y %H:%M:%S"),
          "layout_mode" => mode,
          "settings" => settings,
          "summary" => {
            "total_materials" => materials_info.length,
            "total_parts" => total_parts,
            "total_boards" => total_boards,
            "total_area_used_m2" => total_area_used.round(3),
            "total_area_boards_m2" => total_area_boards.round(3),
            "overall_efficiency_percent" => overall_efficiency
          },
          "materials" => materials_info
        }
        
        begin
          master_group.set_attribute("RJV_Report", "data", JSON.generate(report_data))
          master_group.set_attribute("RJV_Report", "version", "2.0")
          
          puts "✅ Relatório salvo no grupo master"
          puts "   Total: #{total_parts} peças, #{total_boards} pranchas, #{overall_efficiency}% eficiência"
          
        rescue => e
          puts "❌ Erro ao salvar relatório: #{e.message}"
        end
      end
      
      def count_boards_from_layout(master_group, material_info, layer_name)
        return 1 unless master_group && master_group.valid?

        material_name = material_info ? material_info["name"] : layer_name.gsub(/^MU_/, '')
        boards_count = 0

        # ✅ CONTA RETÂNGULOS DA PRANCHA (faces na layer RJV_Board)
        model = Sketchup.active_model
        board_layer = model.layers[BOARD_LAYER_NAME]

        if board_layer
          # Busca recursivamente por faces na layer de prancha dentro do master_group
          find_board_faces = ->(entities) do
            entities.each do |entity|
              if entity.is_a?(Sketchup::Face) && entity.layer == board_layer
                # Verifica se é uma face grande o suficiente para ser prancha (não texto)
                area_mm2 = entity.area * 645.16  # Conversão in² → mm²
                if area_mm2 > 10000  # Maior que 100x100mm (filtra textos 3D)
                  boards_count += 1
                end
              elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                if entity.respond_to?(:entities) && entity.entities
                  find_board_faces.call(entity.entities)
                elsif entity.respond_to?(:definition) && entity.definition && entity.definition.entities
                  find_board_faces.call(entity.definition.entities)
                end
              end
            end
          end

          find_board_faces.call(master_group.entities)
        end

        # Se não encontrou pranchas pela layer, usa o método antigo (fallback)
        if boards_count == 0
          master_group.entities.grep(Sketchup::Group).each do |group|
            next unless group && group.valid?

            group_name = group.name
            next unless group_name

            if group_name.include?(material_name)
              if group_name.match(/Prancha\s+\d+/i)
                boards_count += 1
              elsif group_name.match(/(\d+)\s+Pranchas/i)
                match = group_name.match(/(\d+)\s+Pranchas/i)
                count = match[1].to_i
                boards_count += count
              end
            end
          end
        end

        boards_count > 0 ? boards_count : 1
      end
      
      def calculate_top_faces_area(definition)
        return 0.0 unless definition && definition.valid?
        
        total_area_mm2 = 0.0
        
        begin
          definition.entities.grep(Sketchup::Face).each do |face|
            next unless face&.valid?
            
            normal = face.normal
            next unless normal
            
            if normal.z > 0.7
              face_area = face.area || 0.0
              area_mm2 = face_area * 645.16  # Conversão de in² para mm²
              total_area_mm2 += area_mm2
            end
          end
        rescue => e
          return 0.0
        end
        
        total_area_mm2.round(2)
      end
      
    end
  end
end