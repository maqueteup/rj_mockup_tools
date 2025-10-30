# lib/notification_overlay.rb
# encoding: UTF-8

require 'sketchup.rb'

module Rjv
  module MockupTools
    module NotificationOverlay

      # ===== CONSTANTES =====
      OVERLAY_ID = 'makettepro_notifications'.freeze
      
      # Cores por tipo de notificação (mais suaves e discretas)
      COLORS = {
        info: {
          bg: Sketchup::Color.new(52, 152, 219, 180),  # Azul mais suave
          border: Sketchup::Color.new(41, 128, 185, 220),
          text: Sketchup::Color.new(255, 255, 255)
        },
        success: {
          bg: Sketchup::Color.new(46, 204, 113, 180),  # Verde mais suave
          border: Sketchup::Color.new(39, 174, 96, 220),
          text: Sketchup::Color.new(255, 255, 255)
        },
        warning: {
          bg: Sketchup::Color.new(241, 196, 15, 180),  # Amarelo mais suave
          border: Sketchup::Color.new(243, 156, 18, 220),
          text: Sketchup::Color.new(255, 255, 255)
        },
        error: {
          bg: Sketchup::Color.new(231, 76, 60, 180),   # Vermelho mais suave
          border: Sketchup::Color.new(192, 57, 43, 220),
          text: Sketchup::Color.new(255, 255, 255)
        },
        update: {
          bg: Sketchup::Color.new(155, 89, 182, 180),  # Roxo mais suave
          border: Sketchup::Color.new(142, 68, 173, 220),
          text: Sketchup::Color.new(255, 255, 255)
        },
        engraving: {
          bg: Sketchup::Color.new(52, 152, 219, 180),  # Azul claro mais suave
          border: Sketchup::Color.new(41, 128, 185, 220),
          text: Sketchup::Color.new(255, 255, 255)
        }
      }.freeze

      # ===== CLASSE DO OVERLAY =====
      class MaketteProNotificationOverlay < Sketchup::Overlay
        
        def initialize
          super(OVERLAY_ID, "MakettePro Notifications")
          @persistent_notifications = {}  # Para notificações permanentes por tipo
          @temporary_notifications = []   # Para notificações temporárias
          @cleanup_timer = nil
        end
        
        def draw(view)
          # Limpa notificações temporárias expiradas
          cleanup_expired_temporary_notifications
          
          # Desenha notificações persistentes primeiro (ficam no fundo)
          index = 0
          @persistent_notifications.each do |type, notification|
            draw_notification(view, notification, index, true)
            index += 1
          end
          
          # Desenha notificações temporárias por cima
          @temporary_notifications.each do |notification|
            draw_notification(view, notification, index, false)
            index += 1
          end
        end
        
        def getExtents
          # Retorna bounds vazio - notificações são 2D
          Geom::BoundingBox.new
        end
        
        # ===== GERENCIAMENTO DE NOTIFICAÇÕES =====
        
        # Adiciona notificação temporária (some automaticamente)
        def add_temporary_notification(message, type = :info, duration = 3000, position = :bottom_center)
          notification = {
            id: Time.now.to_f,
            message: message,
            type: type,
            position: position,
            created_at: Time.now,
            duration: duration / 1000.0,
            alpha: 1.0
          }
          
          @temporary_notifications << notification
          start_cleanup_timer
          Sketchup.active_model.active_view.invalidate
          
          puts "📢 Notificação temporária: #{message}"
          notification[:id]
        end
        
        # Adiciona/atualiza notificação persistente (fica até ser removida)
        def set_persistent_notification(key, message, type = :warning, position = :top_right)
          @persistent_notifications[key] = {
            id: key,
            message: message,
            type: type,
            position: position,
            created_at: Time.now,
            persistent: true,
            alpha: 1.0
          }
          
          Sketchup.active_model.active_view.invalidate
          puts "📌 Notificação persistente (#{key}): #{message}"
        end
        
        # Remove notificação persistente específica
        def remove_persistent_notification(key)
          if @persistent_notifications.delete(key)
            Sketchup.active_model.active_view.invalidate
            puts "🗑️ Removida notificação persistente: #{key}"
          end
        end
        
        # Limpa todas as notificações
        def clear_all_notifications
          @persistent_notifications.clear
          @temporary_notifications.clear
          stop_cleanup_timer
          Sketchup.active_model.active_view.invalidate
        end
        
        def cleanup
          clear_all_notifications
        end
        
        private
        
        # ===== DESENHO DAS NOTIFICAÇÕES =====
        def draw_notification(view, notification, index, is_persistent = false)
          begin
            # Calcula posição e dimensões (mais compactas e discretas)
            x, y, width, height = calculate_notification_bounds(view, notification, index, is_persistent)
            
            # Calcula alpha baseado no tempo (persistentes não fazem fade)
            alpha = is_persistent ? 0.9 : calculate_alpha(notification)
            
            # Pula se completamente transparente
            return if alpha <= 0
            
            # Cores com alpha aplicado
            colors = COLORS[notification[:type]] || COLORS[:info]
            bg_color = apply_alpha_to_color(colors[:bg], alpha)
            border_color = apply_alpha_to_color(colors[:border], alpha)
            text_color = apply_alpha_to_color(colors[:text], alpha)
            
            # Desenha sombra sutil para profundidade
            draw_notification_shadow(view, x + 2, y - 2, width, height, alpha * 0.3)
            
            # Desenha fundo da notificação com cantos arredondados (simulado)
            draw_notification_background(view, x, y, width, height, bg_color)
            
            # Desenha borda mais fina
            draw_notification_border(view, x, y, width, height, border_color)
            
            # Desenha ícone menor e mais discreto
            draw_notification_icon(view, x + 12, y + height/2, notification[:type], text_color)
            
            # Desenha texto mais compacto
            draw_notification_text(view, x + 32, y + height/2, notification[:message], text_color, is_persistent)
            
          rescue => e
            puts "Erro ao desenhar notificação: #{e.message}"
          end
        end
        
        def calculate_notification_bounds(view, notification, index, is_persistent)
          vp_width = view.vpwidth
          vp_height = view.vpheight
          
          # Dimensões mais compactas e discretas
          if is_persistent
            width = 300
            height = 35   # Mais baixo para ser discreto
            spacing = 40  # Menor espaçamento
          else
            width = 320
            height = 40
            spacing = 45
          end
          
          margin = 15
          
          # Calcula posição baseada no tipo
          case notification[:position]
          when :top_right
            x = vp_width - width - margin
            y = vp_height - margin - height - (index * spacing)
          when :top_left
            x = margin
            y = vp_height - margin - height - (index * spacing)
          when :top_center
            x = (vp_width - width) / 2
            y = vp_height - margin - height - (index * spacing)
          when :bottom_right
            x = vp_width - width - margin
            y = margin + (index * spacing)
          when :bottom_left
            x = margin
            y = margin + (index * spacing)
          when :bottom_center
            x = (vp_width - width) / 2
            y = margin + (index * spacing)
          else
            # Default: top_right
            x = vp_width - width - margin
            y = vp_height - margin - height - (index * spacing)
          end
          
          [x, y, width, height]
        end
        
        def calculate_alpha(notification)
          current_time = Time.now
          age = current_time - notification[:created_at]
          remaining = notification[:duration] - age
          
          # Fade out nos últimos 1 segundo
          if remaining < 1.0
            [remaining, 0.0].max
          else
            1.0
          end
        end
        
        def apply_alpha_to_color(color, alpha)
          Sketchup::Color.new(color.red, color.green, color.blue, (alpha * 255).to_i)
        end
        
        def draw_notification_shadow(view, x, y, width, height, alpha)
          shadow_color = Sketchup::Color.new(0, 0, 0, (alpha * 80).to_i)
          pts_shadow = [
            [x, y, 0],
            [x + width, y, 0],
            [x + width, y + height, 0],
            [x, y + height, 0]
          ]
          view.drawing_color = shadow_color
          view.draw2d(GL_QUADS, pts_shadow)
        end
        
        def draw_notification_background(view, x, y, width, height, bg_color)
          # Desenha retângulo de fundo
          view.drawing_color = bg_color
          pts_bg = [
            [x, y, 0],
            [x + width, y, 0],
            [x + width, y + height, 0],
            [x, y + height, 0]
          ]
          view.draw2d(GL_QUADS, pts_bg)
        end
        
        def draw_notification_border(view, x, y, width, height, border_color)
          # Desenha borda mais fina
          view.drawing_color = border_color
          view.line_width = 1  # Mais fino
          pts_border = [
            [x, y, 0],
            [x + width, y, 0],
            [x + width, y + height, 0],
            [x, y + height, 0]
          ]
          view.draw2d(GL_LINE_LOOP, pts_border)
        end
        
        def draw_notification_icon(view, x, y, type, color)
          # Desenha ícone menor e mais discreto
          view.drawing_color = color
          view.line_width = 1.5  # Mais fino
          
          case type
          when :info, :engraving
            # Círculo com "i" menor
            draw_circle(view, x, y, 6, color)
            # Ponto para o "i"
            view.draw2d(GL_POINTS, [[x, y - 2]])
            view.draw2d(GL_LINES, [[x, y + 1], [x, y + 4]])
          when :success
            # Checkmark menor
            pts = [[x - 3, y], [x - 1, y + 2], [x + 4, y - 3]]
            view.draw2d(GL_LINE_STRIP, pts)
          when :warning, :update
            # Triângulo menor
            pts = [
              [x, y - 4],
              [x - 3, y + 3],
              [x + 3, y + 3]
            ]
            view.draw2d(GL_LINE_LOOP, pts)
            # Ponto de exclamação
            view.draw2d(GL_LINES, [[x, y - 1], [x, y + 1]])
          when :error
            # X menor
            view.draw2d(GL_LINES, [
              [x - 3, y - 3], [x + 3, y + 3],
              [x + 3, y - 3], [x - 3, y + 3]
            ])
          end
        end
        
        def draw_circle(view, cx, cy, radius, color)
          # Desenha círculo menor
          points = []
          8.times do |i|  # Menos pontos para ser mais discreto
            angle = i * Math::PI * 2 / 8
            x = cx + Math.cos(angle) * radius
            y = cy + Math.sin(angle) * radius
            points << [x, y]
          end
          view.drawing_color = color
          view.draw2d(GL_LINE_LOOP, points)
        end
        
        def draw_notification_text(view, x, y, text, text_color, is_persistent = false)
          # Desenha texto mais compacto
          begin
            text_pt = Geom::Point3d.new(x, y, 0)
            text_options = {
              font: "Arial",
              size: is_persistent ? 10 : 11,  # Texto menor para persistentes
              bold: false,  # Menos bold para ser mais discreto
              color: text_color
            }
            view.draw_text(text_pt, text, text_options)
          rescue => e
            puts "Erro ao desenhar texto: #{e.message}"
          end
        end
        
        # ===== LIMPEZA AUTOMÁTICA =====
        def cleanup_expired_temporary_notifications
          current_time = Time.now
          initial_count = @temporary_notifications.size
          
          @temporary_notifications.reject! do |notification|
            age = current_time - notification[:created_at]
            age >= notification[:duration]
          end
          
          # Para timer se não há mais notificações temporárias
          if @temporary_notifications.empty? && @cleanup_timer
            stop_cleanup_timer
          end
          
          # Força redesenho se algo foi removido
          if @temporary_notifications.size != initial_count
            Sketchup.active_model.active_view.invalidate
          end
        end
        
        def start_cleanup_timer
          return if @cleanup_timer
          
          @cleanup_timer = UI.start_timer(1.0, true) do  # A cada 1 segundo
            cleanup_expired_temporary_notifications
          end
        end
        
        def stop_cleanup_timer
          if @cleanup_timer
            UI.stop_timer(@cleanup_timer)
            @cleanup_timer = nil
          end
        end
      end

      # ===== GERENCIAMENTO SINGLETON =====
      @overlay_instance = nil

      def self.initialize
        return if @overlay_instance && Sketchup.active_model.overlays.include?(@overlay_instance)

        # Remove overlay anterior se existir
        old_overlay = Sketchup.active_model.overlays.find { |o| o.overlay_id == OVERLAY_ID }
        Sketchup.active_model.overlays.remove(old_overlay) if old_overlay

        # Cria novo overlay
        @overlay_instance = MaketteProNotificationOverlay.new
        Sketchup.active_model.overlays.add(@overlay_instance)

        puts "✅ Sistema de notificações MakettePro inicializado!"
      end

      def self.show_notification(message, type = :info, duration = 3000, position = :bottom_center)
        initialize unless @overlay_instance
        @overlay_instance.add_temporary_notification(message, type, duration, position)
      end

      # ===== MÉTODOS DE CONVENIÊNCIA =====
      
      # Notificações PERMANENTES (ficam até situação ser resolvida)
      def self.show_pending_engravings(count)
        if count > 0
          message = "#{count} gravação#{count > 1 ? 'ões' : ''} pendente#{count > 1 ? 's' : ''}"
          initialize unless @overlay_instance
          @overlay_instance.set_persistent_notification(:pending_engravings, message, :engraving, :top_right)
        else
          hide_pending_engravings
        end
      end

      def self.hide_pending_engravings
        @overlay_instance&.remove_persistent_notification(:pending_engravings)
      end

      def self.show_pending_updates(count)
        if count > 0
          message = "#{count} carimbo#{count > 1 ? 's' : ''} para atualizar"
          initialize unless @overlay_instance
          @overlay_instance.set_persistent_notification(:pending_updates, message, :update, :top_right)
        else
          hide_pending_updates
        end
      end

      def self.hide_pending_updates
        @overlay_instance&.remove_persistent_notification(:pending_updates)
      end

      def self.show_editing_components(count)
        if count > 0
          message = "Editando #{count} componente#{count > 1 ? 's' : ''} associado#{count > 1 ? 's' : ''}"
          initialize unless @overlay_instance
          @overlay_instance.set_persistent_notification(:editing_components, message, :info, :top_center)
        else
          hide_editing_components
        end
      end

      def self.hide_editing_components
        @overlay_instance&.remove_persistent_notification(:editing_components)
      end
      
      # Notificações TEMPORÁRIAS (somem automaticamente)
      def self.show_material_applied(material_name, success = true)
        if success
          show_notification("✅ #{material_name} aplicado!", :success, 2000, :bottom_center)
        else
          show_notification("❌ Erro ao aplicar #{material_name}", :error, 3000, :bottom_center)
        end
      end

      def self.show_finish_applied(finish_name)
        show_notification("✅ #{finish_name} aplicado!", :success, 1500, :bottom_center)
      end

      def self.clear_all
        @overlay_instance&.clear_all_notifications
      end

      def self.cleanup
        if @overlay_instance
          begin
            Sketchup.active_model.overlays.remove(@overlay_instance)
          rescue => e
            puts "Erro ao remover overlay: #{e.message}"
          end
          @overlay_instance = nil
        end
      end

      # ===== MÉTODOS PARA TESTES =====
      def self.test_notifications
        show_notification("Testando notificação de informação", :info, 3000, :top_right)
        
        UI.start_timer(1.0, false) do
          show_notification("Testando notificação de sucesso!", :success, 3000, :top_center)
        end
        
        UI.start_timer(2.0, false) do
          show_notification("Testando notificação de aviso", :warning, 3000, :bottom_right)
        end
        
        UI.start_timer(3.0, false) do
          show_notification("Testando notificação de erro", :error, 3000, :bottom_center)
        end
      end
    end
  end
end