-- pm_view.lua : desenha o PAC-MAZE (tela 480x270). Usa so gfx: clear, fill, box, text.
-- Labirinto 28x31 tiles de 8 px (224x248), centralizado. Cores 0xRRGGBB da paleta DB32.
local Pac = require("pm_core")
local View = {}
View.W, View.H, View.CHAR_W = 480, 270, 8
View.lite = false      -- modo leve (console): paredes lisas, sem relevo
-- linhas do titulo: { texto, y [, "blink"] }. O console troca estas linhas.
View.title_lines = {
  { "SETAS OU WASD: MOVER", 150 },
  { "P: PAUSAR     ESC: SAIR", 162 },
  { "Z: INICIAR", 232, "blink" },
}

local OX, OY = 128, 11
local U = Pac.U
local COLS, ROWS = Pac.COLS, Pac.ROWS
local floor, abs = math.floor, math.abs

local C = {
  black = 0x000000, wall = 0x306082, wallhi = 0x5b6ee1, dot = 0xeec39a, pac = 0xfbf236,
  white = 0xffffff, dim = 0x9badb7, gold = 0xfbf236, red = 0xd95763, pink = 0xd77bba,
  cyan = 0x5fcde4, orange = 0xdf7126, fright = 0x5b6ee1, ink = 0x222034, green = 0x6abe30,
  pupil = 0x3f3f74, brown = 0x8f563b,
}
local GCOL = { C.red, C.pink, C.cyan, C.orange }

local function center(gfx, s, y, c) gfx.text(s, floor((View.W - #s * View.CHAR_W) / 2), y, c) end
local function pad(n, w)
  local s = tostring(n)
  while #s < w do s = "0" .. s end
  return s
end

-- ---------------------------------------------------------------- paredes (retangulos unidos)
local rects
local function build_rects()
  rects = {}
  local used = {}
  for ty = 0, ROWS - 1 do
    for tx = 0, COLS - 1 do
      local i = ty * COLS + tx + 1
      if Pac.wall_at(tx, ty) and not used[i] then
        local w = 1
        while tx + w < COLS and Pac.wall_at(tx + w, ty) and not used[ty * COLS + tx + w + 1] do w = w + 1 end
        local h, ok = 1, true
        while ok and ty + h < ROWS do
          for k = 0, w - 1 do
            if not Pac.wall_at(tx + k, ty + h) or used[(ty + h) * COLS + tx + k + 1] then ok = false; break end
          end
          if ok then h = h + 1 end
        end
        for yy = 0, h - 1 do
          for xx = 0, w - 1 do used[(ty + yy) * COLS + tx + xx + 1] = true end
        end
        rects[#rects + 1] = { tx * 8, ty * 8, w * 8, h * 8 }
      end
    end
  end
end
View.wall_rects = function() if not rects then build_rects() end return #rects end

local function draw_walls(gfx, flash)
  if not rects then build_rects() end
  local col = flash and C.white or C.wall
  for i = 1, #rects do
    local r = rects[i]
    gfx.fill(OX + r[1], OY + r[2], r[3], r[4], col)
    if not View.lite and not flash and r[3] > 2 and r[4] > 2 then
      gfx.fill(OX + r[1] + 1, OY + r[2] + 1, r[3] - 2, r[4] - 2, C.ink)   -- miolo escuro: parede "vazada"
    end
  end
end

-- ---------------------------------------------------------------- pac-man (disco com boca)
local HW6 = { [0] = 6, 6, 6, 5, 5, 4, 2 }
local HW4 = { [0] = 4, 4, 4, 3, 2 }
-- dir: 1 cima, 2 esquerda, 3 baixo, 4 direita. t = abertura da boca (0 = fechada)
local function disc(gfx, cx, cy, dir, t, R, col)
  local hwt = (R == 6) and HW6 or HW4
  for v = -R, R do
    local hw = hwt[abs(v)]
    local u1 = hw
    local front = hw
    if t > 0 then front = floor(abs(v) / t); if front > hw then front = hw end end
    -- parte de tras: u de -hw a 0; parte da frente: u de 1 a front (se houver)
    local segs = { { -hw, (t > 0) and 0 or hw } }
    if t > 0 and front >= 1 then segs[2] = { 1, front } end
    for k = 1, #segs do
      local a, b = segs[k][1], segs[k][2]
      local len = b - a + 1
      if dir == 4 then gfx.fill(cx + a, cy + v, len, 1, col)
      elseif dir == 2 then gfx.fill(cx - b, cy + v, len, 1, col)
      elseif dir == 3 then gfx.fill(cx + v, cy + a, 1, len, col)
      else gfx.fill(cx + v, cy - b, 1, len, col) end
    end
  end
end

local MOUTH = { 1.6, 0.7, 0, 0.7 }
local DEATH = { 1.0, 2.0, 4.0, 8.0, 16.0, 40.0, 200.0 }

local function draw_pac(gfx, g)
  local p = g.pac
  local cx, cy = OX + floor(p.x / 16), OY + floor(p.y / 16)
  if g.state == "dying" then
    local k = 120 - g.timer
    if k < 30 then disc(gfx, cx, cy, 1, 0.7, 6, C.pac)
    elseif k < 100 then
      local stage = floor((k - 30) / 10) + 1
      if stage <= #DEATH then disc(gfx, cx, cy, 1, DEATH[stage], 6, C.pac)
      else
        for i = 1, 4 do   -- pequena explosao
          local dx, dy = (i % 2 == 0) and 6 or -6, (i > 2) and 6 or -6
          gfx.fill(cx + dx - 1, cy + dy - 1, 2, 2, C.pac)
        end
      end
    end
    return
  end
  local t = 0.7
  if p.moved and g.state == "play" then t = MOUTH[floor(g.t / 3) % 4 + 1] end
  disc(gfx, cx, cy, (p.dir ~= 0) and p.dir or 2, t, 6, C.pac)
end

-- ---------------------------------------------------------------- fantasmas
local function eyes(gfx, cx, cy, dir)
  local dx, dy = Pac.DX[dir] or 0, Pac.DY[dir] or 0
  gfx.fill(cx - 5, cy - 4, 4, 5, C.white)
  gfx.fill(cx + 1, cy - 4, 4, 5, C.white)
  gfx.fill(cx - 4 + dx, cy - 3 + dy, 2, 2, C.pupil)
  gfx.fill(cx + 2 + dx, cy - 3 + dy, 2, 2, C.pupil)
end

local function draw_ghost(gfx, g, e, frame)
  local cx, cy = OX + floor(e.x / 16), OY + floor(e.y / 16)
  if e.state == "house" then cy = cy + ((floor(frame / 12) % 2 == 0) and -2 or 2) end
  if e.state == "eyes" then eyes(gfx, cx, cy, e.dir); return end
  local col = GCOL[e.id]
  if e.fright then
    col = C.fright
    if g.fright_t < 150 and floor(frame / 8) % 2 == 0 then col = C.white end
  end
  gfx.fill(cx - 4, cy - 7, 9, 1, col)
  gfx.fill(cx - 5, cy - 6, 11, 1, col)
  gfx.fill(cx - 6, cy - 5, 13, 7, col)
  gfx.fill(cx - 6, cy + 2, 13, 2, col)
  if floor(frame / 6) % 2 == 0 then
    gfx.fill(cx - 6, cy + 4, 3, 2, col); gfx.fill(cx - 1, cy + 4, 3, 2, col); gfx.fill(cx + 4, cy + 4, 3, 2, col)
  else
    gfx.fill(cx - 4, cy + 4, 3, 2, col); gfx.fill(cx + 2, cy + 4, 3, 2, col)
  end
  if e.fright then
    local face = (col == C.white) and C.red or C.white
    gfx.fill(cx - 3, cy - 3, 2, 2, face); gfx.fill(cx + 2, cy - 3, 2, 2, face)
    gfx.fill(cx - 5, cy + 1, 11, 1, face)
  else
    eyes(gfx, cx, cy, e.dir)
  end
end

-- ---------------------------------------------------------------- frutas
local FRUIT = {
  { { -5, 1, 5, 5, 0xd95763 }, { 1, 2, 5, 5, 0xd95763 }, { -1, -5, 1, 6, 0x6abe30 }, { 3, -4, 1, 6, 0x6abe30 } },       -- cereja
  { { -4, -3, 9, 8, 0xd95763 }, { -2, 5, 5, 2, 0xd95763 }, { -3, -5, 7, 2, 0x6abe30 } },                              -- morango
  { { -5, -4, 11, 10, 0xdf7126 }, { -1, -6, 3, 2, 0x6abe30 } },                                                       -- laranja
  { { -5, -4, 11, 10, 0xac3232 }, { -1, -6, 2, 3, 0x8f563b } },                                                       -- maca
  { { -6, -4, 13, 10, 0x6abe30 }, { -2, -4, 2, 10, 0x99e550 }, { 2, -4, 2, 10, 0x99e550 } },                          -- melao
  { { -5, -5, 11, 4, 0xfbf236 }, { -1, -1, 3, 7, 0x5b6ee1 }, { -6, -4, 2, 3, 0xd95763 } },                            -- nave
  { { -4, -5, 9, 8, 0xfbf236 }, { -6, 3, 13, 2, 0xfbf236 }, { -1, 5, 3, 2, 0xdf7126 } },                              -- sino
  { { -3, -6, 7, 5, 0xcbdbfc }, { -1, -1, 2, 8, 0xcbdbfc }, { 1, 3, 3, 1, 0xcbdbfc }, { 1, 5, 3, 1, 0xcbdbfc } },     -- chave
}
local function draw_fruit(gfx, kind, cx, cy)
  local f = FRUIT[(kind > #FRUIT) and #FRUIT or kind]
  for i = 1, #f do gfx.fill(cx + f[i][1], cy + f[i][2], f[i][3], f[i][4], f[i][5]) end
end

-- ---------------------------------------------------------------- jogo
local function draw_game(gfx, g, frame)
  draw_walls(gfx, g.state == "win" and floor(g.timer / 12) % 2 == 0)
  gfx.fill(OX + 13 * 8, OY + 12 * 8 + 3, 16, 2, C.pink)                -- porta da casa
  local blink = floor(frame / 15) % 2 == 0
  if g.state ~= "win" or g.timer > 100 then
    for ty = 0, ROWS - 1 do
      for tx = 0, COLS - 1 do
        local v = g.dot[ty * COLS + tx + 1]
        if v == 1 then
          gfx.fill(OX + tx * 8 + 3, OY + ty * 8 + 3, 2, 2, C.dot)
        elseif v == 2 and blink then
          gfx.fill(OX + tx * 8 + 1, OY + ty * 8 + 1, 6, 6, C.dot)
        end
      end
    end
  end
  if g.fruit then
    draw_fruit(gfx, (g.level > 8) and 8 or g.level, OX + floor(g.fruit.x / 16), OY + floor(g.fruit.y / 16))
  end
  if g.state == "dying" and 120 - g.timer >= 30 then
    draw_pac(gfx, g)                          -- so o pac aparece na animacao de morte
  elseif g.state ~= "win" or g.timer > 60 then
    for i = 1, 4 do draw_ghost(gfx, g, g.ghosts[i], frame) end
    draw_pac(gfx, g)
  else
    draw_pac(gfx, g)
  end
  if g.pop then
    local s = tostring(g.pop.val)
    gfx.text(s, OX + floor(g.pop.x / 16) - floor(#s * 4), OY + floor(g.pop.y / 16) - 4, C.cyan)
  end
  local msg_x
  if g.state == "ready" then
    gfx.text("READY!", OX + 112 - 24, OY + 17 * 8 + 1, C.gold)
  elseif g.state == "gameover" then
    gfx.text("GAME OVER", OX + 112 - 36, OY + 17 * 8 + 1, C.red)
  end
end

local function draw_hud(gfx, g, app, frame)
  gfx.text("PONTOS", 8, 24, C.dim)
  gfx.text(pad(g.score, 6), 8, 36, C.white)
  gfx.text("FASE", 8, 62, C.dim)
  gfx.text(tostring(g.level), 8, 74, C.white)
  gfx.text("RECORDE", 360, 24, C.dim)
  local hi = (app.high > g.score) and app.high or g.score
  gfx.text(pad(hi, 6), 360, 36, C.white)
  for i = 1, g.lives - 1 do disc(gfx, 14 + (i - 1) * 14, 238, 2, 0.7, 4, C.pac) end
  local first = (g.level > 7) and (g.level - 6) or 1
  for lv = first, g.level do
    draw_fruit(gfx, (lv > 8) and 8 or lv, 464 - (g.level - lv) * 16, 238)
  end
end

-- ---------------------------------------------------------------- titulo
local function draw_title(gfx, app, frame)
  gfx.box(8, 8, View.W - 16, View.H - 16, 0x595652)
  center(gfx, "PAC-MAZE", 34, C.gold)
  center(gfx, "LABIRINTO COM FANTASMAS", 48, C.dim)
  -- animacao: os fantasmas perseguem o pac; depois ele os persegue
  local ph = frame % 720
  local y = 100
  local fake = { fright_t = 0 }
  if ph < 360 then
    local x = -20 + floor(ph * 1.45)
    for i = 1, 4 do
      draw_ghost(gfx, { fright_t = 999 }, { id = i, x = (x - 26 * i) * 16 - OX * 16, y = (y - OY) * 16, dir = 4, state = "normal", fright = false }, frame)
    end
    disc(gfx, x, y, 4, MOUTH[floor(frame / 3) % 4 + 1], 6, C.pac)
  else
    local x = 500 - floor((ph - 360) * 1.45)
    for i = 1, 4 do
      draw_ghost(gfx, { fright_t = 999 }, { id = i, x = (x - 26 * i) * 16 - OX * 16, y = (y - OY) * 16, dir = 2, state = "normal", fright = true }, frame)
    end
    disc(gfx, x, y, 2, MOUTH[floor(frame / 3) % 4 + 1], 6, C.pac)
  end
  if app.high > 0 then center(gfx, "RECORDE " .. pad(app.high, 6), 124, C.white) end
  for i = 1, #View.title_lines do
    local l = View.title_lines[i]
    if l[3] == "blink" then
      if floor(frame / 30) % 2 == 0 then center(gfx, l[1], l[2], C.gold) end
    else
      center(gfx, l[1], l[2], C.dim)
    end
  end
  for i = 1, 8 do draw_fruit(gfx, i, 100 + (i - 1) * 40, 200) end
end

function View.draw(app, gfx, frame)
  gfx.clear(C.black)
  if app.screen == "title" then draw_title(gfx, app, frame); return end
  local g = app.game
  draw_game(gfx, g, frame)
  draw_hud(gfx, g, app, frame)
  if app.paused then
    gfx.fill(176, 100, 128, 44, C.ink)
    gfx.box(176, 100, 128, 44, C.gold)
    center(gfx, "PAUSADO", 116, C.gold)
  elseif g.state == "gameover" and g.timer >= 90 and floor(frame / 30) % 2 == 0 then
    center(gfx, View.back_hint or "Z: VOLTAR AO TITULO", 256, C.gold)
  end
end

return View
