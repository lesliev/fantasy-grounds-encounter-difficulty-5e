local XP_THRESHOLDS = {
  [1]  = {25, 50, 75, 100},
  [2]  = {50, 100, 150, 200},
  [3]  = {75, 150, 225, 400},
  [4]  = {125, 250, 375, 500},
  [5]  = {250, 500, 750, 1100},
  [6]  = {300, 600, 900, 1400},
  [7]  = {350, 750, 1100, 1700},
  [8]  = {450, 900, 1400, 2100},
  [9]  = {550, 1100, 1600, 2400},
  [10] = {600, 1200, 1900, 2800},
  [11] = {800, 1600, 2400, 3600},
  [12] = {1000, 2000, 3000, 4500},
  [13] = {1100, 2200, 3400, 5100},
  [14] = {1250, 2500, 3800, 5700},
  [15] = {1400, 2800, 4300, 6400},
  [16] = {1600, 3200, 4800, 7200},
  [17] = {2000, 3900, 5900, 8800},
  [18] = {2100, 4200, 6300, 9500},
  [19] = {2400, 4900, 7300, 10900},
  [20] = {2800, 5700, 8500, 12700},
}

local XP_BUDGET_2024 = {
  [1]  = {50, 75, 100},
  [2]  = {100, 150, 200},
  [3]  = {150, 225, 400},
  [4]  = {250, 375, 500},
  [5]  = {500, 750, 1100},
  [6]  = {600, 1000, 1400},
  [7]  = {750, 1300, 1700},
  [8]  = {1000, 1700, 2100},
  [9]  = {1300, 2000, 2600},
  [10] = {1600, 2300, 3100},
  [11] = {1900, 2900, 4100},
  [12] = {2200, 3700, 4700},
  [13] = {2600, 4200, 5400},
  [14] = {2900, 4900, 6200},
  [15] = {3300, 5400, 7800},
  [16] = {3800, 6100, 9800},
  [17] = {4500, 7200, 11700},
  [18] = {5000, 8700, 14200},
  [19] = {5500, 10700, 17200},
  [20] = {6400, 13200, 22000},
}


local openBattles = {}

local function rulesVersion()
  return OptionsManager.getOption("GAVE") or "2014"
end

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function getPartyCharNodes()
  local t = {}
  for _, node in pairs(DB.getChildren("partysheet.partyinformation") or {}) do
    local sClass, sRecord = DB.getValue(node, "link", "", "")
    if sRecord and sRecord ~= "" then
      local pc = DB.findNode(sRecord)
      if pc then
        t[#t+1] = pc
      end
    end
  end
  return t
end

local function getPCLevel(nodePC)
  -- Try common 5E fields first
  local nLevel = DB.getValue(nodePC, "level", 0)
  if nLevel and nLevel > 0 then return nLevel end

  -- Fallback: sum class levels if present
  local total = 0
  for _, cls in pairs(DB.getChildren(nodePC, "classes") or {}) do
    total = total + (DB.getValue(cls, "level", 0) or 0)
  end
  if total > 0 then return total end

  -- Last fallback
  return 1
end

local function getPartyThresholds()
  local pcs = getPartyCharNodes()
  local partySize = #pcs
  if partySize == 0 then
    return 0, 0, 0, 0, 0
  end

  local easy, med, hard, deadly = 0, 0, 0, 0
  for _, pc in ipairs(pcs) do
    local lvl = clamp(getPCLevel(pc), 1, 20)
    local th = XP_THRESHOLDS[lvl] or XP_THRESHOLDS[1]
    easy   = easy   + th[1]
    med    = med    + th[2]
    hard   = hard   + th[3]
    deadly = deadly + th[4]
  end

  return partySize, easy, med, hard, deadly
end

local function getNPCXP(nodeNPC)
  if not nodeNPC then return 0 end
  local xp = DB.getValue(nodeNPC, "xp", 0)
  if type(xp) == "number" then return xp end
  return parseNumber(xp)
end

local function resolveNPCRecord(nodeEncounterNPC)
  -- Encounter NPC entry typically has a "link" field to an npc record
  local sClass, sRecord = DB.getValue(nodeEncounterNPC, "link", "", "")
  if sRecord and sRecord ~= "" then
    return DB.findNode(sRecord)
  end
  return nil
end

local function getEncounterNPCList(nodeEncounter)
  return DB.getChildren(nodeEncounter, "npclist") or {}
end

local function getNPCCount(nodeEncounterNPC)
  local c = DB.getValue(nodeEncounterNPC, "count", 0)
  if c and c > 0 then return c end
  return 1
end

local function getEncounterXP(nodeEncounter)
  local baseXP = 0
  local monsterCount = 0

  for _, encNPC in pairs(getEncounterNPCList(nodeEncounter)) do
    local nCount = clamp(getNPCCount(encNPC), 0, 999)
    if nCount > 0 then
      local npcRecord = resolveNPCRecord(encNPC)
      local xpEach = getNPCXP(npcRecord)
      baseXP = baseXP + (xpEach * nCount)
      monsterCount = monsterCount + nCount
    end
  end

  return baseXP, monsterCount
end

local function getMultiplierByCount(monsterCount)
  if monsterCount <= 0 then return 0 end
  if monsterCount == 1 then return 1.0 end
  if monsterCount == 2 then return 1.5 end
  if monsterCount >= 3 and monsterCount <= 6 then return 2.0 end
  if monsterCount >= 7 and monsterCount <= 10 then return 2.5 end
  if monsterCount >= 11 and monsterCount <= 14 then return 3.0 end
  return 4.0
end

local function shiftMultiplier(mult, steps)
  -- DMG step ladder (ascending):
  local ladder = {1.0, 1.5, 2.0, 2.5, 3.0, 4.0}
  local idx = 1
  for i, v in ipairs(ladder) do
    if math.abs(v - mult) < 0.001 then
      idx = i
      break
    end
  end
  idx = clamp(idx + steps, 1, #ladder)
  return ladder[idx]
end

local function partySizeAdjustMultiplier(mult, partySize)
  -- DMG: party size <3 => one step harder; party size >=6 => one step easier
  if partySize > 0 and partySize < 3 then
    return shiftMultiplier(mult, 1)
  elseif partySize >= 6 then
    return shiftMultiplier(mult, -1)
  end
  return mult
end

local function getAdjustedXP(baseXP, monsterCount, partySize)
  if rulesVersion() == "2024" then
    return baseXP, 1.0
  end

  local mult = getMultiplierByCount(monsterCount)
  mult = partySizeAdjustMultiplier(mult, partySize)
  return baseXP * mult, mult
end

local function formatInt(n)
  n = math.floor(n + 0.5)
  local s = tostring(n)
  local out = {}
  local len = #s
  local i = len
  local c = 0
  while i > 0 do
    out[#out+1] = s:sub(i, i)
    c = c + 1
    if c == 3 and i > 1 then
      out[#out+1] = ","
      c = 0
    end
    i = i - 1
  end
  local rev = {}
  for j = #out, 1, -1 do rev[#rev+1] = out[j] end
  return table.concat(rev)
end

local function difficultyLabel(adjustedXP, easy, med, hard, deadly)
  if adjustedXP <= 0 then return "—" end
  if adjustedXP < easy then return "Trivial" end
  if adjustedXP < med then return "Easy" end
  if adjustedXP < hard then return "Medium" end
  if adjustedXP < deadly then return "Hard" end
  return "Deadly"
end

local function difficultyLabel2024(xp, budget)
  if xp <= budget * 0.5 then return "Low" end
  if xp <= budget * 0.75 then return "Moderate" end
  if xp <= budget then return "High" end
  return "Extreme"
end

local function get2024Budget()
  local pcs = getPartyCharNodes()
  local low, mod, high = 0, 0, 0

  for _, pc in ipairs(pcs) do
    local lvl = clamp(getPCLevel(pc), 1, 20)
    local row = XP_BUDGET_2024[lvl]
    low  = low  + row[1]
    mod  = mod  + row[2]
    high = high + row[3]
  end

  return low, mod, high
end

local function recalcEncounter(nodeEncounter)
  if not nodeEncounter then
    Debug.print("Recalc node is nil")
    return
  end

  local partySize, easy, med, hard, deadly = getPartyThresholds()
  local baseXP, monsterCount = getEncounterXP(nodeEncounter)

  local adjusted, mult = getAdjustedXP(baseXP, monsterCount, partySize)
  local rv = rulesVersion()
  local label
  if rv == "2024" then
    local low, mod, high = get2024Budget()
    label = difficultyLabel2024(adjusted, high)
  else
    label = difficultyLabel(adjusted, easy, med, hard, deadly)
  end

  local text
  local debugText

  if monsterCount == 0 then
    text = "-"
    debugText = "No monsters"
  else
    local partyText = (partySize > 0)
      and string.format("Party: %d", partySize)
      or "No party"

    text = label

    local rv = rulesVersion()
    if rv == "2024" then
      debugText = string.format(
        "%s\nXP: %s\nEnemies: %d\n%s\nRules: 2024",
        label,
        formatInt(adjusted),
        monsterCount,
        partyText
      )
    else
      debugText = string.format(
        "%s\nXP: %s (x%.1f)\nEnemies: %d\n%s\nRules: 2014",
        label,
        formatInt(adjusted),
        mult,
        monsterCount,
        partyText
      )
    end
  end

  DB.setValue(nodeEncounter, "difficultytext", "string", text)
  DB.setValue(nodeEncounter, "difficultytooltip", "string", debugText)
end


local function stripAtSuffix(path)
  return string.gsub(path, "@.*$", "")
end

local function recalcFromNode(node)
  local cur = node
  for _ = 1, 12 do
    if not cur then return end
    local parent = cur.getParent and cur.getParent() or nil

    if parent then
      local p = parent.getPath and parent.getPath() or ""
      if string.gsub(p, "@.*$", "") == "battle" then
        recalcEncounter(cur)
        return
      end
    end

    cur = parent
  end
end

local function onPartyChanged()
  -- Debug.print("Party changed, recalc open encounters")
  for w in pairs(openBattles) do
    local node = w.getDatabaseNode and w.getDatabaseNode()
    if node then
      recalcEncounter(node)
    end
  end
end

local function onEncounterChanged(node)
  if node then
    -- Debug.print("Encounter changed, recalc path " .. node.getPath())
    recalcFromNode(node)
  end
end

local function dumpNode(node, indent)
  indent = indent or ""
  Debug.print(indent .. node.getPath())

  for _, child in pairs(DB.getChildren(node) or {}) do
    dumpNode(child, indent .. "  ")
  end
end

local function initBattleHandlers()

  -- New encounter example path:
  -- battle.id-00001.npclist.id-00002.count

  -- Module encounter example path:
  -- battle.id-00015.npclist.id-00001.count@Alagoran's Gem

  local tMappings = RecordDataManager.getDataPaths("battle")

  for _, sMapping in ipairs(tMappings) do
    local base = DB.getPath(sMapping)

    Debug.print("initBattleHandlers mapping: " .. sMapping .. ", base: " .. base)

    -- Watch NPC list changes
    DB.addHandler(base .. ".*.npclist", "onChildAdded",  onEncounterChanged)
    DB.addHandler(base .. ".*.npclist", "onChildDeleted", onEncounterChanged)

    DB.addHandler(base .. ".*.npclist@*", "onChildAdded",  onEncounterChanged)
    DB.addHandler(base .. ".*.npclist@*", "onChildDeleted", onEncounterChanged)

    -- Watch count + link changes
    DB.addHandler(base .. ".*.npclist.*.count", "onUpdate", onEncounterChanged)
    DB.addHandler(base .. ".*.npclist.*.link",  "onUpdate", onEncounterChanged)

    DB.addHandler(base .. ".*.npclist.*.count@*", "onUpdate", onEncounterChanged)
    DB.addHandler(base .. ".*.npclist.*.link@*",  "onUpdate", onEncounterChanged)
  end
end

function onInit()
  Debug.print("Encounter difficulty extension onInit")

  if User.isHost() == true then
    local oldOpen = Interface.onWindowOpened
    Interface.onWindowOpened = function(w)
      if oldOpen then oldOpen(w) end
      if w.getClass and w.getClass() == "battle" then
        openBattles[w] = true
        local node = w.getDatabaseNode and w.getDatabaseNode()
        if node then
          recalcEncounter(node)
        end
      end
    end

    local oldClose = Interface.onWindowClosed
    Interface.onWindowClosed = function(w)
      if oldClose then oldClose(w) end
      openBattles[w] = nil
    end

    initBattleHandlers()

    -- Party changes
    DB.addHandler("partysheet.partyinformation.*", "onChildAdded", onPartyChanged)
    DB.addHandler("partysheet.partyinformation.*", "onChildDeleted", onPartyChanged)
    DB.addHandler("partysheet.partyinformation.*", "onChildUpdate", onPartyChanged)
    DB.addHandler("partysheet.partyinformation.*.link", "onUpdate", onPartyChanged)

    Debug.print("Encounter difficulty extension initialisation done")
  else
    Debug.print("Not host, skipping encounter difficulty extension")
  end
end

-- For testing
__encounter_test = {
  recalcEncounter = recalcEncounter,
  getEncounterXP = getEncounterXP,
  getPartyThresholds = getPartyThresholds
}

