-- pm_app.lua : telas (titulo -> jogo -> game over). Sem LOVE.
local Pac = require("pm_core")
local App = {}
App.__index = App

function App.new()
  return setmetatable({ screen = "title", game = nil, high = 0, paused = false }, App)
end

-- botao de confirmar: titulo -> jogo; fim de jogo -> titulo
function App:ok(frame)
  if self.screen == "title" then
    self.game = Pac.new({ seed = (frame or 1) * 7919 + 13 })
    self.screen, self.paused = "play", false
  elseif self.screen == "play" and self.game.state == "gameover" and self.game.timer >= 90 then
    if self.game.score > self.high then self.high = self.game.score end
    self.screen, self.game = "title", nil
  end
end

function App:pause()
  if self.screen == "play" and self.game.state ~= "gameover" then self.paused = not self.paused end
end

-- h = {up,left,down,right} (botoes segurados)
function App:update(h)
  if self.screen == "play" and not self.paused then
    self.game:update(h)
    if self.game.score > self.high then self.high = self.game.score end
  end
end

return App
