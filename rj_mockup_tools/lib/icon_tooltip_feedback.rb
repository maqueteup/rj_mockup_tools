# lib/icon_tooltip_feedback.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    module IconTooltipFeedback
      
      # ===== CLASSE PRINCIPAL =====
      class IconStatusManager
        
        def initialize
          @pending_engravings = 0
          @pending_updates = 0
          @last_status = nil
          @engraving_commands = []  # Referências para os comandos
          @update_commands = []     # Referências para os comandos
        end
        
        def update_status(pending_engravings, pending_updates)
          current_status = "#{pending_engravings}-#{pending_updates}"
          return if @last_status == current_status  # Evita updates desnecessários
          
          @last_status = current_status
          @pending_engravings = pending_engravings
          @pending_updates = pending_updates
          
          # Atualiza tooltips e ícones dos botões
          update_button_tooltips_and_icons
          
          puts "📊 Status atualizado: #{pending_engravings} gravações, #{pending_updates} carimbos"
        end
        
        def register_engraving_command(command)
          @engraving_commands << command
        end
        
        def register_update_command(command)
          @update_commands << command
        end
        
        private
        
        def update_button_tooltips_and_icons
          # Atualiza botões de gravação
          @engraving_commands.each do |cmd|
            next unless cmd
            
            if @pending_engravings > 0
              # Ícone "pendente" + tooltip com informação
              cmd.small_icon = get_engraving_icon_path(true)
              cmd.large_icon = get_engraving_icon_path(true)
              cmd.tooltip = "🔴 Gerar Gravação a Laser (#{@pending_engravings} pendente#{@pending_engravings > 1 ? 's' : ''})"
              cmd.status_bar_text = "#{@pending_engravings} gravação#{@pending_engravings > 1 ? 'ões' : ''} pendente#{@pending_engravings > 1 ? 's' : ''} - clique para processar"
            else
              # Ícone "normal" + tooltip padrão
              cmd.small_icon = get_engraving_icon_path(false)
              cmd.large_icon = get_engraving_icon_path(false)
              cmd.tooltip = "Gerar Gravação a Laser"
              cmd.status_bar_text = "Gerar Gravação a Laser na seleção"
            end
          end
          
          # Atualiza botões de update
          @update_commands.each do |cmd|
            next unless cmd
            
            if @pending_updates > 0
              # Ícone "pendente" + tooltip com informação
              cmd.small_icon = get_update_icon_path(true)
              cmd.large_icon = get_update_icon_path(true)
              cmd.tooltip = "🟡 Atualizar Carimbos (#{@pending_updates} pendente#{@pending_updates > 1 ? 's' : ''})"
              cmd.status_bar_text = "#{@pending_updates} carimbo#{@pending_updates > 1 ? 's' : ''} para atualizar - clique para atualizar"
            else
              # Ícone "normal" + tooltip padrão
              cmd.small_icon = get_update_icon_path(false)
              cmd.large_icon = get_update_icon_path(false)
              cmd.tooltip = "Atualizar Carimbos"
              cmd.status_bar_text = "Atualizar todos os carimbos"
            end
          end
        end
        
        def get_engraving_icon_path(has_pending)
          icons_dir = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, 'icons')
          
          if has_pending
            File.join(icons_dir, 'create_engraving_pending.png')  # Ícone vermelho/alerta
          else
            File.join(icons_dir, 'create_engraving_normal.png')   # Ícone normal
          end
        end
        
        def get_update_icon_path(has_pending)
          icons_dir = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, 'icons')
          
          if has_pending
            File.join(icons_dir, 'update_stamps_pending.png')     # Ícone amarelo/alerta
          else
            File.join(icons_dir, 'update_stamps_normal.png')      # Ícone normal
          end
        end
        
        def cleanup
          @engraving_commands.clear
          @update_commands.clear
        end
      end
      
      # ===== SINGLETON =====
      @manager = nil
      
      def self.initialize
        @manager ||= IconStatusManager.new
      end
      
      def self.update_status(pending_engravings, pending_updates)
        initialize
        @manager.update_status(pending_engravings, pending_updates)
      end
      
      def self.register_engraving_command(command)
        initialize
        @manager.register_engraving_command(command)
      end
      
      def self.register_update_command(command)
        initialize
        @manager.register_update_command(command)
      end
      
      def self.cleanup
        @manager&.cleanup
        @manager = nil
      end
    end
  end
end