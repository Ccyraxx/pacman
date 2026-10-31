-- pm_core.lua : regras do PAC-MAZE (estilo Pac-Man). Lua puro (5.1+): nao conhece LOVE nem tela.
-- Sem math.random (gerador proprio). Tudo em quadros (60 por segundo).
-- Posicoes em "unidades": 1 tile = 128 unidades = 8 pixels (16 unidades por pixel).
-- O centro do tile (tx,ty) e (tx*128+64, ty*128+64). Os personagens andam de centro em centro.
local Pac = {}
Pac.__index = Pac

local COLS, ROWS, U = 28, 31, 128
Pac.COLS, Pac.ROWS, Pac.U = COLS, ROWS, U
local floor = math.floor

-- # parede   - porta da casa dos fantasmas   . ponto   o pastilha de poder   (espaco) vazio
Pac.MAZE = {
  "############################",
  "#............##............#",
  "#.####.#####.##.#####.####.#",
  "#o####.#####.##.#####.####o#",
  "#.####.#####.##.#####.####.#",
  "#..........................#",
  "#.####.##.########.##.####.#",
  "#.####.##.########.##.####.#",
  "#......##....##....##......#",
  "######.##### ## #####.######",
  "######.##### ## #####.######",
  "######.##          ##.######",
  "######.## ###--### ##.######",
  "######.## #      # ##.######",
  "      .   #      #   .      ",
  "######.## #      # ##.######",
  "######.## ######## ##.######",
  "######.##          ##.######",
  "######.## ######## ##.######",
  "######.## ######## ##.######",
  "#............##............#",
  "#.####.#####.##.#####.####.#",
  "#.####.#####.##.#####.####.#",
  "#o..##.......  .......##..o#",
  "###.##.##.########.##.##.###",
  "###.##.##.########.##.##.###",
  "#......##....##....##......#",
  "#.##########.##.##########.#",
  "#.##########.##.##########.#",
  "#..........................#",
  "############################",
}

-- mapa estatico (so parede/porta/vazio) e posicao inicial dos pontos
local WALL, DOTS0, NDOTS = {}, {}, 0
for ty = 0, ROWS - 1 do
  local row = Pac.MAZE[ty + 1]
  for tx = 0, COLS - 1 do
    local c = row:sub(tx + 1, tx + 1)
    local i = ty * COLS + tx + 1
    if c == "#" or c == "-" then WALL[i] = c else WALL[i] = " " end
    DOTS0[i] = (c == ".") and 1 or ((c == "o") and 2 or 0)
    if DOTS0[i] > 0 then NDOTS = NDOTS + 1 end
  end
end
Pac.NDOTS = NDOTS

local function chr(tx, ty)
  if ty == 14 and (tx == -1 or tx == COLS) then return " " end      -- tuneis (tiles virtuais)
  if tx < 0 or tx >= COLS or ty < 0 or ty >= ROWS then return "#" end
  return WALL[ty * COLS + tx + 1]
end
function Pac.wall_at(tx, ty) return chr(tx, ty) == "#" end
function Pac.door_at(tx, ty) return chr(tx, ty) == "-" end

local function can_pac(tx, ty) local c = chr(tx, ty); return c ~= "#" and c ~= "-" end
local function can_ghost(tx, ty, door) local c = chr(tx, ty); return c ~= "#" and (c ~= "-" or door) end
Pac.can_pac = can_pac

-- direcoes: 1 cima, 2 esquerda, 3 baixo, 4 direita (ordem de desempate dos fantasmas)
local DX = { 0, -1, 0, 1 }
local DY = { -1, 0, 1, 0 }
Pac.DX, Pac.DY = DX, DY
local function opp(d) return (d + 1) % 4 + 1 end
local DIRKEY = { "up", "left", "down", "right" }

-- cruzamentos onde os fantasmas nao viram para cima (como no original)
local NOUP = {}
for _, t in ipairs({ { 12, 11 }, { 15, 11 }, { 12, 23 }, { 15, 23 } }) do NOUP[t[2] * COLS + t[1] + 1] = true end

-- cantos de dispersao (fora do mapa, como no original)
local SCATTER = { { 25, -3 }, { 2, -3 }, { 27, 34 }, { 0, 34 } }

-- ---------------------------------------------------------------- dificuldade por fase
local FRIGHT = { 360, 300, 240, 180, 120, 300, 120, 120, 60, 300, 120, 60, 60, 180, 60, 60, 0, 60 }
local FRUITS = { 100, 300, 500, 500, 700, 700, 1000, 1000, 2000, 2000, 3000, 3000, 5000 }
Pac.FRUITS = FRUITS

local function params(level)
  local p = {}
  if level == 1 then p.pac, p.pacf, p.gh, p.fr, p.tn = 16, 18, 15, 10, 8
  elseif level <= 4 then p.pac, p.pacf, p.gh, p.fr, p.tn = 18, 19, 17, 11, 9
  elseif level <= 20 then p.pac, p.pacf, p.gh, p.fr, p.tn = 20, 20, 19, 12, 10
  else p.pac, p.pacf, p.gh, p.fr, p.tn = 18, 18, 19, 12, 10 end
  p.fright = FRIGHT[level] or 0
  if level == 1 then p.elroy1 = 20 elseif level == 2 then p.elroy1 = 30
  elseif level <= 5 then p.elroy1 = 40 elseif level <= 8 then p.elroy1 = 50
  elseif level <= 11 then p.elroy1 = 60 elseif level <= 14 then p.elroy1 = 80
  elseif level <= 18 then p.elroy1 = 100 else p.elroy1 = 120 end
  p.elroy2 = floor(p.elroy1 / 2)
  if level == 1 then p.modes = { 420, 1200, 420, 1200, 300, 1200, 300 }
  elseif level <= 4 then p.modes = { 420, 1200, 420, 1200, 300, 61980, 1 }
  else p.modes = { 300, 1200, 300, 1200, 300, 62220, 1 } end
  -- pontos que o pac precisa comer para soltar cada fantasma da casa (rosa, ciano, laranja)
  p.limit = { [2] = 0, [3] = (level == 1) and 30 or 0, [4] = (level == 1) and 60 or ((level == 2) and 50 or 0) }
  p.idle = (level < 5) and 240 or 180
  return p
end

-- ---------------------------------------------------------------- criacao
-- Park-Miller (seguro em Lua 5.1)
function Pac:rnd(n)
  self.seed = (self.seed * 16807) % 2147483647
  return self.seed % n
end

local function newg(id, tx, ty, state, dir)
  return { id = id, x = tx * U + 64, y = ty * U + 64, dir = dir or 0, state = state,
           fright = false, inside = false, cnt = 0, moved = false }
end

function Pac:reset_positions(delay)
  local p = self.pac
  p.x, p.y, p.dir, p.want, p.moved = 13 * U + 64, 23 * U + 64, 2, 0, false
  self.ghosts = {
    newg(1, 13, 11, "normal", 2),    -- vermelho (ja fora da casa)
    newg(2, 13, 14, "house"),        -- rosa
    newg(3, 11, 14, "house"),        -- ciano
    newg(4, 16, 14, "house"),        -- laranja
  }
  self.mode, self.mode_i, self.mode_t = "scatter", 1, 0
  self.fright_t, self.combo, self.idle = 0, 0, 0
  self.fruit, self.pop, self.freeze = nil, nil, 0
  self.state, self.timer = "ready", delay or 120
  self.pdir = 0
  self.prevh = { false, false, false, false }
end

function Pac:new_level()
  self.par = params(self.level)
  self.dot = {}
  for i = 1, COLS * ROWS do self.dot[i] = DOTS0[i] end
  self.dots_left, self.eaten = NDOTS, 0
  self:reset_positions(180)
end

-- opts: level, god (nao morre: so para testes), seed
function Pac.new(opts)
  opts = opts or {}
  local g = setmetatable({}, Pac)
  g.seed = (floor(opts.seed or 1) % 2147483646) + 1
  g.score, g.lives, g.level, g.extra = 0, 3, opts.level or 1, false
  g.god = opts.god and true or false
  g.t = 0
  g.pac = { x = 0, y = 0, dir = 2, want = 0, moved = false }
  g:new_level()
  return g
end

-- ---------------------------------------------------------------- movimento
-- anda `s` unidades, parando em cada centro de tile para decidir a direcao.
function Pac:advance(e, s, decide, on_center)
  e.moved = false
  while s > 0 do
    if e.x % U == 64 and e.y % U == 64 then
      if not decide(self, e) then return end
    end
    local dir, d = e.dir, 0
    if dir == 1 or dir == 3 then
      local r = (e.y - 64) % U
      if dir == 1 then d = (r == 0) and U or r else d = U - r end
    else
      local r = (e.x - 64) % U
      if dir == 2 then d = (r == 0) and U or r else d = U - r end
    end
    local m = (s < d) and s or d
    e.x, e.y = e.x + DX[dir] * m, e.y + DY[dir] * m
    s = s - m
    e.moved = true
    if e.x % U == 64 and e.y % U == 64 then
      local tx = floor(e.x / U)
      if tx == -1 then e.x = COLS * U + 64 elseif tx == COLS then e.x = -64 end   -- tunel
      if on_center then on_center(self, e) end
    end
  end
end

local function decide_pac(self, e)
  local tx, ty = floor(e.x / U), floor(e.y / U)
  if e.want ~= 0 and can_pac(tx + DX[e.want], ty + DY[e.want]) then e.dir = e.want end
  if e.dir == 0 then return false end
  return can_pac(tx + DX[e.dir], ty + DY[e.dir])
end

-- alvo do fantasma no modo perseguir/dispersar
function Pac:target(e)
  local p = self.pac
  local ptx, pty = floor(p.x / U), floor(p.y / U)
  local pd = (p.dir ~= 0) and p.dir or 2
  local id = e.id
  local etx, ety = floor(e.x / U), floor(e.y / U)
  local scatter = (self.mode == "scatter")
  if id == 1 and self.dots_left <= self.par.elroy1 then scatter = false end   -- "Elroy" persegue sempre
  if scatter then return SCATTER[id][1], SCATTER[id][2] end
  if id == 1 then return ptx, pty end
  if id == 2 then
    local ax, ay = ptx + 4 * DX[pd], pty + 4 * DY[pd]
    if pd == 1 then ax = ax - 4 end                                    -- "bug" do original (cima)
    return ax, ay
  end
  if id == 3 then
    local ax, ay = ptx + 2 * DX[pd], pty + 2 * DY[pd]
    if pd == 1 then ax = ax - 2 end
    local red = self.ghosts[1]
    local rx, ry = floor(red.x / U), floor(red.y / U)
    return rx + 2 * (ax - rx), ry + 2 * (ay - ry)
  end
  local dx, dy = etx - ptx, ety - pty
  if dx * dx + dy * dy >= 64 then return ptx, pty end
  return SCATTER[4][1], SCATTER[4][2]
end

local function decide_ghost(self, e)
  local tx, ty = floor(e.x / U), floor(e.y / U)
  local st = e.state
  if st == "house" then return false end
  if st == "exit" then
    if tx == 13 and ty == 11 then            -- saiu da casa
      e.state, e.dir = "normal", 2
      return true
    end
    if tx ~= 13 then e.dir = (tx < 13) and 4 or 2 else e.dir = 1 end
    return true
  end
  if st == "eyes" then
    if e.inside then
      if tx == 13 and ty == 14 then          -- chegou: renasce
        e.inside, e.state, e.fright, e.dir = false, "exit", false, 1
      else
        e.dir = 3
      end
      return true
    end
    if tx == 13 and ty == 11 then e.inside, e.dir = true, 3; return true end
    local best, bd = 0, 1e18
    local back = (e.dir ~= 0) and opp(e.dir) or 0
    for d = 1, 4 do
      if d ~= back then
        local nx, ny = tx + DX[d], ty + DY[d]
        if can_ghost(nx, ny, true) then
          local dd = (nx - 13) * (nx - 13) + (ny - 11) * (ny - 11)
          if dd < bd then best, bd = d, dd end
        end
      end
    end
    if best == 0 then best = back end
    e.dir = best
    return true
  end
  -- normal ou assustado
  local back = (e.dir ~= 0) and opp(e.dir) or 0
  local noup = NOUP[ty * COLS + tx + 1] and not e.fright
  local n = 0
  for d = 1, 4 do
    if d ~= back and can_ghost(tx + DX[d], ty + DY[d], false) and not (d == 1 and noup) then n = n + 1 end
  end
  if n == 0 then
    e.dir = (back ~= 0) and back or 2
    return true
  end
  if e.fright then
    local pick = self:rnd(n)
    for d = 1, 4 do
      if d ~= back and can_ghost(tx + DX[d], ty + DY[d], false) and not (d == 1 and noup) then
        if pick == 0 then e.dir = d; return true end
        pick = pick - 1
      end
    end
  end
  local gx, gy = self:target(e)
  local best, bd = 0, 1e18
  for d = 1, 4 do
    if d ~= back and can_ghost(tx + DX[d], ty + DY[d], false) and not (d == 1 and noup) then
      local nx, ny = tx + DX[d] - gx, ty + DY[d] - gy
      local dd = nx * nx + ny * ny
      if dd < bd then best, bd = d, dd end
    end
  end
  e.dir = best
  return true
end

-- ---------------------------------------------------------------- eventos
function Pac:add_score(n)
  self.score = self.score + n
  if not self.extra and self.score >= 10000 then self.extra, self.lives = true, self.lives + 1 end
end

function Pac:release(i)
  local e = self.ghosts[i]
  if e.state == "house" then e.state, e.dir = "exit", 0 end
end

function Pac:release_first()
  for i = 2, 4 do
    if self.ghosts[i].state == "house" then self:release(i); return end
  end
end

function Pac:start_fright()
  self.combo = 0
  if self.par.fright <= 0 then return end
  self.fright_t = self.par.fright
  for i = 1, 4 do
    local e = self.ghosts[i]
    if e.state ~= "eyes" then
      e.fright = true
      if e.state == "normal" and e.dir ~= 0 then e.dir = opp(e.dir) end
    end
  end
end

local function on_center_pac(self, e)
  local tx, ty = floor(e.x / U), floor(e.y / U)
  local i = ty * COLS + tx + 1
  local v = self.dot[i]
  if v and v > 0 then
    self.dot[i] = 0
    self.dots_left, self.eaten, self.idle = self.dots_left - 1, self.eaten + 1, 0
    if v == 1 then self:add_score(10) else self:add_score(50); self:start_fright() end
    -- contadores da casa: o primeiro fantasma na fila conta o ponto
    for k = 2, 4 do
      local g = self.ghosts[k]
      if g.state == "house" then
        g.cnt = g.cnt + 1
        if g.cnt >= self.par.limit[k] then self:release(k) end
        break
      end
    end
    if (self.eaten == 70 or self.eaten == 170) and not self.fruit then
      self.fruit = { x = 14 * U, y = 17 * U + 64, t = 600 + self:rnd(60) }
    end
    if self.dots_left == 0 then self.state, self.timer = "win", 120 end
  end
end

local function ghost_speed(self, e)
  local par = self.par
  local tx, ty = floor(e.x / U), floor(e.y / U)
  if e.state == "eyes" then return 32 end
  if e.state == "exit" then return 10 end
  if ty == 14 and (tx <= 5 or tx >= 22) then return par.tn end
  if e.fright then return par.fr end
  local s = par.gh
  if e.id == 1 then
    if self.dots_left <= par.elroy2 then s = s + 2 elseif self.dots_left <= par.elroy1 then s = s + 1 end
  end
  return s
end

function Pac:play(h)
  if self.freeze > 0 then
    self.freeze = self.freeze - 1
    if self.pop then self.pop.t = self.pop.t - 1 end
    return
  end
  self.pop = nil
  local p = self.pac
  -- entrada: vale a direcao apertada por ultimo (enquanto segurada)
  local pd = self.pdir
  for d = 1, 4 do
    local on = h[DIRKEY[d]] and true or false
    if on and not self.prevh[d] then pd = d end
    self.prevh[d] = on
  end
  if pd ~= 0 and not h[DIRKEY[pd]] then pd = 0 end
  local want = pd
  if want == 0 then
    for d = 1, 4 do if h[DIRKEY[d]] then want = d; break end end
  end
  self.pdir, p.want = pd, want
  if want ~= 0 and p.dir ~= 0 and want == opp(p.dir) then p.dir = want end   -- vira para tras na hora

  self:advance(p, (self.fright_t > 0) and self.par.pacf or self.par.pac, decide_pac, on_center_pac)
  if self.state ~= "play" then return end                                    -- comeu o ultimo ponto

  for i = 1, 4 do
    local e = self.ghosts[i]
    local sp = ghost_speed(self, e)
    if e.state ~= "house" and sp > 0 then self:advance(e, sp, decide_ghost) end
  end

  -- colisoes
  for i = 1, 4 do
    local e = self.ghosts[i]
    if e.state ~= "house" and e.state ~= "exit" and e.state ~= "eyes" then
      local dx, dy = e.x - p.x, e.y - p.y
      if dx * dx + dy * dy < 6400 then
        if e.fright then
          local pts = 200 * (2 ^ self.combo)
          pts = floor(pts + 0.5)
          self.combo = self.combo + 1
          self:add_score(pts)
          e.state, e.fright, e.inside = "eyes", false, false
          self.pop = { x = e.x, y = e.y, val = pts, t = 45 }
          self.freeze = 45
          return
        elseif not self.god then
          self.state, self.timer = "dying", 120
          return
        end
      end
    end
  end

  -- fruta
  local f = self.fruit
  if f then
    f.t = f.t - 1
    local dx, dy = f.x - p.x, f.y - p.y
    if dx * dx + dy * dy < 6400 then
      local v = FRUITS[(self.level > #FRUITS) and #FRUITS or self.level]
      self:add_score(v)
      self.pop = { x = f.x, y = f.y, val = v, t = 60 }
      self.freeze = 30
      self.fruit = nil
    elseif f.t <= 0 then
      self.fruit = nil
    end
  end

  -- fantasmas parados na casa: solta o proximo se o pac demora a comer
  self.idle = self.idle + 1
  if self.idle >= self.par.idle then self:release_first(); self.idle = 0 end
  for k = 2, 4 do   -- limite 0 = sai logo
    local g = self.ghosts[k]
    if g.state == "house" and self.par.limit[k] == 0 then self:release(k) end
  end

  -- assustado / modos
  if self.fright_t > 0 then
    self.fright_t = self.fright_t - 1
    if self.fright_t == 0 then
      for i = 1, 4 do self.ghosts[i].fright = false end
    end
  else
    self.mode_t = self.mode_t + 1
    local lim = self.par.modes[self.mode_i]
    if lim and self.mode_t >= lim then
      self.mode_i, self.mode_t = self.mode_i + 1, 0
      self.mode = (self.mode == "scatter") and "chase" or "scatter"
      for i = 1, 4 do
        local e = self.ghosts[i]
        if e.state == "normal" and e.dir ~= 0 then e.dir = opp(e.dir) end
      end
    end
  end
end

-- h: tabela {up,left,down,right} = true/false (botoes segurados)
function Pac:update(h)
  self.t = self.t + 1
  local s = self.state
  if s == "ready" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self.state = "play" end
  elseif s == "play" then
    self:play(h or {})
  elseif s == "dying" then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.lives = self.lives - 1
      if self.lives <= 0 then
        self.state, self.timer = "gameover", 0
      else
        self:reset_positions(120)
      end
    end
  elseif s == "win" then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.level = self.level + 1
      self:new_level()
    end
  elseif s == "gameover" then
    self.timer = self.timer + 1
  end
end

return Pac
