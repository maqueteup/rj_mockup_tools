# Loader para o plugin ChecarFaces

module ChecarFacesPlugin
  # Define o caminho base para os arquivos do plugin
  plugin_path = __dir__

  # Carrega o código principal do plugin
  require(File.join(plugin_path, 'checar_faces', 'main'))
end
