require 'sketchup'

module ChecarFacesPlugin
  module ChecarFaces
    class NegativeZFaceOverlay < Sketchup::Overlay

      COLOR_NEG_Z = Sketchup::Color.new(255, 0, 0, 128) # Cor semi-transparente para as faces Z negativas

      def initialize
        super('checar_faces_overlay', 'Checar Faces com Z Negativo')
        self.description = 'Destaca faces voltadas para o eixo Z negativo no contexto local do componente.'
        @negative_faces_points = []
        @bounds = Geom::BoundingBox.new
        start_observing
      end

      def start
        analyze_model(Sketchup.active_model)
      end

      def stop
        stop_observing
      end

      def draw(view)
        analyze_model(Sketchup.active_model)
        view.drawing_color = COLOR_NEG_Z
        view.draw(GL_TRIANGLES, @negative_faces_points) if @negative_faces_points.size % 3 == 0
      end

      def getExtents
        @bounds
      end

      # Observadores para eventos de modificação no modelo
      def onTransactionStart(model)
        analyze_model(model)
      end

      def onTransactionCommit(model)
        analyze_model(model)
      end

      def onTransactionUndo(model)
        analyze_model(model)
      end

      def onTransactionRedo(model)
        analyze_model(model)
      end

      private

      def start_observing
        model = Sketchup.active_model
        model.remove_observer(self)
        model.add_observer(self)
        Sketchup.active_model.active_view.add_observer(self)
      end

      def stop_observing
        model = Sketchup.active_model
        model.remove_observer(self)
        Sketchup.active_model.active_view.remove_observer(self)
      end

      def analyze_model(model)
        @negative_faces_points.clear
        model.entities.grep(Sketchup::ComponentInstance) do |component|
          analyze_component_faces(component, component.transformation)
        end
        recompute_bounds
        model.active_view.invalidate # Redesenha a view para refletir as alterações
      end

      def analyze_component_faces(component, transformation)
        local_z_negative = transformation.zaxis.reverse

        # Analisando faces dentro do componente
        component.definition.entities.grep(Sketchup::Face) do |face|
          face_normal_local = face.normal.transform(transformation)

          if face_normal_local.samedirection?(local_z_negative)
            collect_face_triangles(face, transformation)
          end
        end

        # Analisando componentes aninhados
        component.definition.entities.grep(Sketchup::ComponentInstance) do |nested_component|
          nested_transformation = nested_component.transformation * transformation
          analyze_component_faces(nested_component, nested_transformation) # Chamada corrigida
        end
      end

      def collect_face_triangles(face, transformation)
        face.mesh.polygons.each do |polygon|
          if polygon.size == 3
            points = polygon.map { |index| face.mesh.point_at(index).transform(transformation) }
            @negative_faces_points.concat(points)
          end
        end
      end

      def recompute_bounds
        @bounds = Geom::BoundingBox.new
        @negative_faces_points.each { |point| @bounds.add(point) }
      end

    end # class NegativeZFaceOverlay

    @overlay = nil

    # Ativando/desativando o overlay
    def self.toggle_overlay
      if @overlay.nil?
        @overlay = NegativeZFaceOverlay.new
        Sketchup.active_model.overlays.add(@overlay)
        @overlay.start
      else
        @overlay.stop
        Sketchup.active_model.overlays.remove(@overlay)
        @overlay = nil
      end
      update_button_state
    end

    # Atualiza a aparência do botão
    def self.update_button_state
      if @overlay.nil?
        @toggle_command.set_validation_state(UI::Command::STATE_ENABLED)
        @toggle_command.tooltip = "Ativar Checar Faces"
        @toggle_command.small_icon = File.join(__dir__, 'icons', 'checar_faces_icon.png')
        @toggle_command.large_icon = File.join(__dir__, 'icons', 'checar_faces_icon.png')
      else
        @toggle_command.set_validation_state(UI::Command::STATE_DISABLED)
        @toggle_command.tooltip = "Desativar Checar Faces"
        @toggle_command.small_icon = File.join(__dir__, 'icons', 'checar_faces_active_icon.png') # Ícone ativo
        @toggle_command.large_icon = File.join(__dir__, 'icons', 'checar_faces_active_icon.png') # Ícone ativo
      end
    end

    # Caminho do ícone
    icon_path = File.join(__dir__, 'icons', 'checar_faces_icon.png')
    active_icon_path = File.join(__dir__, 'icons', 'checar_faces_active_icon.png') # Ícone ativo

    # Criando o comando
    @toggle_command = UI::Command.new("Checar Faces") {
      toggle_overlay
      update_button_state
    }
    @toggle_command.small_icon = icon_path if File.exist?(icon_path)
    @toggle_command.large_icon = icon_path if File.exist?(icon_path)
    @toggle_command.tooltip = "Checar Faces voltadas para o Z negativo"
    @toggle_command.status_bar_text = "Destaca faces orientadas para o eixo Z negativo no UCS do componente."
    @toggle_command.menu_text = "Checar Faces"

    # Criando a toolbar
    toolbar = UI::Toolbar.new("Checar Faces")
    toolbar.add_item(@toggle_command)
    toolbar.show

    # Adicionando ao menu Plugins
    menu = UI.menu("Plugins")
    menu.add_item(@toggle_command)

  end # module ChecarFaces
end # module ChecarFacesPlugin
