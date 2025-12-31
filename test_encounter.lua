-- =========================
-- Mock Fantasy Grounds API
-- =========================

DB = {
  _data = {},

  getValue = function(node, key, _, default)
    if type(node) == "string" then
      node = DB._data[node]
    end

    if type(node) == "table" then
      local val = node[key]
      if key == "link" and type(val) == "string" then
        return "", val
      end
      return val or default
    end

    return default
  end,


  setValue = function(node, key, _, value)
    node[key] = value
  end,

  getChildren = function(node, key)
    if type(node) == "string" then
      node = DB._data[node]
    end
    if not node then return {} end
    return key and node[key] or node
  end,

  findNode = function(path)
    return DB._data[path]
  end,

  getPath = function(path)
    return path
  end,

  addHandler = function(...) end
}

OptionsManager = {
  getOption = function()
    return "2014"
  end
}

User = {
  isHost = function() return true end
}

Interface = {
  onWindowOpened = nil,
  onWindowClosed = nil
}

RecordDataManager = {
  getDataPaths = function()
    return { "battle" }
  end
}

Debug = {
  print = function(...) print("[DEBUG]", ...) end
}

local function resetDB()
  DB._data = {}
end

local function mockParty(levels)
  DB._data["partysheet.partyinformation"] = {}

  for i, lvl in ipairs(levels) do
    local id = "chars.pc" .. i
    DB._data["partysheet.partyinformation"][i] = { link = id }
    DB._data[id] = { level = lvl }
  end
end

local function mockEncounter(monsters)
  local list = {}
  for i, m in ipairs(monsters) do
    list[i] = {
      count = m.count,
      link = m.npc
    }
    DB._data[m.npc] = { xp = m.xp }
  end

  return { npclist = list }
end

local function runTest(name, party, monsters, expected)
  resetDB()
  mockParty(party)
  local enc = mockEncounter(monsters)

  __encounter_test.recalcEncounter(enc)

  local ok =
    enc.difficultytext == expected.label and
    enc.difficultytooltip:find(expected.label, 1, true)

  print(string.format(
    "[%s] %s",
    ok and "PASS" or "FAIL",
    name
  ))

  if not ok then
    print("  Expected:", expected.label)
    print("  Got:", enc.difficultytext)
    print(enc.difficultytooltip)
  end
end

-- ===========
-- Load module
-- ===========

dofile("EncounterDifficulty/scripts/encounter_difficulty.lua")

-- ===============
-- Build mock data
-- ===============

-- Fake party
DB._data["partysheet.partyinformation"] = {
  {
    link = "chars.pc1"
  },
  {
    link = "chars.pc2"
  }
}

DB._data["chars.pc1"] = { level = 3 }
DB._data["chars.pc2"] = { level = 3 }

-- Fake NPC
DB._data["npc.goblin"] = { xp = 50 }

-- Fake encounter
local encounter = {
  npclist = {
    {
      count = 3,
      link = "npc.goblin"
    }
  }
}

local function withRuleset(version, fn)
  local old = OptionsManager.getOption
  OptionsManager.getOption = function() return version end
  fn()
  OptionsManager.getOption = old
end

__encounter_test.recalcEncounter(encounter)


print("\nRunning encounter tests...\n")

-- 2× L3 PCs vs 3 Goblins
-- 150 XP ×2 = 300
-- Easy threshold = 150
runTest(
  "2x L3 vs 3 Goblins",
  {3,3},
  { { npc = "npc.goblin", xp = 50, count = 3 } },
  { label = "Medium" }
)

-- 4× L5 PCs vs 1 Ogre
-- 450 XP ×1 = 450
-- Easy threshold = 1000
runTest(
  "4x L5 vs Ogre",
  {5,5,5,5},
  { { npc = "npc.ogre", xp = 450, count = 1 } },
  { label = "Trivial" }
)

-- 4× L5 PCs vs 6 Orcs
-- 600 XP ×2 = 1200
-- Easy = 1000, Medium = 2000
runTest(
  "4x L5 vs 6 Orcs",
  {5,5,5,5},
  { { npc = "npc.orc", xp = 100, count = 6 } },
  { label = "Easy" }
)

-- 5× L8 PCs vs 10 Cultists
-- 250 XP ×2.5 = 625
-- Easy threshold = 2250
runTest(
  "5x L8 vs 10 Cultists",
  {8,8,8,8,8},
  { { npc = "npc.cultist", xp = 25, count = 10 } },
  { label = "Trivial" }
)

-- 2× L10 PCs vs Adult Dragon
-- 18,000 XP ×1 = 18,000
-- Deadly threshold = 5600
runTest(
  "2x L10 vs Adult Dragon",
  {10,10},
  { { npc = "npc.dragon", xp = 18000, count = 1 } },
  { label = "Deadly" }
)

print("\nRunning 2024 encounter tests...\n")

withRuleset("2024", function()

  -- Example 1:
  -- 4 × Level 1, Low difficulty
  -- Budget: 50 × 4 = 200
  -- 1 Bugbear (200 XP)
  runTest(
    "2024: 4x L1 vs Bugbear (Low)",
    {1,1,1,1},
    { { npc = "npc.bugbear", xp = 200, count = 1 } },
    { label = "Low" }
  )

  -- Example 2:
  -- 5 × Level 3, Moderate
  -- Budget: 225 × 5 = 1125
  -- 2 Nothics (450) + 9 Stirges (25) = 1125
  runTest(
    "2024: 5x L3 Moderate Mix",
    {3,3,3,3,3},
    {
      { npc = "npc.nothic", xp = 450, count = 2 },
      { npc = "npc.stirge", xp = 25, count = 9 }
    },
    { label = "Moderate" }
  )

  -- Example 3:
  -- 6 × Level 15, High
  -- Budget: 7800 × 6 = 46800
  -- 2 Adult Red Dragons + 2 Fire Giants = 46000
  runTest(
    "2024: 6x L15 High Difficulty",
    {15,15,15,15,15,15},
    {
      { npc = "npc.red_dragon", xp = 18000, count = 2 },
      { npc = "npc.fire_giant", xp = 5000, count = 2 }
    },
    { label = "High" }
  )

  -- Over-budget → Extreme
  runTest(
    "2024: Extreme encounter",
    {10,10,10,10},
    {
      { npc = "npc.dragon", xp = 18000, count = 1 }
    },
    { label = "Extreme" }
  )

end)

-- Run test suite like so:
-- lua ./test_encounter.lua
