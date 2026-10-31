-- PAC-MAZE para o console Lupi (labirinto com fantasmas, 1 jogador).
-- Os modulos pm_core, pm_app e pm_view sao Lua puro, iguais aos da versao do computador.
-- Este arquivo e so o "adaptador" da SDK: desenho (ui.*), botoes (ui.btn) e paleta DB32.
-- Se algo falhar, o erro aparece na TELA (em vez de tela preta).
require "palette"
require "sprites"

local W, H = 480, 270
local floor = math.floor
local App, View, app          -- carregados no primeiro quadro, dentro de pcall
local crashed, ready = nil, false
local safe = pcall or function(f, ...) return true, f(...) end

-- ================================================================ BOTOES (EDITE AQUI)
-- Nomes do SEU console (descobertos com o teste de botoes):
--   cruzeta: UP DOWN LEFT RIGHT | acao: BTN_Z BTN_X BTN_F BTN_G | L=BTN_Q R=BTN_E | START=ZOOM_2X
-- Cada acao aceita VARIOS botoes (basta apertar um). Se a constante nao existir, so aquele botao some.
local NAMES = { "up", "left", "down", "right", "ok", "pause" }
local MAP = {
  up    = { function() return UP end },
  left  = { function() return LEFT end },
  down  = { function() return DOWN end },
  right = { function() return RIGHT end },
  ok    = { function() return BTN_Z end, function() return BTN_X end },     -- Z ou X: iniciar / voltar
  pause = { function() return ZOOM_2X end, function() return BTN_G end },   -- START (ou G): pausar
}
local map = {}

local function resolve_buttons()
  for i = 1, #NAMES do
    local n = NAMES[i]
    local list = {}
    for k = 1, #MAP[n] do
      local ok, v = safe(MAP[n][k])
      if ok and type(v) == "number" then list[#list + 1] = v end
    end
    map[n] = list
  end
end

local held, prev = {}, {}
local function read_buttons()
  for i = 1, #NAMES do
    local n = NAMES[i]
    local list, on = map[n], false
    for k = 1, #list do
      local r = ui.btn(list[k])
      if r ~= nil and r ~= false and r ~= 0 then on = true end
    end
    held[n] = on
  end
end
local function pressed(name)
  local now = held[name]
  local p = now and not prev[name]
  prev[name] = now
  return p
end

-- ================================================================ CORES (paleta DB32)
local DB32 = {
  0x000000, 0x222034, 0x45283c, 0x663931, 0x8f563b, 0xdf7126, 0xd9a066, 0xeec39a,
  0xfbf236, 0x99e550, 0x6abe30, 0x37946e, 0x4b692f, 0x524b24, 0x323c39, 0x3f3f74,
  0x306082, 0x5b6ee1, 0x639bff, 0x5fcde4, 0xcbdbfc, 0xffffff, 0x9badb7, 0x847e87,
  0x696a6a, 0x595652, 0x76428a, 0xac3232, 0xd95763, 0xd77bba, 0x8f974a, 0x8a6f30,
}
local DR, DG, DB = {}, {}, {}
for i = 1, #DB32 do
  local c = DB32[i]
  DR[i], DG[i], DB[i] = floor(c / 65536), floor(c / 256) % 256, c % 256
end
local cache, ncache = {}, 0
local function color(rgb)
  local idx = cache[rgb]
  if idx then return idx end
  local r, g, b = floor(rgb / 65536), floor(rgb / 256) % 256, rgb % 256
  local best, bestd = 1, 1e9
  for i = 1, #DB32 do
    local dr, dg, db = r - DR[i], g - DG[i], b - DB[i]
    local d = dr * dr + dg * dg + db * db
    if d < bestd then best, bestd = i, d end
  end
  idx = Palette.hex(DB32[best])
  if ncache >= 1500 then cache, ncache = {}, 0 end
  cache[rgb] = idx
  ncache = ncache + 1
  return idx
end

-- ================================================================ DESENHO
-- ui.rect/rectfill recebem os dois cantos (inclusivos). Retangulos que saem da tela sao cortados aqui.
local gfx = {
  clear = function(rgb) ui.cls(color(rgb)) end,
  fill = function(x, y, w, h, rgb)
    local x1, y1 = x + w - 1, y + h - 1
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end
    if x1 > W - 1 then x1 = W - 1 end
    if y1 > H - 1 then y1 = H - 1 end
    if x1 >= x and y1 >= y then ui.rectfill(x, y, x1, y1, color(rgb)) end
  end,
  box = function(x, y, w, h, rgb)
    if w > 0 and h > 0 then ui.rect(x, y, x + w - 1, y + h - 1, color(rgb)) end
  end,
  text = function(s, x, y, rgb) ui.print(s, x, y, color(rgb)) end,
}

local RED, WHITE, DIM = 0xd95763, 0xffffff, 0x9badb7
local function draw_error(msg)
  gfx.clear(0x000000)
  gfx.text("PAC-MAZE - ERRO", 12, 12, RED)
  gfx.text("COPIE ESTA MENSAGEM E MANDE PARA O ASSISTENTE:", 12, 26, DIM)
  local done = safe(function()
    local y, i, n = 44, 1, #msg
    while i <= n and y < 250 do
      local j = i + 55
      if j > n then j = n end
      gfx.text(msg:sub(i, j), 12, y, WHITE)
      y, i = y + 10, j + 1
    end
  end)
  if not done then ui.print(msg, 12, 44, color(WHITE)) end
end

-- ================================================================ LOOP
local function boot()
  App, View = require("pm_app"), require("pm_view")
  resolve_buttons()
  View.lite = true                                     -- menos chamadas de desenho por quadro
  View.title_lines = {
    { "SETAS: MOVER   START: PAUSAR", 150 },
    { "COMA OS PONTOS E FUJA DOS FANTASMAS", 162 },
    { "Z: INICIAR", 232, "blink" },
  }
  app = App.new()
  ready = true
end

local hold = { up = false, left = false, down = false, right = false }
local function step(frame)
  read_buttons()
  local z, st = pressed("ok"), pressed("pause")
  pressed("up"); pressed("left"); pressed("down"); pressed("right")
  if z then app:ok(frame) end
  if st then app:pause() end
  hold.up, hold.left, hold.down, hold.right = held.up, held.left, held.down, held.right
  app:update(hold)
  View.draw(app, gfx, frame)
end

function loop(frame)
  for i = 1, #Palette do ui.palset(i - 1, Palette[i]) end
  ui.clip(0, 0, W, H)
  ui.camera(0, 0)
  if crashed then draw_error(crashed); return end
  local ok, err
  if not ready then
    ok, err = safe(boot)
    if not ok then crashed = tostring(err); draw_error(crashed); return end
  end
  ok, err = safe(step, frame)
  if not ok then crashed = tostring(err); draw_error(crashed) end
end
