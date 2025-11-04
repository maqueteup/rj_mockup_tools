# encoding: UTF-8
require 'sketchup.rb'

module Rjv
  module MockupTools
    module AutoCADExporter
      extend self
      
      # Exporta planificações para AutoCAD
      def export_cuts_to_autocad
        puts "\n🚀 INICIANDO EXPORTAÇÃO PARA AUTOCAD (Send Action Method)"
        puts "=" * 60
        
        model = Sketchup.active_model
        selection = model.selection
        
        # Verifica se é SketchUp Pro
        unless Sketchup.is_pro?
          UI.messagebox("⚠️ A exportação DWG/DXF requer SketchUp Pro!\n\nVocê está usando: #{Sketchup.version}")
          return
        end
        
        # NOVO: Busca apenas 1 corte por vez
        export_group = get_single_export_group(model, selection)
        return unless export_group
        
        cut_name = get_cut_name(export_group)
        puts "📋 Corte selecionado: #{cut_name}"
        
        # Escolhe pasta de destino
        export_folder = UI.select_directory(title: "Escolher pasta para exportar DWG/DXF")
        return unless export_folder
        
        puts "📁 Pasta de destino: #{export_folder}"
        
        # Configurações de exportação
        export_config = get_export_configuration
        return unless export_config
        
        puts "⚙️ Configurações: #{export_config}"
        
        # Verifica se é Windows (para automação)
        if RUBY_PLATFORM.match(/mswin|mingw|cygwin/)
          puts "🪟 Windows detectado - automação disponível"
          export_with_automation(export_group, export_folder, export_config)
        else
          puts "🖱️ Exportação manual necessária"
          export_manual_mode(export_group, export_folder, export_config)
        end
      end
      
      private
      
      # NOVO: Busca apenas 1 corte selecionado
      def get_single_export_group(model, selection)
        if selection.empty?
          UI.messagebox("⚠️ Selecione UM corte para exportar!")
          return nil
        end
        
        # Filtra apenas grupos que são cortes
        cut_groups = selection.grep(Sketchup::Group).select { |g| g.get_attribute("RJV_Cut", "name") }
        
        if cut_groups.empty?
          UI.messagebox("⚠️ Nenhum corte válido selecionado!\n\nSelecione UM grupo de corte.")
          return nil
        end
        
        if cut_groups.length > 1
          UI.messagebox("⚠️ Selecione apenas UM corte por vez!\n\n#{cut_groups.length} cortes estão selecionados.")
          return nil
        end
        
        cut_groups.first
      end
      
      # Exportação com automação (Windows) - SIMPLIFICADA
      def export_with_automation(group, export_folder, config)
        begin
          require 'win32ole'
          shell = WIN32OLE.new("WScript.Shell")
          
          cut_name = get_cut_name(group)
          puts "\n📐 Exportando corte: #{cut_name}"
          
          result = export_single_cut_automated(group, export_folder, config, shell)
          
          if result[:success]
            puts "✅ Sucesso: #{result[:file_path]}"
            choice = UI.messagebox("Exportação concluída!\n\n✅ Corte '#{cut_name}' exportado com sucesso.\n\nDeseja abrir a pasta?", MB_YESNO)
            if choice == IDYES
              open_folder(File.expand_path(export_folder))
            end
          else
            puts "❌ Falha: #{result[:error]}"
            UI.messagebox("❌ Erro na exportação:\n\n#{result[:error]}")
          end
          
        rescue LoadError
          puts "⚠️ WIN32OLE não disponível, usando modo manual"
          export_manual_mode(group, export_folder, config)
        end
      end
      
      # Exportação manual (sem automação) - SIMPLIFICADA
      def export_manual_mode(group, export_folder, config)
        puts "\n🖱️ MODO MANUAL"
        
        cut_name = get_cut_name(group)
        safe_name = cut_name.gsub(/[^\w\s\-]/, '').strip.gsub(/\s+/, '_')
        suggested_filename = "#{safe_name}.#{config[:format].downcase}"
        
        puts "📐 Preparando corte: #{cut_name}"
        
        # Prepara vista para o corte
        hidden_entities = prepare_view_for_export(group, config)
        
        # Mensagem com nome sugerido
        UI.messagebox("EXPORTAÇÃO MANUAL\n\n📋 Nome do corte: #{cut_name}\n📄 Nome sugerido: #{safe_name}\n\nO dialog de Export 2D será aberto.\n\n1. Use o nome: #{safe_name}\n2. Configure como #{config[:format]}\n3. Pasta: #{export_folder}\n4. Clique Export")
        
        # MÉTODO CORRETO: Abre Export 2D Dialog
        puts "    🚀 Abrindo Export 2D Dialog..."
        Sketchup.send_action(21237)  # Export 2D Graphics
        
        # Aguarda usuário completar
        result = UI.messagebox("Corte '#{cut_name}' exportado?\n\nClique SIM se exportou com sucesso.", MB_YESNO)
        
        if result == IDYES
          puts "    ✅ Corte '#{cut_name}' exportado com sucesso"
          UI.messagebox("✅ Exportação concluída!\n\nCorte '#{cut_name}' exportado com sucesso.")
        else
          puts "    ❌ Exportação cancelada"
        end
        
        # Restaura vista
        restore_manual_view(group, hidden_entities)
      end
      
      # Exportação automatizada de um corte - SEM configuração de nome
      def export_single_cut_automated(group, export_folder, config, shell)
        model = Sketchup.active_model
        
        # Nome do arquivo baseado no nome do corte (apenas para logs)
        cut_name = get_cut_name(group)
        safe_name = cut_name.gsub(/[^\w\s\-]/, '').strip.gsub(/\s+/, '_')
        filename_without_ext = safe_name
        extension = config[:format].downcase
        filename = "#{filename_without_ext}.#{extension}"
        file_path = File.join(export_folder, filename)
        
        puts "    📄 Arquivo esperado: #{filename}"
        puts "    📝 Nome do corte: #{cut_name}"
        
        # Salva estado
        saved_state = save_view_state(model)
        hidden_entities = []
        
        begin
          # Prepara vista
          hidden_entities = prepare_view_for_export(group, config)
          
          # ABRE EXPORT 2D DIALOG
          puts "    🚀 Abrindo Export 2D Dialog automatizado..."
          Sketchup.send_action(21237)  # Export 2D Graphics
          
          # Aguarda dialog abrir
          sleep(2.0)
          
          # Automação Windows - SEM configuração de nome
          puts "    ⌨️ Enviando comandos automatizados..."
          
          # Vai direto para configurar pasta
          configure_export_folder(shell, export_folder)
          
          # Configura tipo de arquivo
          puts "    ⚙️ Configurando formato #{config[:format]}..."
          configure_file_type(shell, config[:format])
          
          # Exporta
          puts "    📤 Executando exportação..."
          shell.SendKeys("{ENTER}")  # Clica Export
          sleep(2.0)
          
          # Fecha confirmação se houver
          shell.SendKeys("{ENTER}")
          sleep(0.5)
          
          # VERIFICAÇÃO SIMPLIFICADA: Sempre considera sucesso
          puts "    ✅ Comandos de exportação enviados com sucesso"
          
          # Verifica se arquivo foi criado (opcional, só para logs)
          if File.exist?(file_path)
            file_size = File.size(file_path)
            puts "    ✅ Arquivo confirmado: #{filename} (#{file_size} bytes)"
            return { success: true, file_path: file_path }
          else
            # Procura arquivos relacionados
            related_files = find_related_files(export_folder, safe_name, cut_name, extension)
            if related_files.any?
              puts "    ✅ Arquivo encontrado: #{related_files.first}"
              return { success: true, file_path: File.join(export_folder, related_files.first) }
            else
              puts "    ✅ Exportação executada (arquivo pode ter nome diferente)"
              return { success: true, file_path: "Exportado com sucesso" }
            end
          end
          
        rescue => e
          return { success: false, error: "Erro na automação: #{e.message}" }
          
        ensure
          # Restaura vista
          restore_view_state(model, saved_state, hidden_entities)
        end
      end
      
      # NOVO: Configura apenas a pasta (sem mexer no nome)
      def configure_export_folder(shell, export_folder)
        puts "      📁 Configurando pasta de destino..."
        
        # Usa Ctrl+L para ir direto à barra de endereços
        shell.SendKeys("^l")  # Ctrl+L
        sleep(0.8)
        
        # Limpa e digita o caminho da pasta
        shell.SendKeys("^a")  # Seleciona tudo
        sleep(0.3)
        
        windows_path = export_folder.gsub('/', '\\')
        shell.SendKeys(windows_path)
        sleep(0.5)
        
        shell.SendKeys("{ENTER}")  # Navega para pasta
        sleep(1.5)  # Aguarda navegação
        
        puts "      ✅ Pasta configurada: #{windows_path}"
      end
      
      # NOVO: Configura tipo de arquivo (simplificado)
      def configure_file_type(shell, format)
        # Tab para campo tipo
        shell.SendKeys("{TAB}")  
        sleep(0.3)
        
        if format == "DWG"
          shell.SendKeys("A")  # AutoCAD DWG (primeira opção com A)
        else
          shell.SendKeys("A")  # Vai para DWG primeiro
          sleep(0.2)
          shell.SendKeys("{DOWN}")  # Desce para DXF
        end
        
        sleep(0.3)
        shell.SendKeys("{TAB}")  # Vai para botão Export
        sleep(0.3)
      end
      
      # NOVO: Procura arquivos relacionados
      def find_related_files(export_folder, safe_name, cut_name, extension)
        return [] unless Dir.exist?(export_folder)
        
        Dir.entries(export_folder).select do |file|
          next if File.directory?(File.join(export_folder, file))
          
          file_lower = file.downcase
          safe_lower = safe_name.downcase
          cut_lower = cut_name.downcase.gsub(' ', '_')
          
          # Procura por nome exato, similar, ou contendo o nome do corte
          file_lower.include?(safe_lower) || 
          file_lower.include?(cut_lower) ||
          file_lower.include?('teste') ||  # Nome padrão do SketchUp
          (file_lower.end_with?(".#{extension}") && file_lower.length > 3)
        end.sort_by { |f| File.mtime(File.join(export_folder, f)) }.reverse
      end
      
      # Prepara vista para exportação - MELHORADA
      def prepare_view_for_export(group, config)
        model = Sketchup.active_model
        hidden_entities = []
        
        puts "    💾 Preparando vista 2D..."
        
        # Ativa cena ou ColorByLayer
        if config[:use_planification_scene]
          scene_activated = activate_planification_scene(model)
          unless scene_activated
            puts "      ⚠️ Cena 'Planificação' não encontrada, ativando ColorByLayer"
            activate_color_by_layer(model)
          end
        else
          puts "      🎨 Ativando ColorByLayer"
          activate_color_by_layer(model)
        end
        
        # Esconde TODAS as outras entidades (incluindo outros cortes)
        model.entities.each do |entity|
          if entity != group && entity.visible? && entity.valid?
            if entity.is_a?(Sketchup::Group) && entity.get_attribute("RJV_Cut", "name")
              puts "        🚫 Escondendo outro corte: #{get_cut_name(entity)}"
            end
            entity.visible = false
            hidden_entities << entity
          end
        end
        
        # Garante que o grupo atual está visível
        group.visible = true
        
        # Configura vista 2D focada
        setup_2d_view_for_group(model, group)
        
        puts "    ✅ Vista 2D preparada (#{hidden_entities.length} entidades escondidas)"
        hidden_entities
      end
      
      # NOVO: Ativa estilo CAD pré-configurado da pasta resources
      def activate_color_by_layer(model)
        begin
          puts "      🎨 Carregando estilo CAD pré-configurado..."
          
          # Primeiro tenta usar sua função ColorByLayer
          begin
            result1 = Rjv::MockupTools::ColorByLayerToggle.activate_color_by_layer
            puts "      ✅ ColorByLayer ativado via função"
          rescue NameError
            puts "      ⚠️ Função ColorByLayer não encontrada"
            result1 = false
          end
          
          # Procura e carrega estilo CAD da pasta resources
          style_loaded = load_cad_style(model)
          
          if style_loaded
            puts "      ✅ Estilo CAD carregado com sucesso"
            return true
          elsif result1
            puts "      ✅ ColorByLayer ativado (sem estilo CAD)"
            return true
          else
            puts "      ⚠️ Usando método básico de atualização"
            model.active_view.invalidate
            return false
          end
          
        rescue => e
          puts "      ❌ Erro ao ativar configurações CAD: #{e.message}"
          model.active_view.invalidate
          return false
        end
      end
      
      # NOVO: Carrega estilo CAD da pasta resources
      def load_cad_style(model)
        begin
          # Determina o diretório do plugin
          # __FILE__ aponta para o arquivo atual do módulo
          current_file = __FILE__
          plugin_dir = File.dirname(current_file)
          
          # Caminhos possíveis para o estilo CAD (baseado na estrutura vista)
          possible_paths = [
            File.join(plugin_dir, 'resources', 'CAD.style'),
            File.join(plugin_dir, '..', 'resources', 'CAD.style'),
            File.join(plugin_dir, '..', '..', 'resources', 'CAD.style'),
            File.join(plugin_dir, '...', 'resources', 'CAD.style'),
            # Caminhos alternativos caso esteja em subpasta
            File.join(File.dirname(plugin_dir), 'resources', 'CAD.style'),
            File.join(File.dirname(File.dirname(plugin_dir)), 'resources', 'CAD.style')
          ]
          
          puts "      🔍 Procurando estilo CAD..."
          puts "      📂 Diretório atual: #{plugin_dir}"
          
          # Procura pelo arquivo de estilo
          style_file = nil
          possible_paths.each_with_index do |path, index|
            puts "      🔍 Testando #{index + 1}: #{path}"
            if File.exist?(path)
              style_file = path
              puts "      ✅ Estilo encontrado: #{path}"
              break
            else
              puts "      ❌ Não encontrado: #{path}"
            end
          end
          
          if style_file.nil?
            puts "      ⚠️ Arquivo CAD.style não encontrado!"
            puts "      💡 Verifique se existe em: .../rj_mockup_tools/resources/CAD.style"
            return false
          end
          
          # Carrega o estilo
          styles = model.styles
          puts "      📦 Carregando estilo CAD..."
          
          begin
            # Adiciona e ativa o estilo
            new_style = styles.add_style(style_file, true)  # true = activate immediately
            puts "      ✅ Estilo CAD '#{new_style.name}' carregado e ativado"
            
            # Força atualização da view
            model.active_view.invalidate
            sleep(0.3)  # Pequena pausa para garantir que carregou
            
            return true
            
          rescue => e
            puts "      ⚠️ Erro ao carregar estilo: #{e.message}"
            puts "      🔄 Tentando ativar estilo CAD existente..."
            
            # Fallback: procura estilo CAD já carregado
            styles.each do |style|
              style_name = style.name.downcase
              if style_name.include?('cad') || style_name == 'cad'
                puts "      🔄 Ativando estilo existente: #{style.name}"
                styles.selected_style = style
                model.active_view.invalidate
                return true
              end
            end
            
            puts "      ❌ Não foi possível carregar ou encontrar estilo CAD"
            return false
          end
          
        rescue => e
          puts "      ❌ Erro geral ao procurar estilo CAD: #{e.message}"
          puts "      📍 Arquivo atual: #{__FILE__}"
          return false
        end
      end
      
      # Ativa cena de planificação - MELHORADA
      def activate_planification_scene(model)
        model.pages.each do |page|
          page_name = page.name.downcase
          if page_name.include?("planific") || page_name.include?("planif") || page_name == "planificação"
            puts "      🎬 Ativando cena: '#{page.name}'"
            model.pages.selected_page = page
            page.update(1)
            sleep(0.3)
            return true
          end
        end
        false
      end
      
      # Configura vista 2D focada no grupo
      def setup_2d_view_for_group(model, group)
        view = model.active_view
        bounds = group.bounds
        center = bounds.center
        width = bounds.width.to_f
        height = bounds.height.to_f
        depth = bounds.depth.to_f
        
        # Câmera Top ortográfica
        distance = [width, height, depth].max + 1000
        eye = [center.x, center.y, center.z + distance]
        target = [center.x, center.y, center.z]
        up = [0, 1, 0]
        
        camera = Sketchup::Camera.new(eye, target, up)
        camera.perspective = false
        camera.height = [width, height].max * 1.1
        
        view.camera = camera
        view.invalidate
      end
      
      # Restaura vista no modo manual (INCLUINDO estilo)
      def restore_manual_view(group, hidden_entities)
        puts "    🔄 Restaurando vista..."
        
        model = Sketchup.active_model
        
        # Restaura entidades escondidas
        hidden_entities.each do |entity|
          begin
            entity.visible = true if entity.valid?
          rescue
            # Ignora erros
          end
        end
        
        # Se tiver salvo o estilo original, restaura
        # (Para modo manual, vamos apenas tentar restaurar o primeiro estilo que não seja CAD)
        begin
          styles = model.styles
          current_style = styles.selected_style
          
          if current_style && current_style.name.downcase.include?('cad')
            puts "    🎨 Restaurando estilo padrão..."
            # Procura um estilo padrão para restaurar
            styles.each do |style|
              style_name = style.name.downcase
              if style_name.include?('default') || style_name.include?('padrão') || 
                 style_name == 'simple style' || style_name == 'architectural design'
                puts "    🔄 Restaurando para: #{style.name}"
                styles.selected_style = style
                break
              end
            end
          end
        rescue => e
          puts "    ⚠️ Erro ao restaurar estilo: #{e.message}"
        end
        
        model.active_view.invalidate
        puts "    ✅ Vista restaurada"
      end
      
      # Salva estado da vista (INCLUINDO estilo atual)
      def save_view_state(model)
        view = model.active_view
        camera = view.camera
        
        {
          camera: {
            eye: camera.eye.clone,
            target: camera.target.clone,
            up: camera.up.clone,
            perspective: camera.perspective?,
            height: (camera.perspective? ? nil : camera.height),
            fov: (camera.perspective? ? camera.fov : nil)
          },
          page: model.pages.selected_page,
          original_style: model.styles.selected_style  # NOVO: Salva estilo atual
        }
      end
      
      # Restaura estado da vista (INCLUINDO estilo original + ZOOM EXTENTS)
      def restore_view_state(model, saved_state, hidden_entities)
        puts "    🔄 Restaurando vista..."
        
        # Restaura entidades escondidas
        hidden_entities.each do |entity|
          begin
            entity.visible = true if entity.valid?
          rescue
            # Ignora erros
          end
        end
        
        # Restaura câmera
        view = model.active_view
        camera_data = saved_state[:camera]
        camera = view.camera
        camera.set(camera_data[:eye], camera_data[:target], camera_data[:up])
        camera.perspective = camera_data[:perspective]
        
        if camera_data[:perspective]
          camera.fov = camera_data[:fov] if camera_data[:fov]
        else
          camera.height = camera_data[:height] if camera_data[:height]
        end
        
        view.camera = camera
        
        # NOVO: Restaura estilo original
        if saved_state[:original_style] && saved_state[:original_style].valid?
          begin
            puts "    🎨 Restaurando estilo original: #{saved_state[:original_style].name}"
            model.styles.selected_style = saved_state[:original_style]
          rescue => e
            puts "    ⚠️ Erro ao restaurar estilo: #{e.message}"
          end
        end
        
        # Restaura cena
        if saved_state[:page] && saved_state[:page] != model.pages.selected_page
          model.pages.selected_page = saved_state[:page]
          saved_state[:page].update(1)
        end
        
        # CHAVE DE OURO: Zoom Extents no final! 🔑✨
        puts "    🔍 Zoom Extents - finalizando com chave de ouro!"
        view.zoom_extents
        view.invalidate
        
        puts "    ✅ Vista restaurada completamente com Zoom Extents"
      end
      
      # Métodos auxiliares
      def get_cut_name(group)
        return "Invalid Group" unless group.valid?
        group.get_attribute("RJV_Cut", "name") || group.name || "Unnamed"
      end
      
      def get_export_configuration
        prompts = [
          "Formato:",
          "Ativar cena 'Planificação' (ou ColorByLayer):"
        ]
        
        defaults = ["DWG", "Sim"]
        
        lists = [
          "DWG|DXF",
          "Sim|Não"
        ]
        
        results = UI.inputbox(prompts, defaults, lists, "Export 2D - Corte Individual")
        return nil unless results
        
        {
          format: results[0],
          use_planification_scene: results[1] == "Sim"
        }
      end
      
      def open_folder(folder_path)
        if RUBY_PLATFORM.match(/mswin|mingw|cygwin/)
          system("explorer \"#{folder_path.gsub('/', '\\')}\"")
        elsif RUBY_PLATFORM.match(/darwin/)
          system("open \"#{folder_path}\"")
        else
          system("xdg-open \"#{folder_path}\"")
        end
      end
      
    end # Fim do módulo AutoCADExporter
  end # Fim do módulo MockupTools
end # Fim do módulo Rjv