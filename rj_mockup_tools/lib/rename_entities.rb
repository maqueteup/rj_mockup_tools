# encoding: UTF-8
# Mockup Tools RJV - Rename Entities Tool Module (Versão Melhorada)

require 'sketchup.rb'
require 'set'

module Rjv
  module MockupTools
    module RenameEntities

      # --- Constantes ---
      TOLERANCE = 1e-4
      X_AXIS = Geom::Vector3d.new(1, 0, 0).freeze
      Y_AXIS = Geom::Vector3d.new(0, 1, 0).freeze
      Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze
      ORIGIN = Geom::Point3d.new(0, 0, 0).freeze

      # --- Estado ---
      @last_bulk_settings = {
          prefix: "Comp_",
          suffix: "",
          seqType: "N",
          startValue: 1,
          increment: 1,
          sortMethod: "C",
          nameMode: "R", # R=Replace, K=Keep+Prefix/Suffix, F=Find/Replace
          findText: "",
          replaceText: "",
          keepCase: true,
          addLayer: false,
          layerName: "",
          addAttributes: false,
          attributeKey: "Description",
          attributeValue: ""
      }.freeze

      # --- Getter para Configurações ---
      def self.get_last_bulk_settings
        unless defined?(@last_bulk_settings)
            @last_bulk_settings = { 
                prefix: "Comp_", 
                suffix: "", 
                seqType: "N", 
                startValue: 1, 
                increment: 1, 
                sortMethod: "C",
                nameMode: "R",
                findText: "",
                replaceText: "",
                keepCase: true,
                addLayer: false,
                layerName: "",
                addAttributes: false,
                attributeKey: "Description",
                attributeValue: ""
            }.freeze
        end
        return @last_bulk_settings.dup
      end

      # --- run ---
      def self.run
        model = Sketchup.active_model
        selection = model.selection.to_a
        valid_entities = selection.select do |e|
          e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        end
        if valid_entities.empty?
          UI.messagebox("Nenhum Grupo/Comp. selecionado.")
          return
        end
        if valid_entities.length == 1
          rename_single(valid_entities.first, model)
        else
          # Passa a seleção inicial diretamente
          show_bulk_rename_dialog(valid_entities, model)
        end
      end

      # --- rename_single ---
      private_class_method def self.rename_single(entity, model)
        target_object = entity
        is_definition = false
        current_name = entity.name || ""
        prompt_text = "Novo nome Grupo '#{current_name || '(S/N)'}':"
        if entity.is_a?(Sketchup::ComponentInstance)
          target_object = entity.definition
          is_definition = true
          current_name = target_object.name || ""
          prompt_text = "Novo nome Definição '#{current_name || '(S/N)'}':"
        end
        prompts = [prompt_text]
        defaults = [current_name]
        input = UI.inputbox(prompts, defaults, "Renomear")
        return unless input
        new_name = input[0].strip
        if new_name == current_name
          Sketchup.status_text = "Nome não alterado."
          return
        end
        if is_definition && model.definitions[new_name]
          UI.messagebox("Definição '#{new_name}' já existe.")
          return
        end
        op_name = is_definition ? "Renomear Definição" : "Renomear Grupo"
        model.start_operation(op_name, true)
        begin
          if target_object.valid?
            target_object.name = new_name
            model.commit_operation
            Sketchup.status_text = "#{op_name.split.last} '#{new_name}'."
          else
            model.abort_operation
            UI.messagebox("Objeto inválido.")
          end
        rescue => e
          model.abort_operation
          UI.messagebox("Erro: #{e.message}")
          puts e.backtrace.join("\n")
        end
      end

      # --- show_bulk_rename_dialog ---
      private_class_method def self.show_bulk_rename_dialog(initial_selection, model)
          dialog = UI::HtmlDialog.new(
              dialog_title: "Renomear Defs/Grupos",
              preferences_key: "RjvMockupToolsRenameBulk",
              scrollable: true, resizable: true,
              width: 480, height: 680,
              style: UI::HtmlDialog::STYLE_DIALOG
          )
          html_path = File.join(__dir__, '..', 'html', 'rename_dialog.html')
          dialog.set_file(html_path)

          dialog.add_action_callback("request_initial_data") do |action_context|
              settings_to_send = get_last_bulk_settings # Usa o getter
              settings_to_send[:startValue] = settings_to_send[:startValue].to_s # String para JS
              dialog.execute_script("initializeDialog(#{initial_selection.length}, #{settings_to_send.to_json});")
          end

          dialog.add_action_callback("save_settings") do |action_context, settings|
               prefix = settings["prefix"] || ""
               suffix = settings["suffix"] || ""
               seq_type = (settings["seqType"] == "A") ? "A" : "N"
               sv_raw = settings["startValue"]
               sort_method = settings["sortMethod"] || "C" # Default C
               inc = settings["increment"].to_i; inc = 1 if inc < 1
               name_mode = settings["nameMode"] || "R"
               find_text = settings["findText"] || ""
               replace_text = settings["replaceText"] || ""
               keep_case = settings["keepCase"] == true
               add_layer = settings["addLayer"] == true
               layer_name = settings["layerName"] || ""
               add_attributes = settings["addAttributes"] == true
               attribute_key = settings["attributeKey"] || "Description"
               attribute_value = settings["attributeValue"] || ""
               
               sv = nil
               if seq_type == "N"; begin; sv = Integer(sv_raw); rescue; sv = 1; end
               else; sv = sv_raw.to_s.strip.upcase; if sv.empty? || !sv.match?(/^[A-Z]+$/); sv = "A"; end; end

               @last_bulk_settings = {
                   prefix: prefix, 
                   suffix: suffix, 
                   seqType: seq_type, 
                   startValue: sv, 
                   increment: inc, 
                   sortMethod: sort_method,
                   nameMode: name_mode,
                   findText: find_text,
                   replaceText: replace_text,
                   keepCase: keep_case,
                   addLayer: add_layer,
                   layerName: layer_name,
                   addAttributes: add_attributes,
                   attributeKey: attribute_key,
                   attributeValue: attribute_value
               }.freeze

               dialog.close
               execute_bulk_rename(initial_selection, model, @last_bulk_settings)
          end

          dialog.add_action_callback("cancel") do |action_context|
              dialog.close
          end
          dialog.center; dialog.show
          UI.start_timer(0.1, false) { dialog.execute_script("request_initial_data();") }
      end # Fim show_bulk_rename_dialog

      # --- Executa renomeação em lote ---
      private_class_method def self.execute_bulk_rename(entities_to_rename, model, settings)
          is_numeric = (settings[:seqType] == "N")
          ordered_items = []
          skipped_reasons = Hash.new(0)

          # Extrai configurações
          prefix = settings[:prefix]
          suffix = settings[:suffix]
          name_mode = settings[:nameMode]
          find_text = settings[:findText]
          replace_text = settings[:replaceText]
          keep_case = settings[:keepCase]
          add_layer = settings[:addLayer]
          layer_name = settings[:layerName]
          add_attributes = settings[:addAttributes]
          attribute_key = settings[:attributeKey]
          attribute_value = settings[:attributeValue]
          
          # Preparar layer se necessário
          target_layer = nil
          if add_layer && !layer_name.empty?
            target_layer = get_or_create_layer(layer_name, model)
            if target_layer.nil?
              UI.messagebox("Não foi possível criar/obter a layer '#{layer_name}'")
              add_layer = false
            end
          end

          # Agrupa e Ordena
          definitions_to_rename = {}; groups_to_rename = []
          entities_to_rename.each do |entity|
              next unless entity.valid?
              if entity.is_a?(Sketchup::ComponentInstance); definitions_to_rename[entity.definition] ||= entity;
              elsif entity.is_a?(Sketchup::Group); groups_to_rename << entity; end
          end
          items_to_sort = groups_to_rename + definitions_to_rename.values
          begin
              ordered_items = sort_entities(items_to_sort, settings[:sortMethod], model)
              raise "Falha na ordenação (retornou nil)" if ordered_items.nil?
          rescue => e; UI.messagebox("Erro na ordenação: #{e.message}"); puts e.backtrace.first(5); return; end

          # Renomeação
          model.start_operation("Renomear Lote", true)
          current_value = settings[:startValue]; pc = 0; sc = 0 # pc=processed, sc=skipped
          existing_def_names = model.definitions.map(&:name); rdb = Set.new # rdb=renamed defs batch

          ordered_items.each do |item|
             target_object = item
             is_component = item.is_a?(Sketchup::ComponentInstance)
             isd = false  # isd = is_definition
             
             # Verificar se é definição de componente
             if is_component
               target_object = item.definition
               isd = true
             end
             
             cn = target_object.name || ""  # Nome atual
             
             # Pula def já renomeada (relevante se sort_method = 'C' e há várias instâncias da mesma def)
             if isd && rdb.include?(target_object); next; end
             next unless target_object.respond_to?(:name=) && target_object.valid?

             # Preparar sequência
             sq = current_value.to_s
             
             # Determinar o novo nome baseado no modo selecionado
             new_name = ""
             case name_mode
             when "R"  # Substituição completa
               new_name = "#{prefix}#{sq}#{suffix}"
             when "K"  # Manter nome original + prefixo/sufixo
               new_name = "#{prefix}#{cn}#{suffix}"
             when "F"  # Find/Replace no nome original
               if !find_text.empty?
                 # Usar expressão regular para possibilitar opções case-sensitive
                 if keep_case
                   new_name = cn.gsub(Regexp.new(Regexp.escape(find_text)), replace_text)
                 else
                   new_name = cn.gsub(Regexp.new(Regexp.escape(find_text), Regexp::IGNORECASE), replace_text)
                 end
                 new_name = "#{prefix}#{new_name}#{suffix}"
               else
                 new_name = "#{prefix}#{cn}#{suffix}"
               end
             when "N"  # Nome + Número
               new_name = "#{prefix}#{cn}_#{sq}#{suffix}"
             when "C"  # Primeiro carácter + Número
               first_char = cn.strip.empty? ? "X" : cn[0]
               new_name = "#{prefix}#{first_char}#{sq}#{suffix}"
             end
             
             skip = false; reason = nil
             if new_name == cn
               skip = true; reason = :same_name;
             elsif isd && existing_def_names.include?(new_name)
               skip = true; reason = :def_exists;
             end

             if skip
                 sc += 1; skipped_reasons[reason] += 1
                 puts "   - Pulando '#{cn || '(S/N)'}' -> '#{new_name}': #{reason == :same_name ? "Igual" : "Def Existe"}."
             else
                 begin
                     target_object.name = new_name; pc += 1
                     if isd; existing_def_names << new_name; rdb.add(target_object); end
                     puts "   + Renomeado: '#{cn || '(S/N)'}' -> '#{new_name}'"
                     
                     # Adicionar à layer especificada
                     if add_layer && target_layer && item.respond_to?(:layer=)
                         begin
                             item.layer = target_layer
                             puts "     + Definido layer '#{layer_name}' para '#{new_name}'"
                         rescue => e
                             puts "     - Erro ao definir layer: #{e.message}"
                         end
                     end
                     
                     # Adicionar atributos personalizados
                     if add_attributes && !attribute_key.empty?
                         begin
                             attr_target = is_component ? item : target_object
                             if attr_target.respond_to?(:set_attribute)
                                 # Processar possíveis placeholders no valor do atributo
                                 processed_value = attribute_value.gsub("{nome}", new_name)
                                                                 .gsub("{seq}", sq)
                                                                 .gsub("{original}", cn)
                                 
                                 attr_target.set_attribute("RJVTools", attribute_key, processed_value)
                                 puts "     + Atributo '#{attribute_key}' definido para '#{processed_value}'"
                             end
                         rescue => e
                             puts "     - Erro ao definir atributo: #{e.message}"
                         end
                     end
                 rescue => re
                     puts "   - ERRO renomear '#{new_name}': #{re.message}"; sc += 1; skipped_reasons[:error] += 1
                 end
             end
             # Incrementa sequência SEMPRE
             if is_numeric; current_value += settings[:increment]; else; settings[:increment].times { current_value = increment_letter(current_value) }; end
          end # Fim loop ordered_items

          model.commit_operation
          status = "#{pc} Renomeados."; if sc > 0; status += " #{sc} pulados ("; details=[]; if skipped_reasons[:same_name]>0; details<<"#{skipped_reasons[:same_name]} nome igual"; end; if skipped_reasons[:def_exists]>0; details<<"#{skipped_reasons[:def_exists]} def existente"; end; if skipped_reasons[:error]>0; details<<"#{skipped_reasons[:error]} erro(s)"; end; status += details.join(', ') + ")."; end
          Sketchup.status_text = status; puts status
      end # Fim execute_bulk_rename


      # --- Função auxiliar para ordenar entidades (FORMATADA) ---
      private_class_method def self.sort_entities(entities, method, model)
        origin = ORIGIN; infinity = Float::INFINITY
        get_sort_value = -> (entity, calculation) do
            begin
              value = calculation.call(entity)
              # Retorna um valor comparável ou infinito
              value.respond_to?(:<=>) ? value : infinity
            rescue => e
              puts "Aviso sort value para #{entity.entityID rescue 'N/A'}: #{e.message}. Usando fallback."
              infinity # Coloca no final se der erro
            end
        end

        case method
        when 'C'
          return entities.sort_by(&:entityID)
        when 'L'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.x }) }
        when 'R'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.x }) }.reverse
        when 'F'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.y }) }
        when 'A'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.y }) }.reverse
        when 'B'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.z }) }
        when 'T'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.z }) }.reverse
        when 'NEAR'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.distance(origin) }) }
        when 'FAR'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.center.distance(origin) }) }.reverse
        when 'NAME'
          return entities.sort_by do |e|
            name = e.respond_to?(:definition) ? e.definition.name : e.name
            # Usa o helper get_sort_value para tratar nil
            get_sort_value.call(e, ->(_){ (name || "").downcase })
          end
        when 'NAMEDESC'
          return entities.sort_by do |e|
            name = e.respond_to?(:definition) ? e.definition.name : e.name
            get_sort_value.call(e, ->(_){ (name || "").downcase })
          end.reverse
        when 'SIZE'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.diagonal }) }
        when 'SIZEDESC'
          return entities.sort_by { |e| get_sort_value.call(e, ->(ent){ ent.bounds.diagonal }) }.reverse
        when 'RANDOM'
          return entities.shuffle
        else
          puts "Método ordenação inválido '#{method}'. Usando ID."
          return entities.sort_by(&:entityID) # Fallback para ID
        end
      # Captura erro geral na ordenação
      rescue => sort_error
          puts "Erro GERAL sort_entities: #{sort_error.message}"
          puts sort_error.backtrace.first(3)
          return nil # Retorna nil para indicar falha
      end # Fim sort_entities


      # --- Função auxiliar para incrementar letras (FORMATADA) ---
      private_class_method def self.increment_letter(string)
        chars = string.upcase.chars
        i = chars.length - 1
        while i >= 0
          if chars[i] == 'Z'
            chars[i] = 'A'
            i -= 1
          else
            chars[i] = chars[i].next
            return chars.join # Retorna aqui
          end
        end
        # Se saiu do loop, adiciona 'A'
        return 'A' + chars.join
      end # Fim increment_letter


      # --- get_or_create_layer ---
      private_class_method def self.get_or_create_layer(layer_name, model)
        begin
          lc = model.layers
          unless lc.is_a?(Sketchup::Layers)
            puts "Erro FATAL: model.layers!"
            return nil
          end
          l = lc[layer_name]
          if l.nil?
            puts "   - Criando Layer: '#{layer_name}'"
            l = lc.add(layer_name)
          elsif !l.is_a?(Sketchup::Layer)
            puts "Erro: '#{layer_name}' !Layer"
            return nil
          end
          unless l.is_a?(Sketchup::Layer)
            puts "Erro: Falha get/create Layer."
            return nil
          end
          return l
        rescue => e
          puts "Erro EXCEÇÃO get_layer: #{e.message}"
          puts e.backtrace.first(3)
          return nil
        end
      end # Fim get_or_create_layer

      # --- Função auxiliar para "casar" configurações caso altere o HTML ---
      private_class_method def self.extract_compatible_settings(js_settings)
        # Esta função é útil caso a interface HTML passe a enviar mais ou menos campos
        # que os esperados pelo módulo Ruby, garantindo compatibilidade
        
        known_keys = [
          :prefix, :suffix, :seqType, :startValue, :increment, :sortMethod, 
          :nameMode, :findText, :replaceText, :keepCase,
          :addLayer, :layerName, :addAttributes, :attributeKey, :attributeValue
        ]
        
        # Convertendo de "string" para :symbol como chaves
        result = {}
        js_settings.each do |k, v|
          sym_key = k.to_sym
          if known_keys.include?(sym_key)
            result[sym_key] = v
          end
        end
        
        # Garantindo valores padrão para campos obrigatórios
        result[:prefix] ||= ""
        result[:suffix] ||= ""
        result[:seqType] ||= "N"
        result[:startValue] ||= 1
        result[:increment] ||= 1
        result[:sortMethod] ||= "C"
        result[:nameMode] ||= "R"
        
        return result
      end # Fim extract_compatible_settings

    end # module RenameEntities
  end # module MockupTools
end # module Rjv