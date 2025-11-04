# encoding: UTF-8

module Rjv
  module MockupTools
    class DeepPaintTool
      MK_SHIFT = 1
      VK_SHIFT = 16

      def initialize(material_to_apply)
        @material = material_to_apply
        @hovered_face = nil
        @hovered_transformation = nil
        @shift_down = false
        
        begin
          @cursor_id_normal = UI.create_cursor(File.join(PLUGIN_ROOT_DIR, 'resources', 'icons', 'paint-bucket.svg'), 0, 0)
        rescue
          @cursor_id_normal = 640
        end
        begin
          @cursor_id_shift = UI.create_cursor(File.join(PLUGIN_ROOT_DIR, 'resources', 'icons', 'paint-bucket-shift.svg'), 0, 0)
        rescue
          @cursor_id_shift = 640
        end
      end

      def activate
        UI.set_cursor(@cursor_id_normal)
        update_status_text
      end

      def deactivate(view)
        view.invalidate
        Sketchup.status_text = ""
      end

      def resume(view)
        UI.set_cursor(@shift_down ? @cursor_id_shift : @cursor_id_normal)
        update_status_text
      end

      def onCancel(reason, view)
        Sketchup.active_model.tools.pop_tool
      end
      
      def onLButtonDown(flags, x, y, view)
        ph = view.pick_helper; ph.do_pick(x, y)
        face = ph.leaf_at(0)
        return unless face.is_a?(Sketchup::Face)
        model = Sketchup.active_model
        
        if @shift_down
          model.start_operation("Deep Paint Same Materials", true)
          source_material = face.material
          target_material = @material
          if source_material != target_material
            parent_entities = face.parent.entities
            parent_entities.grep(Sketchup::Face).each { |f| f.material = target_material if f.material == source_material }
          end
          model.commit_operation
        else
          model.start_operation("Deep Paint Face", true)
          face.material = @material
          model.commit_operation
        end
      end

      def onKeyDown(key, r, p, view)
        if key == VK_SHIFT && !@shift_down
          @shift_down = true
          UI.set_cursor(@cursor_id_shift)
        end
      end

      def onKeyUp(key, r, p, view)
        if key == VK_SHIFT && @shift_down
          @shift_down = false
          UI.set_cursor(@cursor_id_normal)
        end
      end

      def onMouseMove(flags, x, y, view)
        ph = view.pick_helper; ph.do_pick(x, y)
        new_hovered_face = ph.leaf_at(0)
        if new_hovered_face != @hovered_face
          if new_hovered_face.is_a?(Sketchup::Face)
            @hovered_face = new_hovered_face
            @hovered_transformation = ph.transformation_at(0)
          else
            @hovered_face = nil; @hovered_transformation = nil
          end
          view.invalidate
        end
      end

      def draw(view)
        return unless @hovered_face && @hovered_face.valid? && @hovered_transformation
        view.line_stipple = ""
        view.line_width = 8
        view.drawing_color = Sketchup::Color.new(66, 133, 244)
        @hovered_face.loops.each do |loop|
          local_points = loop.vertices.map(&:position)
          world_points = local_points.map { |point| point.transform(@hovered_transformation) }
          view.draw(GL_LINE_LOOP, world_points)
        end
      end
      
      # --- CORREÇÃO APLICADA AQUI ---
      def getExtents
        # Pega a BoundingBox geral do modelo
        bb = Sketchup.active_model.bounds

        # Se houver uma face destacada, calcula sua BoundingBox global e a adiciona
        if @hovered_face && @hovered_face.valid? && @hovered_transformation
          # Pega a BoundingBox local da face
          local_bb = @hovered_face.bounds
          
          # Cria uma nova BoundingBox global vazia
          world_bb = Geom::BoundingBox.new
          
          # Transforma cada um dos 8 cantos da BoundingBox local e os adiciona na global
          (0..7).each do |i|
            corner_point = local_bb.corner(i)
            transformed_point = corner_point.transform(@hovered_transformation)
            world_bb.add(transformed_point)
          end
          
          # Adiciona a BoundingBox global recém-calculada à BoundingBox geral
          bb.add(world_bb)
        end
        return bb
      end

      private

      def update_status_text
        Sketchup.status_text = "Clique para pintar a face. Segure SHIFT para pintar faces iguais no mesmo objeto. ESC para sair."
      end
    end
  end
end