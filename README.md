# 🛠️ Mockup Tools RJV

**Versão 3.0.3** | Plugin Profissional para SketchUp

Plugin avançado para criação e análise de mockups, projetos de fabricação com laser, corte e gravação.

---

## 📋 Índice

- [Características](#-características)
- [Instalação](#-instalação)
- [Uso Básico](#-uso-básico)
- [Funcionalidades](#-funcionalidades)
- [Documentação Completa](#-documentação-completa)
- [Requisitos](#-requisitos)
- [Licença](#-licença)

---

## ✨ Características

### 🎯 Principais Funcionalidades

- **Conversão Inteligente**: Converta faces em placas 3D com reset automático de eixos (UCS)
- **Sistema de Materiais**: Catálogo completo com aplicação automática de propriedades dinâmicas
- **Gravação a Laser**: Detecção automática de arestas graváveis
- **Planificação Automática**: Layout 2D otimizado para corte com detecção de colisões
- **Análise de Colisões**: Detecta sobreposições entre peças
- **Carimbos 3D**: Sistema de marcação com texto 3D configurável
- **Workflow Inteligente**: Automatiza tarefas comuns de modelagem

### 🚀 Performance

- **Lazy Loading**: Carregamento otimizado de módulos sob demanda
- **Cache Inteligente**: Sistema de cache com TTL para operações caras
- **Logging Estruturado**: Sistema de logs com níveis configuráveis
- **Validação de Dados**: Validação automática de JSON e estruturas de dados

### 🏗️ Arquitetura

- **Modular**: 38+ módulos Ruby independentes
- **Extensível**: Fácil adição de novas funcionalidades
- **Bem Documentado**: API completa e exemplos de uso
- **Tolerante a Falhas**: Tratamento robusto de erros

---

## 📦 Instalação

### Método 1: Instalação Manual

1. Baixe o plugin (`rj_mockup_tools.rbz`)
2. No SketchUp, vá em: **Window > Extension Manager**
3. Clique em **Install Extension**
4. Selecione o arquivo `.rbz` baixado
5. Reinicie o SketchUp

### Método 2: Instalação por Arquivo

1. Baixe os arquivos do plugin
2. Copie o arquivo `rj_mockup_tools.rb` para:
   - **Windows**: `C:\Users\<usuario>\AppData\Roaming\SketchUp\SketchUp 20XX\SketchUp\Plugins\`
   - **macOS**: `~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins/`
3. Copie a pasta `rj_mockup_tools/` para o mesmo diretório
4. Reinicie o SketchUp

---

## 🎮 Uso Básico

### 1. Acessar o Plugin

Após instalação, acesse o plugin através do menu:

```
Extensions > Mockup Tools RJV > Seletor de Ferramentas
```

### 2. Criar uma Placa

1. Selecione uma ou mais faces no modelo
2. Clique no botão **"Placa a partir da Face"**
3. Digite a espessura desejada (em mm)
4. O componente 3D será criado automaticamente com eixos resetados

### 3. Aplicar Material

1. Selecione componentes criados
2. No painel do seletor, clique em um material
3. O sistema aplicará automaticamente:
   - Material visual
   - Layer correspondente
   - Propriedades dinâmicas
   - Espessura correta

### 4. Criar Gravação

1. Selecione componentes com arestas graváveis
2. Clique em **"Criar Gravação"**
3. Arestas serão automaticamente marcadas na layer `RJV_Gravação_Laser`

### 5. Planificar Peças

1. Selecione as peças a planificar
2. Clique em **"Planifier"**
3. O sistema criará layout 2D organizado por material

---

## 🔧 Funcionalidades

### 📐 Modelagem

#### Face to Board
- Converte faces em componentes 3D (placas)
- Reset automático de eixos (UCS)
- Suporte a furos e geometrias complexas
- 3 modos de UCS: inteligente, canto inferior, centro

#### Reset UCS
- Reseta eixos de componentes
- Detecção inteligente de orientação
- Preserva dimensões e transformações
- Suporte a seleção múltipla

#### Rotações Locais
- Rotações de 90° em X, Y, Z
- Baseado em eixos locais do componente
- Operações reversíveis

### 🎨 Materiais

#### Sistema de Materiais
- **13 materiais pré-configurados**:
  - MDF (2.5mm, 3mm, 6mm, 9mm)
  - Acrílico (1-5mm)
  - PVC (2mm)
  - PET (0.7mm)
  - Melamina (2.8mm)
  - Fórmica (0.7mm)

- **8 acabamentos disponíveis**:
  - Crystal, Espelhado, Leitoso, Água
  - Grama, Preto, Dupla Face, Madeirado

#### Gerenciador de Materiais
- Interface HTML moderna
- Editor visual de propriedades
- Import/Export de configurações JSON
- Geração automática de ícones

### ⚡ Gravação e Fabricação

#### Laser Engraving
- Detecção automática de arestas graváveis:
  - Arestas sem faces
  - Arestas entre faces paralelas
- Layer dedicada (`RJV_Gravação_Laser`)
- Processamento em lote
- Sistema de estado para evitar reprocessamento

#### Planificação
- Layout 2D otimizado
- Agrupamento por material
- Espaçamentos configuráveis
- Detecção de colisões
- Geração de contornos em layer `RJV_Board`

### 🔍 Análise

#### Collision Analyzer
- Detecta colisões entre peças
- Identifica tipo (interna/externa)
- Interface HTML com listagem
- Seleção automática de peças problemáticas

#### Mirror & Scale Handlers
- **Mirror Handler**:
  - Detecta componentes espelhados
  - Oferece correção automática
- **Scale Handler**:
  - Detecta escalas não uniformes
  - Corrige escalas mantendo proporções

#### Model Inspector
- Inspeção geral do modelo
- Estatísticas de componentes
- Análise de camadas
- Relatórios detalhados

### 📝 Carimbos (Stamps)

#### Stamp System
- Adiciona texto 3D em componentes
- Configuração de:
  - Fonte (TrueType support)
  - Tamanho
  - Profundidade
  - Posicionamento
- Sistema de atualização em lote
- Detecção de carimbos pendentes

### 🎯 Workflow

#### Intelligent Workflow
- Automatiza etapas comuns
- Detecção automática de materiais
- Aplicação em lote
- Configuração de espessura automática

---

## 📚 Documentação Completa

### Documentos Disponíveis

- **[API.md](./API.md)** - Documentação completa da API pública
- **[IMPROVEMENTS.md](./IMPROVEMENTS.md)** - Histórico de melhorias e roadmap
- **[CHANGELOG.md](./CHANGELOG.md)** - Log de mudanças entre versões

### Documentação Online

- **SketchUp Ruby API**: https://ruby.sketchup.com/
- **Guias e Tutoriais**: (adicionar link se disponível)

### Exemplos de Código

Veja **[API.md](./API.md)** para exemplos completos de uso programático.

---

## 🔧 Configuração

### Arquivos de Configuração (JSON)

Todos em `rj_mockup_tools/data/`:

#### materiais.json
Catálogo de materiais com tipos, espessuras e acabamentos.

```json
{
  "types": [...],
  "finishes": [...],
  "materials": [...]
}
```

#### user_settings.json
Configurações de espaçamento para planificação.

```json
{
  "part_spacing": 2.0,
  "board_margin": 10.0,
  "board_spacing": 50.0,
  "material_spacing": 200.0
}
```

#### stamp_config.json
Configurações de carimbos.

---

## 💻 Requisitos

### Sistema

- **SketchUp**: Versão 2017 ou superior
- **Ruby**: 2.0+ (incluído no SketchUp)
- **Sistema Operacional**:
  - Windows 7/8/10/11
  - macOS 10.12+

### Dependências

- `sketchup.rb` - API nativa (✅ incluída)
- `json` - Manipulação de JSON (✅ incluída)
- `base64` - Codificação (✅ incluída)

**Sem dependências externas!**

---

## 🏗️ Estrutura do Projeto

```
rj_mockup_tools/
├── rj_mockup_tools.rb          # Loader/Registrador
├── rj_mockup_tools/
│   ├── main.rb                 # Arquivo principal
│   ├── lib/                    # Módulos Ruby (38 arquivos)
│   │   ├── version.rb          # Versionamento centralizado
│   │   ├── logger.rb           # Sistema de logging
│   │   ├── cache.rb            # Sistema de cache
│   │   ├── json_utils.rb       # Utilitários JSON
│   │   ├── face_to_board_improved.rb
│   │   ├── material_manager_tool.rb
│   │   ├── laser_engraving.rb
│   │   ├── planifier.rb
│   │   └── ...
│   ├── html/                   # Interfaces HTML (9 arquivos)
│   │   ├── selector_dialog.html
│   │   ├── property_editor.html
│   │   └── ...
│   ├── data/                   # Configurações JSON (6 arquivos)
│   │   ├── materiais.json
│   │   ├── combinations.json
│   │   └── ...
│   ├── icons/                  # Ícones (80+ PNG)
│   └── resources/              # Recursos adicionais
├── API.md                      # Documentação da API
└── README.md                   # Este arquivo
```

---

## 🤝 Contribuindo

### Reportar Bugs

Encontrou um bug? Abra uma issue com:
- Descrição do problema
- Passos para reproduzir
- Versão do SketchUp
- Sistema operacional

### Sugerir Melhorias

Tem uma ideia? Abra uma issue com:
- Descrição da funcionalidade
- Casos de uso
- Exemplos (se possível)

---

## 📜 Licença

Copyright © 2025, Roberto Jackson Vieira
Todos os direitos reservados.

---

## 👤 Autor

**Roberto Jackson Vieira**

---

## 🙏 Agradecimentos

- Comunidade SketchUp
- Contribuidores do projeto
- Beta testers

---

## 📊 Estatísticas do Projeto

- **Versão**: 3.0.3
- **Arquivos Ruby**: 38 módulos
- **Linhas de Código**: ~15.000
- **Interfaces HTML**: 9
- **Materiais Pré-configurados**: 13
- **Ícones**: 80+
- **Tamanho**: ~2.1 MB

---

## 🔄 Atualizações Recentes (3.0.3)

### ✅ Melhorias Implementadas

- ✅ Versionamento centralizado
- ✅ Sistema de logging estruturado
- ✅ Cache com TTL para performance
- ✅ Validação de JSON
- ✅ Código reformatado (PropertyManager)
- ✅ Precisão de floats corrigida em JSON
- ✅ Documentação completa da API

### 🗑️ Limpeza de Código

- Removidos arquivos obsoletos (`face_to_board.rb`, `reset_ucs.rb`)
- Removida pasta `ref/` com código de desenvolvimento
- Código minificado reformatado

---

## 📞 Suporte

Para suporte técnico ou dúvidas:

- **Email**: (adicionar email)
- **Issues**: GitHub Issues
- **Documentação**: API.md

---

**🚀 Mockup Tools RJV v3.0.3 - Ferramentas Profissionais para SketchUp**
