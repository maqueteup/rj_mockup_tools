# 📖 Mockup Tools RJV - API Documentation

## Versão 3.0.3

Esta documentação descreve a API pública dos principais módulos do plugin Mockup Tools RJV para SketchUp.

---

## 📦 Módulos Principais

### 1. **Rjv::MockupTools**

Módulo raiz do plugin.

#### Constantes

```ruby
Rjv::MockupTools::VERSION          # => "3.0.3"
Rjv::MockupTools::PLUGIN_NAME      # => "Mockup Tools RJV"
Rjv::MockupTools::PLUGIN_CREATOR   # => "Roberto Jackson Vieira"
Rjv::MockupTools::PLUGIN_ROOT_DIR  # => "/path/to/plugin"
```

#### Métodos Principais

```ruby
# Retorna string com nome e versão do plugin
Rjv::MockupTools.full_version_string
# => "Mockup Tools RJV v3.0.3"

# Retorna hash com informações completas
Rjv::MockupTools.info
# => { name: "Mockup Tools RJV", version: "3.0.3", ... }

# Conta peças MakettePro no modelo atual
Rjv::MockupTools.count_makette_pro_pieces
# => 42

# Abre o diálogo seletor principal
Rjv::MockupTools.open_selector_dialog
```

---

### 2. **FaceToBoard** - Conversão de Faces em Placas

Converte faces selecionadas em componentes 3D (placas).

#### Uso Básico

```ruby
# Converter faces selecionadas (modo interativo)
Rjv::MockupTools::FaceToBoard.run

# Converter faces específicas com opções
faces = Sketchup.active_model.selection.grep(Sketchup::Face)
result = Rjv::MockupTools::FaceToBoard.create_boards_from_faces(
  faces,
  thickness_mm: 6.0,
  reset_ucs: true,
  ucs_mode: :intelligent,
  silent: false
)
```

#### Opções Disponíveis

| Opção | Tipo | Padrão | Descrição |
|-------|------|--------|-----------|
| `thickness_mm` | Float | nil | Espessura da placa em mm (nil = pergunta ao usuário) |
| `reset_ucs` | Boolean | true | Aplica reset UCS após criação |
| `ucs_mode` | Symbol | :intelligent | Modo UCS (`:intelligent`, `:bottom_left`, `:center`) |
| `silent` | Boolean | false | Não mostra mensagens de UI |
| `debug` | Boolean | false | Mostra mensagens de debug |
| `keep_original` | Boolean | false | Mantém faces originais |

#### Retorno

```ruby
{
  success: true,                    # Boolean - operação bem-sucedida?
  created_components: [comp1, ...], # Array - componentes criados
  failed_faces: {},                 # Hash - faces que falharam
  ucs_result: {...},                # Hash - resultado do reset UCS
  message: "5 placa(s) criada(s)."  # String - mensagem descritiva
}
```

#### Funções de Conveniência

```ruby
# Criar placas SEM reset UCS
FaceToBoard.create_boards_only(faces, thickness_mm: 6.0)

# Criar placas COM reset UCS forçado
FaceToBoard.create_boards_with_smart_ucs(faces)

# Criar placas mantendo faces originais
FaceToBoard.create_boards_keep_original(faces)

# Analisar faces selecionadas (debug)
FaceToBoard.analyze_faces(faces)
```

---

### 3. **MaterialSystem** - Sistema de Materiais

Gerencia materiais, aplicação e propriedades dinâmicas.

#### Uso Básico

```ruby
# Acessar o gerenciador de propriedades
manager = Rjv::MockupTools::MaterialSystem.property_manager

# Obter propriedades (materiais, tipos, acabamentos)
properties = manager.properties
# => { types: [...], materials: [...], finishes: [...] }

# Aplicar material a componentes selecionados
material_props = {
  name: "MDF 6mm",
  thickness: 0.6,
  color: "#ffd865",
  layer: "MU_MDF 6mm"
}

Rjv::MockupTools::MaterialSystem.execute_material_action(material_props)

# Abrir editor de propriedades
Rjv::MockupTools::MaterialSystem.open_property_editor
```

#### Atributos Dinâmicos Criados

Quando um material é aplicado, os seguintes atributos são configurados:

```ruby
# MakettePro
definition.set_attribute("MakettePro", "identifier", "MakettePro")
definition.set_attribute("MakettePro", "material_name", "MDF 6mm")
definition.set_attribute("MakettePro", "thickness_mm", 6.0)

# Dynamic Components
dc_dict["_lengthunits"] = "CENTIMETERS"
dc_dict["_lenz_formula"] = "0.6"
dc_dict["_layer"] = "MU_MDF 6mm"
dc_dict["_material"] = "MDF 6mm"
dc_dict["_thickness_mm"] = 6.0
```

---

### 4. **LaserEngraving** - Gravação a Laser

Cria marcações de gravação a laser detectando arestas específicas.

#### Uso Básico

```ruby
# Criar gravação na seleção atual
Rjv::MockupTools::LaserEngraving.run_on_selection

# Criar gravação em TODAS as peças pendentes
Rjv::MockupTools::LaserEngraving.run_on_all_pending

# Verificar número de gravações pendentes
count = Rjv::MockupTools::LaserEngraving.check_for_pending_engravings
# => 5
```

#### Detecção de Arestas Graváveis

O sistema detecta automaticamente:
- Arestas sem faces (soltas)
- Arestas entre duas faces paralelas

#### Layer de Gravação

- Nome: `RJV_Gravação_Laser`
- Cor: Vermelho
- Arestas marcadas com atributo: `is_engraving_edge`

---

### 5. **Logger** - Sistema de Logging

Sistema de logging estruturado com níveis e cores.

#### Uso Básico

```ruby
# Configurar nível de log
Rjv::MockupTools::Logger.set_level(:DEBUG) # :DEBUG, :INFO, :WARN, :ERROR, :FATAL

# Logs simples
Rjv::MockupTools::Logger.debug("Mensagem de debug")
Rjv::MockupTools::Logger.info("Operação iniciada")
Rjv::MockupTools::Logger.warn("Aviso importante")
Rjv::MockupTools::Logger.error("Erro crítico")
Rjv::MockupTools::Logger.fatal("Erro fatal")

# Log com contexto
Rjv::MockupTools::Logger.info("Material aplicado", "FaceToBoard")
# => [2025-10-30 14:23:45] [INFO ] [FaceToBoard] Material aplicado

# Log com medição de tempo
Rjv::MockupTools::Logger.timed("Processando peças", level: :INFO) do
  # Operação cara
  process_pieces()
end
# => [INFO] Iniciando: Processando peças
# => [INFO] Concluído: Processando peças (1.234s)
```

#### Configurações

```ruby
# Habilitar/desabilitar cores
Rjv::MockupTools::Logger.set_colors(false)

# Configurar log em arquivo
Rjv::MockupTools::Logger.set_log_file("/path/to/log.txt")
```

---

### 6. **Cache** - Sistema de Cache

Sistema de cache com TTL (Time To Live).

#### Uso Básico

```ruby
# Fetch com cache automático
value = Rjv::MockupTools::Cache.fetch(:my_key, ttl: 5) do
  # Operação cara que será cacheada por 5 segundos
  expensive_operation()
end

# Set manual
Rjv::MockupTools::Cache.set(:key, "valor", ttl: 10)

# Get sem computar
value = Rjv::MockupTools::Cache.get(:key)

# Verificar se está no cache
if Rjv::MockupTools::Cache.cached?(:key)
  puts "Valor em cache!"
end

# Invalidar
Rjv::MockupTools::Cache.invalidate(:key)

# Limpar tudo
Rjv::MockupTools::Cache.clear

# Estatísticas
stats = Rjv::MockupTools::Cache.stats
# => { total_entries: 10, valid_entries: 8, expired_entries: 2, keys: [...] }
```

#### Cache de Contadores

```ruby
# Usar cache especializado para contadores
count = Rjv::MockupTools::CountersCache.get(:makette_pieces)

# Forçar refresh
count = Rjv::MockupTools::CountersCache.get(:makette_pieces, force_refresh: true)

# Contadores disponíveis:
# - :makette_pieces
# - :pending_updates
# - :pending_engravings
# - :mirrored_pieces
# - :scaled_pieces

# Invalidar todos os contadores
Rjv::MockupTools::CountersCache.invalidate_all
```

---

### 7. **JsonUtils** - Utilitários JSON

Utilitários para manipulação de JSON com validação.

#### Uso Básico

```ruby
# Carregar JSON
data = Rjv::MockupTools::JsonUtils.load_json("/path/to/file.json")

# Salvar JSON com arredondamento automático
Rjv::MockupTools::JsonUtils.save_json(
  "/path/to/file.json",
  data,
  precision: 3
)

# Arredondar floats em estrutura de dados
rounded = Rjv::MockupTools::JsonUtils.round_floats(data, 3)

# Validar estrutura de materiais
validation = Rjv::MockupTools::JsonUtils.validate_materials_json(data)
if validation[:valid]
  puts "JSON válido!"
else
  puts "Erros: #{validation[:errors]}"
end

# Corrigir precisão de arquivo existente
Rjv::MockupTools::JsonUtils.fix_json_precision("/path/to/file.json")
```

---

### 8. **Planifier** - Planificação Automática

Planifica peças 3D em layout 2D para corte.

#### Uso Básico

```ruby
# Planificar peças selecionadas
Rjv::MockupTools::Planifier.run

# Configurações (user_settings.json)
{
  "part_spacing": 2.0,        # Espaçamento entre peças (mm)
  "board_margin": 10.0,       # Margem da prancha (mm)
  "board_spacing": 50.0,      # Espaçamento entre pranchas (mm)
  "material_spacing": 200.0   # Espaçamento entre materiais (mm)
}
```

#### Funcionalidades

- Agrupa por material automaticamente
- Verifica colisões antes e depois
- Cria layer `RJV_Board` com contornos
- Aplica espaçamentos configuráveis

---

### 9. **CollisionAnalyzer** - Análise de Colisões

Detecta colisões entre peças do modelo.

#### Uso Básico

```ruby
# Abrir analisador de colisões
Rjv::MockupTools::CollisionAnalyzer.open_dialog
```

#### Tipos de Colisão Detectados

- **Interna**: Componentes completamente dentro de outros
- **Externa**: Componentes parcialmente sobrepostos

---

## 🔧 Utilitários Auxiliares

### Detecção de Espelhamento

```ruby
# Selecionar peças espelhadas
Rjv::MockupTools::MirrorHandler.select_mirrored

# Corrigir todas as peças espelhadas
Rjv::MockupTools::MirrorHandler.fix_all_mirrored
```

### Detecção de Escala

```ruby
# Selecionar peças com escala não uniforme
Rjv::MockupTools::ScaleHandler.select_scaled

# Corrigir peças selecionadas
Rjv::MockupTools::ScaleHandler.fix_selected_scaled
```

### Carimbos (Stamps)

```ruby
# Aplicar carimbo
Rjv::MockupTools::StampName.run

# Configurar carimbo
Rjv::MockupTools::StampName.configure_stamp_settings

# Atualizar carimbos existentes
Rjv::MockupTools::UpdateStamps.run

# Corrigir carimbos pendentes
Rjv::MockupTools::UpdateStamps.fix_pending_stamps

# Selecionar todos os carimbos
Rjv::MockupTools::SelectStamps.select_all_stamps
```

---

## 🎯 Exemplos Avançados

### Exemplo 1: Workflow Completo

```ruby
# 1. Selecionar faces
faces = Sketchup.active_model.selection.grep(Sketchup::Face)

# 2. Criar placas
result = Rjv::MockupTools::FaceToBoard.create_boards_from_faces(
  faces,
  thickness_mm: 3.0,
  reset_ucs: true
)

# 3. Aplicar material
material_props = {
  name: "MDF 3mm",
  thickness: 0.3,
  color: "#7c6419",
  layer: "MU_MDF 3mm"
}

result[:created_components].each do |comp|
  Sketchup.active_model.selection.add(comp)
end

Rjv::MockupTools::MaterialSystem.execute_material_action(material_props)

# 4. Criar gravações
Rjv::MockupTools::LaserEngraving.run_on_selection

# 5. Planificar
Rjv::MockupTools::Planifier.run
```

### Exemplo 2: Logging Estruturado

```ruby
# Configurar logging
Rjv::MockupTools::Logger.set_level(:DEBUG)
Rjv::MockupTools::Logger.set_log_file("#{ENV['HOME']}/rjv_mockup.log")

# Usar em operação
def process_model
  Rjv::MockupTools::Logger.info("Iniciando processamento do modelo")

  Rjv::MockupTools::Logger.timed("Contagem de peças") do
    count = Rjv::MockupTools.count_makette_pro_pieces
    Rjv::MockupTools::Logger.info("Encontradas #{count} peças")
  end

  Rjv::MockupTools::Logger.info("Processamento concluído")
rescue => e
  Rjv::MockupTools::Logger.error("Falha no processamento: #{e.message}")
  raise e
end
```

### Exemplo 3: Cache para Performance

```ruby
# Usar cache para operações caras
def get_model_stats
  Rjv::MockupTools::Cache.fetch(:model_stats, ttl: 10) do
    # Cálculo caro (cacheado por 10 segundos)
    {
      pieces: Rjv::MockupTools.count_makette_pro_pieces,
      engravings: count_engravings,
      materials: list_materials
    }
  end
end

# Invalidar quando modelo mudar
Sketchup.active_model.add_observer(MyObserver.new)

class MyObserver < Sketchup::ModelObserver
  def onActiveModelChanged(model)
    Rjv::MockupTools::Cache.clear
  end
end
```

---

## 📝 Notas Importantes

### Tolerância Numérica

O plugin usa tolerância de `1e-4` para comparações geométricas:

```ruby
Rjv::MockupTools::MaterialSystem::TOLERANCE # => 1e-4
Rjv::MockupTools::FaceToBoard::TOLERANCE    # => 1e-4
```

### Operações Transacionais

Todas as operações que modificam o modelo usam transações:

```ruby
model.start_operation("Nome da Operação", true)
# ... modificações ...
model.commit_operation
```

### Lazy Loading

Módulos são carregados sob demanda para otimizar performance. Use `ensure_loaded` para garantir carregamento:

```ruby
Rjv::MockupTools.ensure_loaded('LaserEngraving')
Rjv::MockupTools::LaserEngraving.run_on_selection
```

---

## 🔗 Referências

- **SketchUp Ruby API**: https://ruby.sketchup.com/
- **GitHub**: (adicionar link do repositório)
- **Documentação Completa**: Ver arquivo README.md

---

**Versão da Documentação**: 3.0.3
**Última Atualização**: 2025-10-30
**Autor**: Roberto Jackson Vieira
