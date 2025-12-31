local function update()
  local node = window.getDatabaseNode()
  if not node then return end
  self.setTooltipText(DB.getValue(node, "difficultytooltip", ""))
end

function onInit()
  local node = window.getDatabaseNode()
  if node then
    DB.addHandler(DB.getPath(node) .. ".difficultytooltip", "onUpdate", update)
  end
  update()
end

function onClose()
  local node = window.getDatabaseNode()
  if node then
    DB.removeHandler(DB.getPath(node) .. ".difficultytooltip", "onUpdate", update)
  end
end
