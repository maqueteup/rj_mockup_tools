# encoding: UTF-8
# Mockup Tools RJV - Rename Entities Tool Module (Versão Melhorada)

require 'sketchup.rb'
require 'set'

module Rjv
  module MockupTools

    # Ferramenta de seleção interativa para Renomear
    class RenameSelectionTool
      VK_ESCAPE = 27

      def initialize(dialog, selection_array)
        @dialog = dialog
        @selection = selection_array
      end

      def activate
        @model = Sketchup.active_model
        @view = @model.active_view
        Sketchup.status_text = "Renomear: Clique nos objetos na ordem desejada (Esc para finalizar)"
        puts "Seleção interativa ativada - #{@selection.length} já selecionado(s)"
      end

      def deactivate(view)
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)

        # Suporte para objetos aninhados usando InstancePath
        picked = nil
        if ph.count > 0
          # Tenta usar path para objetos aninhados
          path = ph.path_at(0)
          if path.is_a?(Sketchup::InstancePath)
            # Pega o último elemento do path (objeto mais profundo)
            picked = path.to_a.last
          else
            # Fallback para best_picked
            picked = ph.best_picked
          end
        end

        return unless picked
        return unless picked.is_a?(Sketchup::Group) || picked.is_a?(Sketchup::ComponentInstance)

        # Verifica se já está selecionado
        if @selection.include?(picked)
          # Desseleção: remove da lista
          @selection.delete(picked)
          puts "Removido: #{@selection.length} objeto(s) restante(s)"
        else
          # Adiciona à seleção
          @selection << picked
          puts "Adicionado: #{@selection.length} objeto(s)"
        end

        # Atualiza o diálogo
        @dialog.execute_script("updateSelectionCount(#{@selection.length});")

        # Invalida a view para redesenhar com novo número
        @view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        if key == VK_ESCAPE
          puts "Seleção finalizada: #{@selection.length} objeto(s)"
          @model.select_tool(nil)
          return true
        end
        false
      end

      def draw(view)
        return if @selection.empty?

        view.line_stipple = ""
        view.line_width = 8
        view.drawing_color = Sketchup::Color.new(66, 133, 244)  # Azul como DeepPaintTool

        @selection.each do |entity|
          next unless entity.valid?
          draw_entity_edges(view, entity)
        end
      end

      def draw_entity_edges(view, entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities.grep(Sketchup::Edge).each do |edge|
            view.draw(GL_LINES, edge.start.position.transform(entity.transformation),
                                edge.end.position.transform(entity.transformation))
          end
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.definition.entities.grep(Sketchup::Edge).each do |edge|
            view.draw(GL_LINES, edge.start.position.transform(entity.transformation),
                                edge.end.position.transform(entity.transformation))
          end
        end
      end

      def onSetCursor
        UI.set_cursor(0)
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        if @selection && !@selection.empty?
          @selection.each do |entity|
            bb.add(entity.bounds) if entity.valid?
          end
        end
        bb
      end
    end

    module RenameEntities

      # --- Constantes ---
      TOLERANCE = 1e-4
      X_AXIS = Geom::Vector3d.new(1, 0, 0).freeze
      Y_AXIS = Geom::Vector3d.new(0, 1, 0).freeze
      Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze
      ORIGIN = Geom::Point3d.new(0, 0, 0).freeze
      STAMP_LAYER_NAME = "MU_Texto".freeze
      STAMP_ATTRIBUTE_DICT = "Rjv_StampName".freeze
      STAMP_GROUP_IDENTIFIER_KEY = "IsStampNameGroup".freeze

      # --- Estado ---
      @last_bulk_settings = {
          prefix: "Comp_",
          suffix: "",
          seqType: "N",
          startValue: 1,
          increment: 1,
          sortMethod: "SEL",  # SEL=Selection Order (novo padrão)
          nameMode: "R",      # R=Replace, K=Keep+Prefix/Suffix, F=Find/Replace
          findText: "",
          replaceText: "",
          keepCase: true
      }.freeze

      # --- Métodos para gerenciar carimbos ---
      private_class_method def self.has_stamp?(definition)
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

      private_class_method def self.remove_stamps(definition)
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

      private_class_method def self.reapply_stamp(definition)
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
          return true
        end

        false
      end

      # --- Getter para Configurações ---
      def self.get_last_bulk_settings
        unless defined?(@last_bulk_settings)
            @last_bulk_settings = {
                prefix: "Comp_",
                suffix: "",
                seqType: "N",
                startValue: 1,
                increment: 1,
                sortMethod: "SEL",  # SEL=Selection Order (novo padrão)
                nameMode: "R",
                findText: "",
                replaceText: "",
                keepCase: true
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

        # Permite abrir sem seleção - diálogo terá botão de seleção
        if valid_entities.empty?
          # Abre diálogo vazio, usuário pode clicar em "Selecionar"
          show_bulk_rename_dialog([], model)
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

        # Adicionar opção de carimbar para renomeação individual
        prompts = [prompt_text, "Carimbar?"]
        defaults = [current_name, "Sim"]
        list = ["", "Sim|Não"]
        input = UI.inputbox(prompts, defaults, list, "Renomear")
        return unless input

        new_name = input[0].strip
        apply_stamp = input[1] == "Sim"

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
            # Verificar se tem carimbo antes de renomear
            had_stamp = false
            if is_definition
              had_stamp = has_stamp?(target_object)
              if had_stamp
                remove_stamps(target_object)
              end
            end

            # Renomear
            target_object.name = new_name

            # Reaplicar ou aplicar novo carimbo
            if is_definition
              if had_stamp
                reapply_stamp(target_object)
              elsif apply_stamp
                reapply_stamp(target_object)
              end
            end

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
          # Variável para rastrear a seleção atual
          current_selection = initial_selection.dup

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
              dialog.execute_script("initializeDialog(#{current_selection.length}, #{settings_to_send.to_json});")
          end

          dialog.add_action_callback("start_selection") do |action_context|
              # Ativa ferramenta de seleção interativa
              puts "Iniciando seleção interativa para Renomear..."
              model.select_tool(RenameSelectionTool.new(dialog, current_selection))
          end

          dialog.add_action_callback("save_settings") do |action_context, settings|
               prefix = settings["prefix"] || ""
               suffix = settings["suffix"] || ""
               seq_type = (settings["seqType"] == "A") ? "A" : "N"
               sv_raw = settings["startValue"]
               sort_method = settings["sortMethod"] || "SEL"  # Default agora é SEL
               inc = settings["increment"].to_i; inc = 1 if inc < 1
               name_mode = settings["nameMode"] || "R"
               find_text = settings["findText"] || ""
               replace_text = settings["replaceText"] || ""
               keep_case = settings["keepCase"] == true
               apply_stamp = settings["applyStamp"] != false

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
                   applyStamp: apply_stamp
               }.freeze

               dialog.close
               execute_bulk_rename(current_selection, model, @last_bulk_settings)
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

          # Agrupa e Ordena
          definitions_to_rename = {}; groups_to_rename = []
          entities_to_rename.each do |entity|
              next unless entity.valid?
              if entity.is_a?(Sketchup::ComponentInstance); definitions_to_rename[entity.definition] ||= entity;
              elsif entity.is_a?(Sketchup::Group); groups_to_rename << entity; end
          end
          items_to_sort = groups_to_rename + definitions_to_rename.values
          begin
              # Para "SEL" (Selection Order), passa a lista original na ordem de seleção
              ordered_items = sort_entities(items_to_sort, settings[:sortMethod], model, entities_to_rename)
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
                     # Verificar se tem carimbo antes de renomear
                     had_stamp = false
                     if isd
                       had_stamp = has_stamp?(target_object)
                       if had_stamp
                         remove_stamps(target_object)
                         puts "     - Carimbo removido"
                       end
                     end

                     # Renomear
                     target_object.name = new_name; pc += 1
                     if isd; existing_def_names << new_name; rdb.add(target_object); end
                     puts "   + Renomeado: '#{cn || '(S/N)'}' -> '#{new_name}'"

                     # Reaplicar ou aplicar novo carimbo
                     if isd
                       if had_stamp
                         if reapply_stamp(target_object)
                           puts "     + Carimbo reaplicado"
                         end
                       elsif settings[:applyStamp]
                         # Não tinha carimbo, mas usuário quer aplicar
                         if reapply_stamp(target_object)
                           puts "     + Carimbo aplicado"
                         end
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
      private_class_method def self.sort_entities(entities, method, model, original_selection = nil)
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
        when 'SEL'
          # Ordem de seleção: preserva a ordem original
          if original_selection && !original_selection.empty?
            # Cria um mapa de índices da seleção original
            selection_index = {}
            original_selection.each_with_index do |entity, idx|
              if entity.is_a?(Sketchup::ComponentInstance)
                selection_index[entity.definition] = idx unless selection_index.key?(entity.definition)
              elsif entity.is_a?(Sketchup::Group)
                selection_index[entity] = idx
              end
            end

            # Ordena entities baseado no índice da seleção original
            return entities.sort_by do |e|
              target = e.is_a?(Sketchup::ComponentInstance) ? e.definition : e
              selection_index[target] || infinity
            end
          else
            # Fallback: mantém a ordem atual
            return entities
          end
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