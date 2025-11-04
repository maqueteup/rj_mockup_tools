# lib/icon_generator.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    module IconGenerator
      
      # Mapeamento dos ícones Font Awesome para caracteres Unicode
      FONT_AWESOME_ICONS = {
        'fa-layer-group' => "\uf5fd",      # face_to_board
        'fa-cubes' => "\uf1b3",           # group_to_component  
        'fa-crosshairs' => "\uf05b",      # reset_ucs
        'fa-retweet' => "\uf079",         # flip_ucs
        'fa-i-cursor' => "\uf246",        # rename_entities
        'fa-undo' => "\uf0e2",            # rot_x
        'fa-redo' => "\uf01e",            # rot_y
        'fa-sync-alt' => "\uf2f1",        # rot_z
        'fa-pencil-ruler' => "\uf5ae",    # create_engraving
        'fa-font' => "\uf031",            # apply_stamp
        'fa-tasks' => "\uf0ae",           # select_stamps
        'fa-magic' => "\uf0d0",           # update_stamps
        'fa-palette' => "\uf53f",         # color_manager
        'fa-th' => "\uf00a",              # planifier
        'fa-object-group' => "\uf247"     # collision_analyzer
      }
      
      ICON_DEFINITIONS = {
        'face_to_board.png' => { icon: 'fa-layer-group', color: '#007bff' },
        'group_to_component.png' => { icon: 'fa-cubes', color: '#28a745' },
        'reset_ucs.png' => { icon: 'fa-crosshairs', color: '#17a2b8' },
        'flip_ucs.png' => { icon: 'fa-retweet', color: '#6c757d' },
        'rename_entities.png' => { icon: 'fa-i-cursor', color: '#6f42c1' },
        'rotate_x.png' => { icon: 'fa-undo', color: '#dc3545' },
        'rotate_y.png' => { icon: 'fa-redo', color: '#fd7e14' },
        'rotate_z.png' => { icon: 'fa-sync-alt', color: '#20c997' },
        'create_engraving.png' => { icon: 'fa-pencil-ruler', color: '#e83e8c' },
        'apply_stamp.png' => { icon: 'fa-font', color: '#6f42c1' },
        'select_stamps.png' => { icon: 'fa-tasks', color: '#495057' },
        'update_stamps.png' => { icon: 'fa-magic', color: '#f8c146' },
        'color_manager.png' => { icon: 'fa-palette', color: '#e91e63' },
        'planifier.png' => { icon: 'fa-th', color: '#795548' },
        'collision_analyzer.png' => { icon: 'fa-object-group', color: '#ff5722' }
      }

      def self.generate_all_icons(icons_dir)
        puts "🎨 Gerando ícones para MakettePro..."
        
        ICON_DEFINITIONS.each do |filename, config|
          icon_path = File.join(icons_dir, filename)
          
          unless File.exist?(icon_path)
            generate_png_icon(icon_path, config[:icon], config[:color])
            puts "✅ Criado: #{filename}"
          end
        end
        
        puts "🚀 Todos os ícones foram gerados!"
      end

      def self.generate_png_icon(output_path, fa_icon, color)
        # Gera um ícone PNG 24x24 usando ImageMagick (se disponível)
        # Fallback para ícone simples se ImageMagick não estiver disponível
        
        begin
          # Tenta usar ImageMagick
          unicode_char = FONT_AWESOME_ICONS[fa_icon] || "\uf059"
          
          # Comando ImageMagick para gerar ícone
          magick_cmd = [
            "magick",
            "-size", "24x24",
            "xc:transparent",
            "-font", "Font-Awesome-6-Free-Solid-900",
            "-pointsize", "16",
            "-fill", color,
            "-gravity", "center",
            "-annotate", "+0+0", unicode_char,
            output_path
          ].join(" ")
          
          # Executa comando
          result = `#{magick_cmd} 2>&1`
          
          if $?.success?
            puts "✅ Ícone gerado com ImageMagick: #{File.basename(output_path)}"
          else
            # Fallback para método simples
            generate_simple_icon(output_path, fa_icon, color)
          end
          
        rescue => e
          # Fallback para método simples
          generate_simple_icon(output_path, fa_icon, color)
        end
      end

      def self.generate_simple_icon(output_path, fa_icon, color)
        # Gera um ícone BMP básico com Ruby puro
        icon_name = fa_icon.gsub('fa-', '').upcase[0..1]
        
        # Converte cor hex para RGB
        color = color.gsub('#', '')
        r = color[0..1].to_i(16)
        g = color[2..3].to_i(16) 
        b = color[4..5].to_i(16)
        
        # Cria BMP 24x24
        width = 24
        height = 24
        
        # Header BMP simplificado
        file_size = 54 + (width * height * 3)
        
        header = [
          0x42, 0x4D,                    # BM signature
          file_size & 0xFF, (file_size >> 8) & 0xFF, (file_size >> 16) & 0xFF, (file_size >> 24) & 0xFF,
          0, 0, 0, 0,                    # Reserved
          54, 0, 0, 0,                   # Offset to pixel data
          40, 0, 0, 0,                   # DIB header size
          width, 0, 0, 0,                # Width
          height, 0, 0, 0,               # Height  
          1, 0,                          # Planes
          24, 0,                         # Bits per pixel
          0, 0, 0, 0,                    # Compression
          0, 0, 0, 0,                    # Image size
          0, 0, 0, 0,                    # X pixels per meter
          0, 0, 0, 0,                    # Y pixels per meter
          0, 0, 0, 0,                    # Colors used
          0, 0, 0, 0                     # Important colors
        ]
        
        # Pixel data (BGR format para BMP)
        pixels = []
        (0...height).each do |y|
          (0...width).each do |x|
            # Desenha ícone simples com borda
            if x < 2 || x >= width-2 || y < 2 || y >= height-2
              pixels += [b, g, r]  # Cor principal na borda
            elsif x < 4 || x >= width-4 || y < 4 || y >= height-4  
              pixels += [(b*0.7).to_i, (g*0.7).to_i, (r*0.7).to_i]  # Cor média
            else
              pixels += [(b*0.4).to_i, (g*0.4).to_i, (r*0.4).to_i]  # Cor clara no centro
            end
          end
        end
        
        # Escreve arquivo BMP
        bmp_path = output_path.gsub('.png', '.bmp')
        File.open(bmp_path, 'wb') do |file|
          file.write(header.pack('C*'))
          file.write(pixels.pack('C*'))
        end
        
        puts "✅ Ícone BMP gerado: #{File.basename(bmp_path)}"
      end
    end

    # ===== SISTEMA DE NOTIFICAÇÕES DESENHADAS NA TELA =====
    module ScreenNotifications
      
      class NotificationOverlay
        def initialize
          @notifications = []
          @update_timer = nil
          @notification_id = 0
        end
        
        def show_notification(message, type = :info, duration = 3000, position = :top_right)
          notification = {
            id: (@notification_id += 1),
            message: message,
            type: type,
            duration: duration,
            position: position,
            created_at: Time.now,
            alpha: 1.0
          }
          
          @notifications << notification
          
          # Inicia timer de atualização se não estiver rodando
          start_update_timer unless @update_timer
          
          # Agenda remoção da notificação
          UI.start_timer(duration / 1000.0, false) do
            remove_notification(notification[:id])
          end
          
          # Força repaint da viewport
          Sketchup.active_model.active_view.invalidate
          
          notification[:id]
        end
        
        def remove_notification(id)
          @notifications.reject! { |n| n[:id] == id }
          
          # Para timer se não há mais notificações
          if @notifications.empty? && @update_timer
            UI.stop_timer(@update_timer)
            @update_timer = nil
          end
          
          Sketchup.active_model.active_view.invalidate
        end
        
        def start_update_timer
          @update_timer = UI.start_timer(0.1, true) do
            update_notifications
          end
        end
        
        def update_notifications
          return if @notifications.empty?
          
          current_time = Time.now
          needs_repaint = false
          
          @notifications.each do |notification|
            age = current_time - notification[:created_at]
            remaining = notification[:duration] / 1000.0 - age
            
            # Fade out nos últimos 500ms
            if remaining < 0.5
              notification[:alpha] = [remaining / 0.5, 0.0].max
              needs_repaint = true
            end
          end
          
          # Remove notificações expiradas
          initial_count = @notifications.size
          @notifications.reject! { |n| 
            age = current_time - n[:created_at]
            age >= n[:duration] / 1000.0
          }
          
          needs_repaint = true if @notifications.size != initial_count
          
          # Para timer se não há mais notificações
          if @notifications.empty?
            UI.stop_timer(@update_timer)
            @update_timer = nil
          end
          
          Sketchup.active_model.active_view.invalidate if needs_repaint
        end
        
        def draw(view)
          return if @notifications.empty?
          
          # Configurações de desenho
          view.line_width = 1
          
          @notifications.each_with_index do |notification, index|
            draw_notification(view, notification, index)
          end
        end
        
        def draw_notification(view, notification, index)
          # Calcula posição baseada no tipo
          x, y = calculate_position(notification[:position], index)
          
          # Dimensões da notificação
          width = 300
          height = 60
          padding = 12
          
          # Cores por tipo
          colors = {
            info: { bg: [100, 150, 250], border: [70, 120, 220] },
            success: { bg: [100, 200, 100], border: [70, 170, 70] },
            warning: { bg: [255, 200, 100], border: [225, 170, 70] },
            error: { bg: [250, 100, 100], border: [220, 70, 70] }
          }
          
          color_set = colors[notification[:type]] || colors[:info]
          alpha = (notification[:alpha] * 255).to_i
          
          # Cor de fundo com transparência
          bg_color = Sketchup::Color.new(
            color_set[:bg][0], 
            color_set[:bg][1], 
            color_set[:bg][2], 
            alpha
          )
          
          # Cor da borda
          border_color = Sketchup::Color.new(
            color_set[:border][0], 
            color_set[:border][1], 
            color_set[:border][2], 
            alpha
          )
          
          # Desenha fundo
          points_2d = [
            [x, y],
            [x + width, y],
            [x + width, y + height],
            [x, y + height]
          ]
          
          view.drawing_color = bg_color
          view.draw2d(GL_QUADS, points_2d)
          
          # Desenha borda
          view.drawing_color = border_color
          view.line_width = 2
          view.draw2d(GL_LINE_LOOP, points_2d)
          
          # Desenha ícone (simples)
          icon_x = x + padding
          icon_y = y + padding
          icon_size = 16
          
          icon_points = [
            [icon_x, icon_y],
            [icon_x + icon_size, icon_y],
            [icon_x + icon_size, icon_y + icon_size],
            [icon_x, icon_y + icon_size]
          ]
          
          view.drawing_color = border_color
          view.draw2d(GL_LINE_LOOP, icon_points)
          
          # Desenha texto (usando TextOptions se disponível)
          begin
            text_x = x + padding + icon_size + 8
            text_y = y + height / 2
            
            options = {
              font: "Arial",
              size: 12,
              bold: false,
              align: TextAlignLeft,
              color: border_color
            }
            
            view.draw_text([text_x, text_y, 0], notification[:message], options)
            
          rescue => e
            # Fallback para texto simples
            puts "Texto da notificação: #{notification[:message]}"
          end
        end
        
        def calculate_position(position, index)
          view = Sketchup.active_model.active_view
          viewport_width = view.vpwidth
          viewport_height = view.vpheight
          
          notification_height = 70 # altura + espaçamento
          offset_y = index * notification_height
          
          case position
          when :top_right
            x = viewport_width - 320  # 300 + 20 de margem
            y = 20 + offset_y
          when :top_left
            x = 20
            y = 20 + offset_y
          when :bottom_right
            x = viewport_width - 320
            y = viewport_height - 80 - offset_y
          when :bottom_left
            x = 20
            y = viewport_height - 80 - offset_y
          when :center
            x = (viewport_width - 300) / 2
            y = (viewport_height - 60) / 2 + offset_y - 50
          else
            x = viewport_width - 320
            y = 20 + offset_y
          end
          
          [x, y]
        end
        
        def cleanup
          @notifications.clear
          if @update_timer
            UI.stop_timer(@update_timer)
            @update_timer = nil
          end
        end
      end
      
      # ===== TOOL OBSERVER PARA DESENHAR NOTIFICAÇÕES =====
      class NotificationTool
        def initialize
          @overlay = NotificationOverlay.new
        end
        
        def activate
          # Tool ativado
        end
        
        def deactivate(view)
          # Tool desativado
        end
        
        def draw(view)
          @overlay.draw(view)
        end
        
        def onLButtonDown(flags, x, y, view)
          # Clique remove notificações na área
          false # Não consome o evento
        end
        
        def show_notification(message, type = :info, duration = 3000, position = :top_right)
          @overlay.show_notification(message, type, duration, position)
        end
        
        def cleanup
          @overlay.cleanup
        end
      end
      
      # ===== SINGLETON GLOBAL =====
      @notification_tool = nil
      
      def self.initialize
        @notification_tool = NotificationTool.new
        
        # Adiciona observer para desenhar em todas as views
        Sketchup.active_model.active_view.add_observer(ViewObserver.new)
      end
      
      def self.show_notification(message, type = :info, duration = 3000, position = :top_right)
        initialize unless @notification_tool
        @notification_tool.show_notification(message, type, duration, position)
      end
      
      def self.cleanup
        @notification_tool&.cleanup
        @notification_tool = nil
      end
      
      # ===== VIEW OBSERVER =====
      class ViewObserver < Sketchup::ViewObserver
        def onViewChanged(view)
          # Força redesenho das notificações quando view muda
          ScreenNotifications.draw_notifications(view) if ScreenNotifications.instance_variable_get(:@notification_tool)
        end
      end
      
      def self.draw_notifications(view)
        @notification_tool&.draw(view)
      end
    end
  end
end

# ===== INICIALIZAÇÃO AUTOMÁTICA =====
unless defined?(@@makettepro_icons_loaded)
  # Gera ícones automaticamente
  icons_dir = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, 'icons')
  FileUtils.mkdir_p(icons_dir) unless Dir.exist?(icons_dir)
  
  Rjv::MockupTools::IconGenerator.generate_all_icons(icons_dir)
  
  # Inicializa sistema de notificações
  Rjv::MockupTools::ScreenNotifications.initialize
  
  @@makettepro_icons_loaded = true
  puts "🎨 Sistema de ícones e notificações carregado!"
end