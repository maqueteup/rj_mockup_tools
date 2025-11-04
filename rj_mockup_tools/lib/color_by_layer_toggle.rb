# lib/color_by_layer_toggle.rb
# encoding: UTF-8

module Rjv
  module MockupTools
    module ColorByLayerToggle
      
      def self.toggle
        model = Sketchup.active_model
        return false unless model
        
        begin
          model.start_operation("Toggle Color by Layer", true)
          
          rop = model.rendering_options
          
          # A propriedade correta é 'DisplayColorByLayer', não 'RenderMode'
          if rop['DisplayColorByLayer'] == false
            rop['DisplayColorByLayer'] = true
          else
            rop['DisplayColorByLayer'] = false
          end
          
          # Força a atualização da view
          model.active_view.invalidate
          
          model.commit_operation
          return true
          
        rescue => e
          puts "Erro ao alternar Color by Layer: #{e.message}"
          model.abort_operation if model
          return false
        end
      end
      
      def self.activate_color_by_layer
        model = Sketchup.active_model
        return false unless model
        
        begin
          model.start_operation("Activate Color by Layer", true)
          model.rendering_options['DisplayColorByLayer'] = true
          model.active_view.invalidate
          model.commit_operation
          return true
          
        rescue => e
          puts "Erro ao ativar Color by Layer: #{e.message}"
          model.abort_operation if model
          return false
        end
      end
      
      def self.deactivate_color_by_layer
        model = Sketchup.active_model
        return false unless model
        
        return false if !is_active?
        
        begin
          model.start_operation("Deactivate Color by Layer", true)
          model.rendering_options['DisplayColorByLayer'] = false
          model.active_view.invalidate
          model.commit_operation
          return true
          
        rescue => e
          puts "Erro ao desativar Color by Layer: #{e.message}"
          model.abort_operation if model
          return false
        end
      end
      
      def self.is_active?
        model = Sketchup.active_model
        return false unless model
        
        begin
          # A propriedade correta é 'DisplayColorByLayer'
          return model.rendering_options['DisplayColorByLayer'] == true
        rescue => e
          puts "Erro ao verificar status Color by Layer: #{e.message}"
          return false
        end
      end
      
      # Método para usar em validation_proc de comandos de menu
      def self.validation_state
        return is_active? ? MF_CHECKED : MF_UNCHECKED
      end
      
      def self.get_current_render_mode
        model = Sketchup.active_model
        return nil unless model
        
        begin
          rop = model.rendering_options
          
          info = {}
          info[:color_by_layer] = rop['DisplayColorByLayer']
          info[:render_mode] = rop['RenderMode']
          
          # Mapeia o RenderMode para nome legível
          case info[:render_mode]
          when 0
            info[:render_mode_name] = "Wireframe"
          when 1
            info[:render_mode_name] = "Hidden Line"
          when 3
            info[:render_mode_name] = "Shaded"
          when 4
            info[:render_mode_name] = "Shaded with Textures"
          when 5
            info[:render_mode_name] = "Monochrome"
          when 6
            info[:render_mode_name] = "Color by Layer"
          when 7
            info[:render_mode_name] = "X-Ray"
          else
            info[:render_mode_name] = "Unknown (#{info[:render_mode]})"
          end
          
          return info
        rescue => e
          puts "Erro ao obter modo de renderização: #{e.message}"
          return nil
        end
      end
      
      # Método de teste para debug
      def self.debug_info
        model = Sketchup.active_model
        return "Nenhum modelo ativo" unless model
        
        begin
          rop = model.rendering_options
          mode_info = get_current_render_mode
          
          info = []
          info << "DisplayColorByLayer: #{rop['DisplayColorByLayer']}"
          info << "RenderMode: #{mode_info[:render_mode]} (#{mode_info[:render_mode_name]})"
          info << "Color by Layer ativo: #{is_active?}"
          info << "Versão do SketchUp: #{Sketchup.version}"
          
          return info.join("\n")
        rescue => e
          return "Erro ao obter informações: #{e.message}"
        end
      end
    end
  end
end

# Exemplo de uso:
# Rjv::MockupTools::ColorByLayerToggle.toggle
# Rjv::MockupTools::ColorByLayerToggle.is_active?
# Rjv::MockupTools::ColorByLayerToggle.debug_info

# Para uso em menus com validation:
# cmd.set_validation_proc { Rjv::MockupTools::ColorByLayerToggle.validation_state }