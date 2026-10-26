--[[
  STEAL AN EGG — Delta Hub v6
  Hermes Agent · 6 Sep 2026
  https://github.com/naharsyaifullah-ai/steal-an-egg-script

  Perbaikan v6 (diselidiki dari script autofarm publik yang masih berfungsi):
   · telur game ini TIDAK bernama "Egg" — mereka hidup di
     workspace.AreaEggSlotsClient (slot berisi part "Plane"), telur event
     berdiri sendiri dengan anak "Hitbox". v5 mencari nama 'egg' → ESP dan
     auto steal sama-sama tidak menemukan apa pun. v6 memindai struktur asli
     ini + tetap memakai deteksi nama generik sebagai cadangan.
   · prompt ambil game ini DIPUSATKAN di workspace.SmartPromptPart, bukan di
     dalam telur — fireSmartPrompts() menembaknya dengan HoldDuration = 0.
   · resep hasil AJARI tersimpan ke berkas executor (writefile) dan dimuat
     ulang otomatis — AJARI cukup sekali, bukan tiap sesi.
   · base dibaca dari workspace.Plots (pemilik dicocokkan dengan nama),
     zona peta (11 zona) dari koordinat terukur.
   · tombol "Geledah struktur game" membedah AreaEggSlotsClient, prompt,
     Plots, dan module ReplicatedStorage kalau data masih belum cocok.

  Resiko: cheat bisa kena ban. Pakai akun cadangan.
]]

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RS                = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local LP                = Players.LocalPlayer

-- urutan rarity dari terendah ke Divine (10 tier resmi)
local RARITY = {
  "Common", "Uncommon", "Rare", "Epic", "Legendary",
  "Mythic", "Cosmic", "Secret", "Eternal", "Divine",
}

local RCOLOR = {
  Common    = Color3.fromRGB(150, 160, 175),
  Uncommon  = Color3.fromRGB(120, 220, 150),
  Rare      = Color3.fromRGB(90,  170, 255),
  Epic      = Color3.fromRGB(180, 130, 255),
  Legendary = Color3.fromRGB(255, 190, 80),
  Mythic    = Color3.fromRGB(255, 110, 200),
  Cosmic    = Color3.fromRGB(90,  230, 240),
  Secret    = Color3.fromRGB(255, 235, 130),
  Eternal   = Color3.fromRGB(200, 120, 255),
  Divine    = Color3.fromRGB(255, 255, 255),
}

-- mutasi diurut dari NAMA TERPANJANG supaya "Spirit Bloom" tidak
-- keliru terbaca sebagai "Bloom"
local MUTATION = { "Spirit Bloom", "Rainbow", "Golden", "Bloom", "Silver" }

-- ============ STATE ============
local S = {
  -- steal
  stealOn      = false,
  rarityPick   = {},
  minWeight    = 0,
  minIncome    = 0,        -- filter income $/s minimum
  maxRange     = 3000,     -- jarak maksimum telur yang dikejar
  preferMutasi = true,
  returnBase   = true,
  stealDelay   = 0.25,
  stealSpeed   = 180,      -- kecepatan khusus saat steal (stud/detik)
  takeUnknown  = true,     -- telur yang tidak dikenal database tetap diambil
  takePlots    = false,    -- ambil telur dari base pemain lain (default: TIDAK)
  baseGuard    = 60,       -- telur sedekat ini ke base sendiri diabaikan
  grabTries    = 3,        -- berapa kali usaha ambil per telur
  blindFire    = false,    -- tembak remote hasil TEBAKAN nama (mati by default)
  approachDist = 6,        -- sedekat apa harus mendekat sebelum mencoba ambil
  hoverBase    = true,     -- setelah ambil, pulang ke base

  -- gerak
  walkMode     = false,    -- false = terbang datar (hop), true = jalan kaki

  -- farm
  autoHatch    = false,
  autoClaim    = false,
  autoTrain    = false,
  autoSell     = false,
  autoUpgrade  = false,

  -- player
  speedOn      = false,
  speed        = 120,      -- kecepatan gerak umum
  antiTrap     = false,
  antiBat      = false,
  antiStun     = true,     -- default ON: mencegah ragdoll saat steal
  noFall       = true,
  avoidRadius  = 26,

  -- esp
  espEgg       = false,
  espPlayer    = false,
  espTrap      = false,
  espGuard     = false,
  espMinRarity = 1,
  espRange     = 3000,
  espUnknown   = true,     -- tampilkan juga telur yang belum dikenal

  -- runtime
  status       = "idle",
  stolen       = 0,
  fails        = 0,
  lastEgg      = "-",
  lastGrab     = "-",
}

for _, r in ipairs(RARITY) do S.rarityPick[r] = false end
S.rarityPick.Secret  = true
S.rarityPick.Eternal = true
S.rarityPick.Divine  = true


-- ============ DATABASE PET & TELUR (106 pet) ============
-- Sumber, diambil 5 Sep 2026 lewat you.com:
--   · Eldorado "all pets index"  -> 80 pet, 10 biome
--   · Joytify + Timesaver.gg     -> Titan Temple (Update 2, 29-30 Agu 2026)
--   · IGN All_Pets               -> Monster Egg 12 pet (income belum diindeks)
-- Angka income = NILAI DASAR pet. Di game, berat/ukuran telur ikut menentukan
-- money/s akhir, jadi ini patokan, bukan hasil persis.
-- Kunci = nama pet huruf kecil tanpa spasi/tanda baca.

local DB = {
  -- Forest
  chicken            = { "Common",    1,          "Forest" },
  dog                = { "Common",    2,          "Forest" },
  bird               = { "Uncommon",  8,          "Forest" },
  owl                = { "Rare",      35,         "Forest" },
  raccoon            = { "Rare",      45,         "Forest" },
  bear               = { "Epic",      240,        "Forest" },
  fox                = { "Epic",      180,        "Forest" },
  brrbrrpatapim      = { "Legendary", 1800,       "Forest" },
  -- Lake
  frog               = { "Common",    3,          "Lake" },
  duckling           = { "Common",    4,          "Lake" },
  catfish            = { "Uncommon",  12,         "Lake" },
  turtle             = { "Rare",      60,         "Lake" },
  trulimerotrulicina = { "Epic",      260,        "Lake" },
  swan               = { "Epic",      320,        "Lake" },
  axolotl            = { "Legendary", 2800,       "Lake" },
  leviathan          = { "Cosmic",    220000,     "Lake" },
  -- Desert
  jerboa             = { "Common",    6,          "Desert" },
  fennec             = { "Uncommon",  18,         "Desert" },
  camel              = { "Rare",      75,         "Desert" },
  tobtobitobtob      = { "Epic",      325,        "Desert" },
  snake              = { "Legendary", 3600,       "Desert" },
  scorpion           = { "Mythic",    18500,      "Desert" },
  sandspider         = { "Mythic",    16000,      "Desert" },
  royalsphinx        = { "Cosmic",    280000,     "Desert" },
  -- Jungle
  toucan             = { "Rare",      110,        "Jungle" },
  chimpanzee         = { "Rare",      90,         "Jungle" },
  crocodile          = { "Epic",      420,        "Jungle" },
  gorilla            = { "Legendary", 4800,       "Jungle" },
  orangutiniananassini = { "Legendary", 5500,     "Jungle" },
  spider             = { "Mythic",    22000,      "Jungle" },
  tiger              = { "Mythic",    28000,      "Jungle" },
  kingsnake          = { "Secret",    3500000,    "Jungle" },
  -- Snow
  penguin            = { "Rare",      140,        "Snow" },
  walrus             = { "Epic",      600,        "Snow" },
  polarbear          = { "Legendary", 7000,       "Snow" },
  sabertoothtiger    = { "Mythic",    35000,      "Snow" },
  mammoth            = { "Mythic",    42000,      "Snow" },
  kingmammoth        = { "Cosmic",    400000,     "Snow" },
  yeti               = { "Secret",    5000000,    "Snow" },
  icedragon          = { "Eternal",   65000000,   "Snow" },
  -- Volcano
  lavagecko          = { "Rare",      180,        "Volcano" },
  lavafrog           = { "Epic",      850,        "Volcano" },
  flamingbull        = { "Legendary", 9500,       "Volcano" },
  lavaiguana         = { "Legendary", 11000,      "Volcano" },
  chillinchilli      = { "Mythic",    55000,      "Volcano" },
  cerberus           = { "Secret",    8000000,    "Volcano" },
  phoenix            = { "Eternal",   85000000,   "Volcano" },
  lavadragon         = { "Eternal",   100000000,  "Volcano" },
  -- Abyss Ocean
  parrotfish         = { "Rare",      220,        "Abyss" },
  swordfish          = { "Epic",      1100,       "Abyss" },
  shark              = { "Legendary", 15000,      "Abyss" },
  orca               = { "Mythic",    80000,      "Abyss" },
  whaleshark         = { "Cosmic",    700000,     "Abyss" },
  belugawhale        = { "Cosmic",    850000,     "Abyss" },
  kraken             = { "Secret",    15000000,   "Abyss" },
  elmaja             = { "Eternal",   130000000,  "Abyss" },
  -- Prehistoric
  dodo               = { "Rare",      280,        "Prehistoric" },
  pterodactyl        = { "Legendary", 22000,      "Prehistoric" },
  ankylosaurus       = { "Mythic",    120000,     "Prehistoric" },
  triceratops        = { "Cosmic",    1200000,    "Prehistoric" },
  bronto             = { "Cosmic",    1500000,    "Prehistoric" },
  tralaledon         = { "Secret",    32000000,   "Prehistoric" },
  trex               = { "Secret",    25000000,   "Prehistoric" },
  mosasaurus         = { "Eternal",   180000000,  "Prehistoric" },
  -- Cosmic
  centapede          = { "Epic",      1500,       "Cosmic" },
  cosmicgecko        = { "Legendary", 30000,      "Cosmic" },
  cosmicgorilla      = { "Mythic",    180000,     "Cosmic" },
  lavaccasaturnosaturnita = { "Cosmic", 2200000,  "Cosmic" },
  cosmicdragon       = { "Secret",    60000000,   "Cosmic" },
  cosmicskeletonboss = { "Secret",    45000000,   "Cosmic" },
  eternallunardragon = { "Eternal",   250000000,  "Cosmic" },
  unicorn            = { "Divine",    1000000000, "Cosmic" },
  -- Cherry Blossom
  crane              = { "Epic",      4000,       "Cherry" },
  salamander         = { "Legendary", 74000,      "Cherry" },
  redpanda           = { "Mythic",    450000,     "Cherry" },
  koi                = { "Cosmic",    12000000,   "Cherry" },
  snowyowl           = { "Cosmic",    7500000,    "Cherry" },
  stag               = { "Secret",    145000000,  "Cherry" },
  onitiger           = { "Eternal",   600000000,  "Cherry" },
  kitsune            = { "Divine",    1800000000, "Cherry" },
  -- Titan Temple (Update 2 — Monsters Are Coming, 29-30 Agu 2026)
  crustacia          = { "Legendary", 130000,     "Titan" },
  spideron           = { "Legendary", 95000,      "Titan" },
  bladehide          = { "Mythic",    750000,     "Titan" },
  mantaris           = { "Cosmic",    11000000,   "Titan" },
  rhinotaur          = { "Cosmic",    17500000,   "Titan" },
  mutantshark        = { "Secret",    215000000,  "Titan" },
  gorillaking        = { "Eternal",   880000000,  "Titan" },
  nightflame         = { "Divine",    nil,        "Titan" },   -- belum diindeks
  -- Brainrot (telur Shop terbatas) — income tidak dipublikasikan
  tungtungsahur      = { "Rare",      nil,        "Brainrot" },
  bananitadolphinita = { "Epic",      nil,        "Brainrot" },
  belulabeluga       = { "Mythic",    nil,        "Brainrot" },
  mangoliniparrochini = { "Cosmic",   nil,        "Brainrot" },
  bomboclatcrocolat  = { "Secret",    nil,        "Brainrot" },
  strawberryelephant = { "Eternal",   nil,        "Brainrot" },
  -- Monster Egg (Robux Shop) — IGN mencatat income "Unknown"; dibiarkan nil
  scorpio            = { "Legendary", nil,        "Monster" },
  froggo             = { "Mythic",    nil,        "Monster" },
  crawler            = { "Cosmic",    nil,        "Monster" },
  crocodon           = { "Secret",    nil,        "Monster" },
  krakenoid          = { "Eternal",   nil,        "Monster" },
  dreadscale         = { "Divine",    8000000000, "Monster" },  -- 1 sumber: ~$8B/s
  mechascorpio       = { "Legendary", nil,        "Monster" },
  mechafroggo        = { "Mythic",    nil,        "Monster" },
  mechacrawler       = { "Cosmic",    nil,        "Monster" },
  mechacrocodon      = { "Secret",    nil,        "Monster" },
  mechakrakenoid     = { "Eternal",   nil,        "Monster" },
  mechadreadscale    = { "Divine",    nil,        "Monster" },
}

-- Nama tampilan: default kapitalkan huruf pertama; multi-kata ditulis manual.
local DISPLAY = {}
for k in pairs(DB) do DISPLAY[k] = k:sub(1, 1):upper() .. k:sub(2) end
DISPLAY.brrbrrpatapim = "Brr Brr Patapim"
DISPLAY.trulimerotrulicina = "Trulimero Trulicina"
DISPLAY.tobtobitobtob = "Tob Tobi Tob Tob"
DISPLAY.orangutiniananassini = "Orangutini Ananassini"
DISPLAY.sandspider = "Sand Spider"
DISPLAY.royalsphinx = "Royal Sphinx"
DISPLAY.kingsnake = "King Snake"
DISPLAY.polarbear = "Polar Bear"
DISPLAY.sabertoothtiger = "Sabertooth Tiger"
DISPLAY.kingmammoth = "King Mammoth"
DISPLAY.icedragon = "Ice Dragon"
DISPLAY.lavagecko = "Lava Gecko"
DISPLAY.lavafrog = "Lava Frog"
DISPLAY.flamingbull = "Flaming Bull"
DISPLAY.lavaiguana = "Lava Iguana"
DISPLAY.chillinchilli = "Chillin Chilli"
DISPLAY.lavadragon = "Lava Dragon"
DISPLAY.whaleshark = "Whale Shark"
DISPLAY.belugawhale = "Beluga Whale"
DISPLAY.elmaja = "El Maja"
DISPLAY.trex = "T-Rex"
DISPLAY.cosmicgecko = "Cosmic Gecko"
DISPLAY.cosmicgorilla = "Cosmic Gorilla"
DISPLAY.lavaccasaturnosaturnita = "La Vacca Saturno Saturnita"
DISPLAY.cosmicdragon = "Cosmic Dragon"
DISPLAY.cosmicskeletonboss = "Cosmic Skeleton Boss"
DISPLAY.eternallunardragon = "Eternal Lunar Dragon"
DISPLAY.redpanda = "Red Panda"
DISPLAY.snowyowl = "Snowy Owl"
DISPLAY.onitiger = "Oni Tiger"
DISPLAY.mutantshark = "Mutant Shark"
DISPLAY.gorillaking = "Gorilla King"
DISPLAY.tungtungsahur = "Tung Tung Sahur"
DISPLAY.bananitadolphinita = "Bananita Dolphinita"
DISPLAY.belulabeluga = "Belula Beluga"
DISPLAY.mangoliniparrochini = "Mangolini Parrochini"
DISPLAY.bomboclatcrocolat = "Bomboclat Crocolat"
DISPLAY.strawberryelephant = "Strawberry Elephant"
DISPLAY.mechascorpio = "Mecha Scorpio"
DISPLAY.mechafroggo = "Mecha Froggo"
DISPLAY.mechacrawler = "Mecha Crawler"
DISPLAY.mechacrocodon = "Mecha Crocodon"
DISPLAY.mechakrakenoid = "Mecha Krakenoid"
DISPLAY.mechadreadscale = "Mecha Dreadscale"

-- Kunci diurut dari TERPANJANG. Wajib: "kingmammoth" harus menang atas
-- "mammoth", "mechadreadscale" atas "dreadscale", "sandspider" atas "spider".
local DB_KEYS = {}
for k in pairs(DB) do DB_KEYS[#DB_KEYS + 1] = k end
table.sort(DB_KEYS, function(a, b) return #a > #b end)

local function normalize(s)
  return (tostring(s or ""):lower():gsub("[^%a]", ""))
end

-- pencocokan longgar: nama pet terkandung di dalam teks
local function dbLookup(name)
  local n = normalize(name)
  if n == "" then return nil end
  n = n:gsub("egg", "")
  if DB[n] then return n end
  for _, k in ipairs(DB_KEYS) do
    if #k >= 4 and n:find(k, 1, true) then return k end
  end
  return nil
end

-- pencocokan ketat: nama objek harus PERSIS nama pet setelah kata "egg" dan
-- semua tanda baca dibuang. Dipakai untuk memutuskan "ini telur atau bukan",
-- supaya "BearTrap" tidak dianggap telur Bear.
local function dbExact(name)
  local n = normalize(name):gsub("egg", "")
  if n ~= "" and DB[n] then return n end
  return nil
end

-- pencocokan dengan mengabaikan awalan mutasi: "RainbowKitsuneEgg" -> kitsune
local function dbStripMutation(name)
  local n = normalize(name):gsub("egg", "")
  for _, m in ipairs({ "spiritbloom", "rainbow", "golden", "bloom", "silver" }) do
    n = n:gsub("^" .. m, "")
  end
  if n ~= "" and DB[n] then return n end
  return nil
end

local function money(v)
  if not v then return "?" end
  local a = math.abs(v)
  if a >= 1e9 then return string.format("$%.3gB/s", v / 1e9) end
  if a >= 1e6 then return string.format("$%.3gM/s", v / 1e6) end
  if a >= 1e3 then return string.format("$%.3gK/s", v / 1e3) end
  return string.format("$%d/s", math.floor(v))
end

local function kg(v)
  if not v or v <= 0 then return nil end
  if v >= 1e6 then return string.format("%.3gMkg", v / 1e6) end
  if v >= 1e3 then return string.format("%.3gKkg", v / 1e3) end
  return string.format("%dkg", math.floor(v))
end

-- jumlah entri, dipakai panel info
local DB_COUNT = 0
for _ in pairs(DB) do DB_COUNT = DB_COUNT + 1 end


-- ============ UTIL ============
local function char()  return LP.Character end
local function hrp()   local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()   local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function alive() local h = hum(); return h and h.Health > 0 end

local function lower(s) return string.lower(tostring(s or "")) end

local function partOf(inst)
  if inst:IsA("BasePart") then return inst end
  if inst:IsA("Model") then
    return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
  end
  return nil
end

local function posOf(inst)
  local p = partOf(inst)
  return p and p.Position or nil
end

local function dist(a, b) return (a - b).Magnitude end

-- cari BasePart pertama secara REKURSIF. FindFirstChildWhichIsA di beberapa
-- executor/game hanya mencari anak langsung, padahal telur event menaruh
-- Plane-nya di dalam Model beberapa lapis.
local function firstPartOf(obj)
  if not obj then return nil end
  if obj:IsA("BasePart") then return obj end
  for _, d in ipairs(obj:GetDescendants()) do
    if d:IsA("BasePart") then return d end
  end
  return nil
end

local function findNamed(obj, name)
  if not obj then return nil end
  if obj.Name == name then return obj end
  for _, d in ipairs(obj:GetDescendants()) do
    if d.Name == name then return d end
  end
  return nil
end

-- Zona peta diukur dari game nyata (dipakai script autofarm publik yang masih
-- berfungsi per Agu 2026): zona tersusun sepanjang sumbu X, pita Z tetap.
-- Dipakai sebagai nama biome cadangan kalau database tidak mengenal pet-nya.
local ZONES = {
  { name = "Forest",         minX = 553.42,  maxX = 646.49  },
  { name = "Lake",           minX = 653.01,  maxX = 793.51  },
  { name = "Desert",         minX = 796.48,  maxX = 1005.04 },
  { name = "Jungle",         minX = 1008.56, maxX = 1240.12 },
  { name = "Snow",           minX = 1244.13, maxX = 1564.18 },
  { name = "Volcano",        minX = 1568.33, maxX = 1949.58 },
  { name = "Abyss Ocean",    minX = 1953.30, maxX = 2378.73 },
  { name = "Prehistoric",    minX = 2382.87, maxX = 2884.09 },
  { name = "Cosmic",         minX = 2888.03, maxX = 3523.51 },
  { name = "Cherry Blossom", minX = 3527.67, maxX = 4263.53 },
  { name = "Titan Temple",   minX = 4268.09, maxX = 5123.06 },
}
local ZONE_MINZ, ZONE_MAXZ = -433.40, -295.05

local function zoneOf(pos)
  if not pos then return nil end
  if pos.Z < ZONE_MINZ or pos.Z > ZONE_MAXZ then return nil end
  for _, z in ipairs(ZONES) do
    if pos.X >= z.minX and pos.X <= z.maxX then return z.name end
  end
  return nil
end

-- Kumpulkan SEMUA teks yang mungkin memuat nama pet: nama objek, nama induk,
-- label, value, DAN Attribute. Attribute adalah yang paling sering dipakai game
-- modern dan tidak dibaca v4 — itulah sebabnya ESP bilang "tidak ada di
-- database" padahal petnya jelas terdaftar.
local function attrBlob(inst)
  local t = {}
  local ok, attrs = pcall(function() return inst:GetAttributes() end)
  if ok and type(attrs) == "table" then
    for k, v in pairs(attrs) do
      t[#t + 1] = tostring(k) .. "=" .. tostring(v)
    end
  end
  return table.concat(t, " | ")
end

local function textBlob(inst)
  local t = { inst.Name }

  -- rantai induk sampai 3 tingkat: sering "Nest > OniTiger > Egg"
  local p = inst.Parent
  local hops = 0
  while p and hops < 3 and p ~= Workspace do
    t[#t + 1] = p.Name
    p = p.Parent
    hops = hops + 1
  end

  t[#t + 1] = attrBlob(inst)

  for _, d in ipairs(inst:GetDescendants()) do
    if d:IsA("TextLabel") or d:IsA("TextBox") then
      t[#t + 1] = d.Text
    elseif d:IsA("StringValue") then
      t[#t + 1] = d.Name .. "=" .. tostring(d.Value)
    elseif d:IsA("NumberValue") or d:IsA("IntValue") then
      t[#t + 1] = d.Name .. "=" .. tostring(d.Value)
    elseif d:IsA("BasePart") or d:IsA("Model") or d:IsA("MeshPart") then
      -- nama part anak kadang memuat nama pet ("KitsuneMesh")
      t[#t + 1] = d.Name
      local ab = attrBlob(d)
      if ab ~= "" then t[#t + 1] = ab end
    end
  end
  return table.concat(t, " | ")
end

-- Rarity & pet: cari nama pet di SEMUA sumber, dari yang paling tepat ke yang
-- paling longgar. Urutan penting supaya "KingMammoth" tidak jadi "Mammoth".
local function rarityOf(inst)
  local blob = textBlob(inst)

  -- 1. nama objek: persis -> tanpa awalan mutasi -> longgar
  local key = dbExact(inst.Name) or dbStripMutation(inst.Name) or dbLookup(inst.Name)
  -- 2. kalau nama objek generik ("Egg", "Egg1"), cari di seluruh blob
  if not key then key = dbLookup(blob) end
  if key then return DB[key][1], key end

  -- 3. cadangan: kata rarity eksplisit di teks.
  -- "Uncommon" wajib diuji sebelum "Common" (substring!).
  local lb = lower(blob)
  local order = { "Divine", "Eternal", "Secret", "Cosmic", "Mythic",
                  "Legendary", "Uncommon", "Common", "Epic", "Rare" }
  for _, r in ipairs(order) do
    local pat = "%f[%a]" .. lower(r) .. "%f[%A]"
    if lb:find(pat) then return r, nil end
  end
  return nil, nil
end

-- income per detik dari database (nil kalau pet tidak dikenal)
local function incomeOf(inst, key)
  if not key then
    key = dbExact(inst.Name) or dbStripMutation(inst.Name) or dbLookup(inst.Name)
      or dbLookup(textBlob(inst))
  end
  if key and DB[key] then return DB[key][2], DISPLAY[key] or key, DB[key][3] end
  return nil, nil, nil
end

local function mutationOf(inst)
  local blob = lower(textBlob(inst)) .. " " .. lower(inst.Name)
  -- MUTATION sudah diurut dari terpanjang: "Spirit Bloom" sebelum "Bloom"
  for _, m in ipairs(MUTATION) do
    if blob:find(lower(m), 1, true) then return m end
  end
  return nil
end

-- pengali mutasi resmi
local MUT_MULT = {
  ["Spirit Bloom"] = 3.0,
  ["Rainbow"]      = 2.5,
  ["Golden"]       = 2.0,
  ["Bloom"]        = 1.5,
  ["Silver"]       = 1.25,
}

-- berat telur (kg) kalau ada
local function weightOf(inst)
  local blob = textBlob(inst)
  local n = blob:match("([%d%.,]+)%s*[kK][gG]")
  if n then return tonumber((n:gsub(",", ""))) or 0 end
  for _, d in ipairs(inst:GetDescendants()) do
    if (d:IsA("NumberValue") or d:IsA("IntValue")) and lower(d.Name):find("weight") then
      return d.Value
    end
  end
  return 0
end

local function isEggName(n)
  n = lower(n)
  return n:find("egg") ~= nil
end

-- ============ SCAN OBJEK ============
-- myBase() harus didefinisikan SEBELUM scanEggs() karena scanEggs memakainya;
-- kalau ditaruh di bawah, Lua membacanya sebagai global nil dan scan meledak.
local baseCache, baseCacheT = nil, -1e9
local function flushBaseCache()
  baseCache, baseCacheT = nil, -1e9
end

local function plotOwnerIsMe(plot)
  local hit = false
  pcall(function()
    for _, key in ipairs({ "Owner", "OwnerName", "Player", "PlayerName" }) do
      local o = plot:FindFirstChild(key)
      if o and o:IsA("ValueBase") and tostring(o.Value) == LP.Name then hit = true end
    end
  end)
  if not hit then
    pcall(function()
      for _, v in pairs(plot:GetAttributes()) do
        if tostring(v) == LP.Name then hit = true break end
      end
    end)
  end
  if not hit then
    for _, d in ipairs(plot:GetDescendants()) do
      if d:IsA("StringValue") and tostring(d.Value) == LP.Name then hit = true break end
      if d:IsA("TextLabel") and tostring(d.Text):find(LP.Name, 1, true) then hit = true break end
    end
  end
  return hit
end

-- Apakah objek berada di dalam plot pemain (base)? Telur di base TIDAK boleh
-- jadi sasaran default: laporan nyata v6 — auto steal malah kabur ke base
-- orang lain dan mencoba mencuri telur milik pemain, bukan telur liar di zona.
-- Kembalikan: inPlot, milikPlotSaya
local function plotState(obj)
  local plots = Workspace:FindFirstChild("Plots")
  if not plots then return false, false end
  local p = obj and obj.Parent
  while p and p ~= Workspace do
    if p.Parent == plots then
      return true, plotOwnerIsMe(p)
    end
    p = p.Parent
  end
  return false, false
end

-- Telur yang sedang DIBAWA pemain lain juga milik orang: karakter yang
-- memegangnya akan dikejar kalau tidak disaring — itu laporan nyata kedua.
local function heldByOther(obj)
  local p = obj and obj.Parent
  while p and p ~= Workspace do
    if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then
      local pl = Players:GetPlayerFromCharacter(p)
      if pl then return pl ~= LP end
    end
    p = p.Parent
  end
  return false
end

local function myBase()
  if tick() - baseCacheT < 5 then return baseCache end

  -- game nyata: plot pemain ada di workspace.Plots (terverifikasi Agu 2026)
  local plots = Workspace:FindFirstChild("Plots")
  if plots then
    for _, plot in ipairs(plots:GetChildren()) do
      if (plot:IsA("Model") or plot:IsA("BasePart")) and plotOwnerIsMe(plot) then
        local p = posOf(plot) or (plot:IsA("Model") and plot:GetPivot().Position)
        if p then baseCache, baseCacheT = p, tick(); return p end
      end
    end
    -- tanpa penanda pemilik: plot terdekat ke spawn kita (pemain lahir di plot sendiri)
    local best, bestD = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
      local sp = plot:FindFirstChild("SpawnLocation")
      if sp and sp:IsA("BasePart") then
        local d = math.abs(sp.Position.X) + math.abs(sp.Position.Z)
        if d < bestD then bestD, best = d, sp.Position end
      end
    end
    if best then baseCache, baseCacheT = best, tick(); return best end
  end

  -- cadangan: objek bernama base/plot/garden dengan penanda pemain (game lain)
  for _, v in ipairs(Workspace:GetDescendants()) do
    local n = lower(v.Name)
    if (v:IsA("BasePart") or v:IsA("Model")) and (n:find("base") or n:find("plot") or n:find("garden")) then
      for _, key in ipairs({ "Owner", "OwnerName", "Player", "PlayerName" }) do
        local o = v:FindFirstChild(key)
        if o and o:IsA("ValueBase") and tostring(o.Value) == LP.Name then
          local p = posOf(v) or (v:IsA("Model") and v:GetPivot().Position)
          if p then baseCache, baseCacheT = p, tick(); return p end
        end
      end
      for _, d in ipairs(v:GetDescendants()) do
        if d:IsA("TextLabel") and tostring(d.Text):find(LP.Name) then
          local p = posOf(v)
          if p then baseCache, baseCacheT = p, tick(); return p end
        end
      end
    end
  end
  local sp = Workspace:FindFirstChildOfClass("SpawnLocation")
  return sp and sp.Position or nil
end

-- ============ TELUR GAME NYATA (v6) ============
-- Game ini TIDAK menamai telurnya "Egg": telur hidup di
-- workspace.AreaEggSlotsClient (tiap slot punya part "Plane"), telur event
-- berdiri sendiri dengan anak "Hitbox", telur langka bertanda
-- "RareAreaEggHighlight", telur parasit "MonsterParasiteVisual". Versi lama
-- mencari nama 'egg' → tidak menemukan apa pun → "pet tidak ada di database".
local function eggFromEntry(entryObj, kind, rare)
  local part = entryObj:FindFirstChild("Plane") or firstPartOf(entryObj)
  if not (part and part:IsA("BasePart")) then return nil end
  local pos = part.Position
  local rar, key = rarityOf(entryObj)
  local inc, petName, biome = incomeOf(entryObj, key)
  local mut = mutationOf(entryObj)
  local mine = false
  local bpos = myBase()
  if bpos and dist(pos, bpos) < S.baseGuard then mine = true end
  local ap = entryObj.Parent
  while ap and ap ~= Workspace do
    if ap == LP.Character then mine = true break end
    ap = ap.Parent
  end
  local inPlot, myPlot = plotState(entryObj)
  if myPlot then mine = true end
  local owned = inPlot or heldByOther(entryObj)
  return {
    obj    = entryObj,
    part   = part,
    pos    = pos,
    rar    = rar,
    key    = key,
    pet    = petName,
    biome  = biome or zoneOf(pos),
    income = inc,
    mut    = mut,
    mult   = mut and MUT_MULT[mut] or 1,
    wt     = weightOf(entryObj),
    mine   = mine,
    owned  = owned,      -- telur ini milik/dipegang pemain lain
    rare   = rare or false,
    kind   = kind,
  }
end

local function scanSlotEggs()
  local out = {}
  local sl = Workspace:FindFirstChild("AreaEggSlotsClient")
  if sl then
    for _, s in ipairs(sl:GetChildren()) do
      local e = eggFromEntry(s, nil, s:FindFirstChild("RareAreaEggHighlight") ~= nil)
      if e then
        if s:FindFirstChild("MonsterParasiteVisual") then e.kind = "parasite" end
        out[#out + 1] = e
      end
    end
  end
  -- telur event: objek Workspace berdiri sendiri dengan anak Hitbox
  for _, obj in ipairs(Workspace:GetChildren()) do
    if obj:IsA("Model") and obj:FindFirstChild("Hitbox") then
      local e = eggFromEntry(obj, "event", findNamed(obj, "RareAreaEggHighlight") ~= nil)
      if e then
        if findNamed(obj, "MonsterParasiteVisual") then e.kind = "parasite" end
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- Telur milik sendiri (sudah di base) ditandai `mine` supaya loop steal tidak
-- memilihnya lagi — itu penyebab "mundar-mandir di base".
local function scanEggs()
  local out = {}
  local seen = {}
  local base = myBase()

  -- 1. telur game nyata (slot AreaEggSlotsClient + telur event) — lihat v6 di atas
  for _, e in ipairs(scanSlotEggs()) do
    seen[e.obj] = true
    if e.part then seen[e.part] = true end
    out[#out + 1] = e
  end

  -- 2. deteksi nama generik (game/event lain): nama memuat 'egg' atau cocok db
  for _, v in ipairs(Workspace:GetDescendants()) do
    if (v:IsA("Model") or v:IsA("BasePart")) and not seen[v] then
      local nameHit = isEggName(v.Name)
      local dbHit = dbExact(v.Name) or dbStripMutation(v.Name)
      if nameHit or dbHit then
        local parentListed = false
        local p = v.Parent
        while p and p ~= Workspace do
          if seen[p] then parentListed = true break end
          p = p.Parent
        end
        if not parentListed then
          local pos = posOf(v)
          if pos then
            seen[v] = true
            local rar, key = rarityOf(v)
            local inc, petName, biome = incomeOf(v, key)
            local mut = mutationOf(v)
            -- apakah telur ini sudah ada di base sendiri / sedang dibawa?
            local mine = false
            if base and dist(pos, base) < S.baseGuard then mine = true end
            local ap = v.Parent
            while ap and ap ~= Workspace do
              if ap == LP.Character then mine = true break end
              ap = ap.Parent
            end
            local inPlot, myPlot = plotState(v)
            if myPlot then mine = true end
            out[#out + 1] = {
              obj    = v,
              pos    = pos,
              rar    = rar,
              key    = key,
              pet    = petName,
              biome  = biome or zoneOf(pos),
              income = inc,
              mut    = mut,
              mult   = mut and MUT_MULT[mut] or 1,
              wt     = weightOf(v),
              mine   = mine,
              owned  = inPlot or heldByOther(v),
            }
          end
        end
      end
    end
  end
  return out
end

local function scanTraps()
  local out = {}
  for _, v in ipairs(Workspace:GetDescendants()) do
    local n = lower(v.Name)
    if v:IsA("BasePart") or v:IsA("Model") then
      if n:find("trap") or n:find("spike") or n:find("mine") or n:find("net")
         or n:find("snare") or n:find("bomb") then
        local p = posOf(v)
        if p then out[#out + 1] = { obj = v, pos = p } end
      end
    end
  end
  return out
end

local function scanHostiles()
  local out = {}
  for _, v in ipairs(Workspace:GetDescendants()) do
    if v:IsA("Model") and v:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(v) then
      local n = lower(v.Name)
      local kind = (n:find("bat") and "bat")
        or ((n:find("guard") or n:find("guardian")) and "guard")
        or ((n:find("beast") or n:find("boss")) and "beast")
        or nil
      if kind then
        local p = posOf(v)
        if p then out[#out + 1] = { obj = v, pos = p, kind = kind } end
      end
    end
  end
  return out
end


-- ============ REMOTE ============
local remotes = {}
local function indexRemotes()
  remotes = {}
  local roots = { RS, Workspace }
  local pg = LP:FindFirstChild("PlayerGui"); if pg then roots[#roots + 1] = pg end
  for _, root in ipairs(roots) do
    for _, r in ipairs(root:GetDescendants()) do
      if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
        remotes[#remotes + 1] = r
      end
    end
  end
  return #remotes
end
indexRemotes()

local function fireMatch(words, ...)
  local args = table.pack(...)
  local n = 0
  for _, r in ipairs(remotes) do
    local nm = lower(r.Name)
    for _, w in ipairs(words) do
      if nm:find(w, 1, true) then
        pcall(function()
          if r:IsA("RemoteEvent") then
            r:FireServer(table.unpack(args, 1, args.n))
          else
            r:InvokeServer(table.unpack(args, 1, args.n))
          end
        end)
        n = n + 1
        break
      end
    end
  end
  return n
end

-- cari remote berdasar nama persis — dipakai memuat resep tersimpan
local function findRemoteByName(name)
  if not name then return nil end
  indexRemotes()
  for _, r in ipairs(remotes) do
    if r.Name == name then return r end
  end
  return nil
end

-- SmartPromptPart: game ini MEMUSATKAN prompt ambil di sini (bukan prompt di
-- dalam telur). Tanpa menembaknya, mendekat + sentuh saja tidak pernah
-- mengambil apa pun. HoldDuration dinolkan dulu: dengan nilai bawaan,
-- fireproximityprompt sering tidak berefek.
local function fireSmartPrompts()
  local n = 0
  for _, c in ipairs(Workspace:GetChildren()) do
    if c.Name == "SmartPromptPart" then
      for _, p in ipairs(c:GetChildren()) do
        if p:IsA("ProximityPrompt") then
          pcall(function()
            p.Enabled = true
            p.MaxActivationDistance = math.max(p.MaxActivationDistance or 0, 60)
            p.RequiresLineOfSight = false
            p.HoldDuration = 0
            fireproximityprompt(p)
          end)
          n = n + 1
        end
      end
    end
  end
  return n
end

-- tekan prompt: HoldDuration harus dinolkan dulu, kalau tidak
-- fireproximityprompt sering tidak menghasilkan apa pun
local function pressPromptsNear(radius)
  local h = hrp(); if not h then return 0 end
  local n = 0
  for _, p in ipairs(Workspace:GetDescendants()) do
    if p:IsA("ProximityPrompt") then
      local pp = partOf(p.Parent)
      if pp and dist(h.Position, pp.Position) <= (radius or 24) then
        pcall(function()
          p.Enabled = true
          p.MaxActivationDistance = math.max(p.MaxActivationDistance or 0, 60)
          p.RequiresLineOfSight = false
          p.HoldDuration = 0
          fireproximityprompt(p)
        end)
        n = n + 1
      end
    end
  end
  return n
end

local function touchPart(part)
  local h = hrp(); if not (h and part) then return end
  pcall(function()
    firetouchinterest(h, part, 0)
    task.wait(0.03)
    firetouchinterest(h, part, 1)
    task.wait(0.03)
    firetouchinterest(h, part, 0)
    task.wait(0.03)
    firetouchinterest(h, part, 1)
  end)
end

-- ============ GERAK: HOP = TERBANG DATAR (Y TERKUNCI) ============
-- Koreksi: pengguna memang mau melayang, tapi LURUS/datar — bukan naik ke
-- langit, dan bukan jalan kaki lambat seperti v3.
-- BodyVelocity dengan Y = 0 membuat karakter meluncur horizontal di ketinggian
-- yang sama. PlatformStand tidak dipakai (itu penyebab ragdoll di v2), dan saat
-- berhenti kecepatan dinolkan lebih dulu supaya tidak terhuyung.

local moving = false
local flyBV = nil

local function clearMoveHelpers()
  local h = hrp()
  if h then
    for _, c in ipairs(h:GetChildren()) do
      if c:IsA("BodyVelocity") or c:IsA("BodyGyro") or c:IsA("BodyPosition")
        or c:IsA("AlignPosition") or c:IsA("LinearVelocity") then
        c:Destroy()
      end
    end
  end
  flyBV = nil
end

local function stopGlide()
  moving = false
  clearMoveHelpers()
  local h = hrp()
  if h then h.Velocity = Vector3.new(0, 0, 0) end
  local hu = hum()
  if hu then
    hu.PlatformStand = false
    hu.AutoRotate = true
  end
end

-- pergeseran hindar: selalu horizontal, tidak pernah menambah ketinggian
local function avoidOffset(from)
  local off = Vector3.new(0, 0, 0)
  local r = S.avoidRadius
  if S.antiTrap then
    for _, t in ipairs(scanTraps()) do
      local d = from - t.pos
      local m = d.Magnitude
      if m < r and m > 0.1 then off = off + d.Unit * (r - m) end
    end
  end
  if S.antiBat then
    for _, mo in ipairs(scanHostiles()) do
      local d = from - mo.pos
      local m = d.Magnitude
      if m < r and m > 0.1 then off = off + d.Unit * (r - m) * 1.3 end
    end
  end
  return Vector3.new(off.X, 0, off.Z)
end

-- terbang datar ke target
local function hopTo(target, timeout, speedOverride)
  local h = hrp()
  local hu = hum()
  if not (h and hu) then return false end
  timeout = timeout or 25
  moving = true

  local spd = math.clamp(speedOverride or S.speed, 16, 1000)
  hu.PlatformStand = false

  if not (flyBV and flyBV.Parent) then
    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "SAE_Fly"
    flyBV.MaxForce = Vector3.new(1e7, 1e7, 1e7)
    flyBV.P = 12500
    flyBV.Velocity = Vector3.new(0, 0, 0)
    flyBV.Parent = h
  end

  local t0 = tick()
  local lastPos, lastCheck = h.Position, tick()

  while moving and alive() and tick() - t0 < timeout do
    local cur = hrp()
    if not cur then break end

    local flat = Vector3.new(target.X - cur.Position.X, 0, target.Z - cur.Position.Z)
    local dy = target.Y - cur.Position.Y
    if flat.Magnitude < 4 and math.abs(dy) < 10 then break end

    local dir = (flat.Magnitude > 0.1) and flat.Unit or Vector3.new(0, 0, 0)
    local push = avoidOffset(cur.Position)
    if push.Magnitude > 0.1 then
      dir = dir + push.Unit * 0.8
      if dir.Magnitude > 0 then dir = dir.Unit end
    end

    -- vertikal HANYA untuk menyamakan ketinggian target, dibatasi 18 stud/s
    -- supaya tidak pernah melesat ke atas
    local vy = 0
    if math.abs(dy) > 8 then vy = math.clamp(dy, -18, 18) end

    if flyBV and flyBV.Parent then
      flyBV.Velocity = Vector3.new(dir.X * spd, vy, dir.Z * spd)
    end

    -- nyangkut: 2 detik hampir tak bergerak → naik sedikit sekali untuk lewat
    if tick() - lastCheck > 2 then
      if (cur.Position - lastPos).Magnitude < 6 and flyBV and flyBV.Parent then
        flyBV.Velocity = Vector3.new(dir.X * spd, 16, dir.Z * spd)
      end
      lastPos, lastCheck = cur.Position, tick()
    end

    task.wait(0.06)
  end

  moving = false
  if flyBV and flyBV.Parent then flyBV.Velocity = Vector3.new(0, 0, 0) end
  clearMoveHelpers()
  local h2 = hrp()
  if h2 then h2.Velocity = Vector3.new(0, 0, 0) end
  local hu2 = hum()
  if hu2 then hu2.PlatformStand = false end
  return true
end

-- mode jalan kaki: pilihan, bukan default
local function walkTo(target, timeout, speedOverride)
  local hu = hum()
  local h = hrp()
  if not (hu and h) then return false end
  timeout = timeout or 25
  moving = true
  local spd = math.clamp(speedOverride or S.speed, 8, 1000)
  hu.PlatformStand = false
  local t0 = tick()
  while moving and alive() and tick() - t0 < timeout do
    local cur = hrp(); if not cur then break end
    local flat = Vector3.new(target.X - cur.Position.X, 0, target.Z - cur.Position.Z)
    if flat.Magnitude < 5 then break end
    hu.WalkSpeed = spd
    hu:MoveTo(target + avoidOffset(cur.Position))
    task.wait(0.12)
  end
  moving = false
  local hu2 = hum()
  if hu2 then
    hu2.PlatformStand = false
    if not S.speedOn then hu2.WalkSpeed = 16 end
  end
  return true
end

-- satu pintu masuk: default terbang datar, jalan kaki kalau S.walkMode
local function moveTo(target, timeout, speedOverride)
  if S.walkMode then return walkTo(target, timeout, speedOverride) end
  return hopTo(target, timeout, speedOverride)
end
local glideTo = moveTo

-- ============ PILIH TELUR ============
local function anyRarityPicked()
  for _, v in pairs(S.rarityPick) do if v then return true end end
  return false
end

local function eggScore(e)
  local mult = e.mult or (e.mut and MUT_MULT[e.mut]) or 1
  local s = 0
  if e.income then
    s = math.log(math.max(e.income, 1) * mult) * 1000
  else
    local idx = 0
    if e.rar then
      for i, r in ipairs(RARITY) do if r == e.rar then idx = i break end end
    end
    s = idx * 1000
  end
  if S.preferMutasi and e.mut then s = s + (mult - 1) * 900 end
  -- telur bertanda RareAreaEggHighlight / parasit diprioritaskan walau
  -- rarity-nya belum terbaca database
  if e.rare then s = s + 50000 end
  if e.kind == "parasite" then s = s + 10000 end
  s = s + math.min((e.wt or 0) / 100000, 400)
  return s
end

-- Telur yang sudah ada di base sendiri BUKAN sasaran. Ini penyebab
-- "mundar-mandir di base": telur yang sudah disetor terus dipilih lagi.
local function nearOwnBase(pos)
  local b = myBase()
  if not b then return false end
  return dist(pos, b) < S.baseGuard
end

local function pickEgg()
  local h = hrp(); if not h then return nil end
  local filter = anyRarityPicked()
  local best, bestScore = nil, -math.huge
  for _, e in ipairs(scanEggs()) do
    local okRar = true
    if filter then
      -- telur belum dikenal tetap boleh kalau S.takeUnknown menyala
      if e.rar == nil then okRar = S.takeUnknown
      else okRar = S.rarityPick[e.rar] == true end
    end
    local okWt = (S.minWeight <= 0) or ((e.wt or 0) >= S.minWeight)
    local okInc = (S.minIncome <= 0) or ((e.income or 0) >= S.minIncome)
    -- telur di base pemain lain hanya kalau pengguna menyalakannya sendiri:
    -- default hanya telur liar di zona (laporan nyata: steal kabur ke base orang)
    local okPlot = S.takePlots or not e.owned
    if okRar and okWt and okInc and okPlot and not e.mine and not nearOwnBase(e.pos) then
      local d = dist(h.Position, e.pos)
      if d <= S.maxRange then
        local sc = eggScore(e) - d * 0.08
        if sc > bestScore then bestScore, best = sc, e end
      end
    end
  end
  return best
end


-- ============ PEREKAM CARA AMBIL (remote spy) ============
-- Dua versi sebelumnya MENEBAK nama remote ("steal", "pickup", ...) dan gagal.
-- Menebak bukan jalan keluar. Modul ini MEREKAM apa yang benar-benar terjadi
-- saat pengguna mengambil telur dengan tangan sendiri:
--   · setiap RemoteEvent/RemoteFunction yang ditembak klien, beserta argumennya
--   · ProximityPrompt mana yang benar-benar terpicu
--   · apakah pengambilan terjadi TANPA remote sama sekali (murni sentuhan)
-- Lalu hasil rekaman itu diputar ulang apa adanya untuk auto steal.

local SPY = {
  hooked     = false,
  recording  = false,
  log        = {},        -- {t, name, method, args, argdesc, path}
  prompts    = {},        -- {t, name, path}
  learned    = nil,       -- {name, method, template, path}
  learnedFrom= nil,       -- "remote" | "prompt" | "touch"
  note       = "belum merekam",
  fires      = 0,
  lastPickup = nil,
  onDisk     = false,     -- resep tersimpan di berkas executor?
}

local MAXLOG = 60

-- Deteksi Instance tanpa bergantung pada typeof(): di beberapa lingkungan
-- typeof tidak ada, dan tebakan lewat type() mengembalikan "table" sehingga
-- objek telur tidak dikenali di argumen — itu membuat resep salah bentuk.
local function isInstance(v)
  if typeof and typeof(v) == "Instance" then return true end
  if type(v) ~= "table" and type(v) ~= "userdata" then return false end
  local ok, res = pcall(function()
    return v.ClassName ~= nil and type(v.IsA) == "function"
  end)
  return ok and res == true
end

local function isDescendantOf(v, root)
  if not (isInstance(v) and root) then return false end
  local ok, res = pcall(function() return v:IsDescendantOf(root) end)
  if ok then return res == true end
  -- cadangan: jalan naik rantai induk sendiri
  local ok2, res2 = pcall(function()
    local p = v.Parent
    while p do
      if p == root then return true end
      p = p.Parent
    end
    return false
  end)
  return ok2 and res2 == true
end

local function pathOf(inst)
  local parts, n = {}, inst
  local hops = 0
  while n and hops < 6 do
    table.insert(parts, 1, n.Name)
    n = n.Parent
    hops = hops + 1
  end
  return table.concat(parts, ".")
end

local function describeArg(v)
  if isInstance(v) then
    local cn, nm = "?", "?"
    pcall(function() cn = tostring(v.ClassName); nm = tostring(v.Name) end)
    return "Instance(" .. cn .. ":" .. nm .. ")"
  end
  local t = type(v)
  if t == "string" then
    return '"' .. tostring(v):sub(1, 24) .. '"'
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = tostring(k)
      if #keys >= 4 then break end
    end
    return "table{" .. table.concat(keys, ",") .. "}"
  end
  return t .. "(" .. tostring(v):sub(1, 20) .. ")"
end

local function describeArgs(args)
  local d = {}
  for i = 2, args.n do d[#d + 1] = describeArg(args[i]) end
  return table.concat(d, ", ")
end

-- Ubah argumen rekaman menjadi cetakan (template) yang bisa dipakai ulang.
-- Argumen yang menunjuk telur diganti placeholder, sisanya dipakai apa adanya.
local function buildTemplate(args, eggObj)
  local tpl = {}
  for i = 2, args.n do
    local v = args[i]
    local slot
    if v == eggObj then
      slot = { kind = "egg" }
    elseif isDescendantOf(v, eggObj) then
      slot = { kind = "egg" }
    elseif eggObj and type(v) == "string" and v == eggObj.Name then
      slot = { kind = "eggname" }
    elseif type(v) == "table" and not isInstance(v) then
      -- salin dangkal, tukar nilai yang menunjuk telur
      local copy = {}
      for k, vv in pairs(v) do
        if vv == eggObj then copy[k] = "__EGG__"
        elseif eggObj and type(vv) == "string" and vv == eggObj.Name then copy[k] = "__EGGNAME__"
        else copy[k] = vv end
      end
      slot = { kind = "table", value = copy }
    else
      slot = { kind = "literal", value = v }
    end
    tpl[#tpl + 1] = slot
  end
  return tpl
end

local function fillTemplate(tpl, eggObj)
  local out = {}
  for i, slot in ipairs(tpl) do
    if slot.kind == "egg" then
      out[i] = eggObj
    elseif slot.kind == "eggname" then
      out[i] = eggObj and eggObj.Name or ""
    elseif slot.kind == "table" then
      local copy = {}
      for k, v in pairs(slot.value) do
        if v == "__EGG__" then copy[k] = eggObj
        elseif v == "__EGGNAME__" then copy[k] = eggObj and eggObj.Name or ""
        else copy[k] = v end
      end
      out[i] = copy
    else
      out[i] = slot.value
    end
  end
  return out, #tpl
end

local function describeTemplate(tpl)
  local d = {}
  for _, s in ipairs(tpl) do
    if s.kind == "egg" then d[#d + 1] = "<telur>"
    elseif s.kind == "eggname" then d[#d + 1] = "<nama telur>"
    elseif s.kind == "table" then d[#d + 1] = "table"
    else d[#d + 1] = describeArg(s.value) end
  end
  return table.concat(d, ", ")
end

-- ---------- pemasangan hook ----------
local function recordFire(remote, method, args)
  SPY.fires = SPY.fires + 1
  local entry = {
    t       = tick(),
    name    = remote.Name,
    method  = method,
    args    = args,
    argdesc = describeArgs(args),
    path    = pathOf(remote),
    remote  = remote,
  }
  table.insert(SPY.log, 1, entry)
  while #SPY.log > MAXLOG do table.remove(SPY.log) end
  return entry
end

-- Jalur suntik untuk harness uji. Di Roblox, recordFire dipanggil dari hook
-- __namecall; harness tidak bisa memasang hook itu, jadi ia memakai pintu ini.
function SPY.recordForTest(remote, method, args)
  return recordFire(remote, method, args)
end

function SPY.install()
  if SPY.hooked then return true, "sudah terpasang" end

  -- jalur utama: hookmetamethod pada __namecall (didukung Delta/Synapse/dll)
  local okHook = false
  pcall(function()
    if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
      local old
      old = hookmetamethod(game, "__namecall", function(self, ...)
        local m = getnamecallmethod()
        if (m == "FireServer" or m == "InvokeServer") and SPY.recording then
          -- table.pack di sini, JANGAN '...' di dalam closure pcall
          local packed = table.pack(self, ...)
          pcall(function()
            if self and self.IsA and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
              recordFire(self, m, packed)
            end
          end)
        end
        return old(self, ...)
      end)
      okHook = true
    end
  end)

  -- jalur cadangan: ganti metatable mentah
  if not okHook then
    pcall(function()
      local mt = getrawmetatable and getrawmetatable(game)
      if mt and setreadonly then
        setreadonly(mt, false)
        local oldNC = mt.__namecall
        mt.__namecall = function(self, ...)
          local m = getnamecallmethod and getnamecallmethod() or ""
          if (m == "FireServer" or m == "InvokeServer") and SPY.recording then
            local packed = table.pack(self, ...)
            pcall(function()
              if self and self.IsA and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                recordFire(self, m, packed)
              end
            end)
          end
          return oldNC(self, ...)
        end
        setreadonly(mt, true)
        okHook = true
      end
    end)
  end

  -- hook prompt: catat prompt mana yang benar-benar terpicu
  pcall(function()
    for _, p in ipairs(Workspace:GetDescendants()) do
      if p:IsA("ProximityPrompt") then
        p.Triggered:Connect(function()
          if SPY.recording then
            table.insert(SPY.prompts, 1, { t = tick(), name = p.Parent and p.Parent.Name or "?", path = pathOf(p) })
            while #SPY.prompts > 20 do table.remove(SPY.prompts) end
          end
        end)
      end
    end
  end)

  SPY.hooked = okHook
  SPY.note = okHook and "hook terpasang" or "executor tidak mendukung hook remote"
  return okHook, SPY.note
end

-- ---------- belajar dari rekaman ----------
-- Dipanggil saat terdeteksi telur BERHASIL terambil oleh pengguna.
function SPY.learnFrom(eggObj, sinceT)
  sinceT = sinceT or (tick() - 4)

  -- 1. remote yang argumennya menyebut telur ini -> paling meyakinkan
  for _, e in ipairs(SPY.log) do
    if e.t >= sinceT then
      for i = 2, e.args.n do
        local v = e.args[i]
        local hit = (v == eggObj)
        if not hit and type(v) == "string" and eggObj and v == eggObj.Name then hit = true end
        if not hit and isDescendantOf(v, eggObj) then hit = true end
        if hit then
          SPY.learned = {
            name = e.name, method = e.method, path = e.path,
            remote = e.remote,
            template = buildTemplate(e.args, eggObj),
          }
          SPY.learnedFrom = "remote"
          SPY.note = "belajar: " .. e.name .. "(" .. describeTemplate(SPY.learned.template) .. ")"
          return true
        end
      end
    end
  end

  -- 2. remote terakhir sebelum telur terambil, walau argumennya tidak menyebut telur
  for _, e in ipairs(SPY.log) do
    if e.t >= sinceT then
      SPY.learned = {
        name = e.name, method = e.method, path = e.path,
        remote = e.remote,
        template = buildTemplate(e.args, eggObj),
      }
      SPY.learnedFrom = "remote"
      SPY.note = "belajar (tanpa arg telur): " .. e.name
      return true
    end
  end

  -- 3. tidak ada remote: prompt?
  for _, p in ipairs(SPY.prompts) do
    if p.t >= sinceT then
      SPY.learned = nil
      SPY.learnedFrom = "prompt"
      SPY.note = "ambil lewat ProximityPrompt di " .. p.name .. " (tanpa remote)"
      return true
    end
  end

  -- 4. benar-benar tanpa apa pun: murni sentuhan / server-side
  SPY.learned = nil
  SPY.learnedFrom = "touch"
  SPY.note = "tidak ada remote & prompt — pengambilan murni sentuhan; yang penting mendekat"
  return true
end

-- putar ulang cara yang sudah dipelajari
function SPY.replay(eggObj)
  local L = SPY.learned
  if not L then return false end
  local ok = false
  pcall(function()
    local r = L.remote
    if not (r and r.Parent) then return end
    local args, n = fillTemplate(L.template, eggObj)
    if L.method == "InvokeServer" then
      r:InvokeServer(table.unpack(args, 1, n))
    else
      r:FireServer(table.unpack(args, 1, n))
    end
    ok = true
  end)
  return ok
end

-- ---------- PERSISTENSI (v6) ----------
-- Keluhan "masa harus diajari terus": sekarang resep hasil AJARI ditulis ke
-- berkas executor (writefile) dan dimuat ulang otomatis saat script jalan
-- lagi di lain waktu. AJARI cukup sekali.
local RECIPE_FILE = "SAE_Recipe.lua"

local function litOut(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if v == nil then return "nil" end
  return nil            -- Instance/func/tabel dalam: tidak bisa disimpan
end

local function slotStorable(slot)
  if slot.kind == "egg" or slot.kind == "eggname" then return true end
  if slot.kind == "literal" then return litOut(slot.value) ~= nil end
  if slot.kind == "table" then
    for k, v in pairs(slot.value) do
      if litOut(k) == nil or litOut(v) == nil then return false end
    end
    return true
  end
  return false
end

function SPY.saveRecipe()
  local L = SPY.learned
  if not (L and L.template and L.name and L.method) then return false end
  if type(writefile) ~= "function" then return false end
  local parts = {}
  for i, slot in ipairs(L.template) do
    if not slotStorable(slot) then return false end
    if slot.kind == "egg" then
      parts[i] = '{kind="egg"}'
    elseif slot.kind == "eggname" then
      parts[i] = '{kind="eggname"}'
    elseif slot.kind == "table" then
      local kv = {}
      for k, v in pairs(slot.value) do
        kv[#kv + 1] = "[" .. litOut(k) .. "]=" .. litOut(v)
      end
      parts[i] = '{kind="table", value={' .. table.concat(kv, ",") .. '}}'
    else
      parts[i] = '{kind="literal", value=' .. litOut(slot.value) .. '}'
    end
  end
  local src = "return {name=" .. string.format("%q", L.name)
    .. ", method=" .. string.format("%q", L.method)
    .. ", template={" .. table.concat(parts, ",") .. "}}"
  local ok = pcall(writefile, RECIPE_FILE, src)
  if ok then SPY.onDisk = true end
  return ok
end

function SPY.loadRecipe()
  SPY.onDisk = false
  if not (type(readfile) == "function" and type(isfile) == "function"
    and type(loadstring) == "function") then return false end
  local ok, exists = pcall(isfile, RECIPE_FILE)
  if not (ok and exists) then return false end
  local ok2, src = pcall(readfile, RECIPE_FILE)
  if not (ok2 and type(src) == "string") then return false end
  local okc, chunk = pcall(loadstring, src)
  if not (okc and type(chunk) == "function") then return false end
  local okr, data = pcall(chunk)
  if not (okr and type(data) == "table" and data.name and data.method
    and type(data.template) == "table") then return false end
  for _, slot in ipairs(data.template) do
    if not (type(slot) == "table" and slot.kind) then return false end
  end
  -- remote diselesaikan ulang lewat nama: path bisa berubah antar update game
  local remote = findRemoteByName(data.name)
  if not remote then return false end
  SPY.learned = { name = data.name, method = data.method,
    remote = remote, template = data.template }
  SPY.learnedFrom = "remote"
  SPY.onDisk = true
  SPY.note = "resep dimuat dari berkas: " .. data.name
  return true
end

pcall(function() SPY.loadRecipe() end)

function SPY.summary()
  local lines = {}
  lines[#lines + 1] = "status : " .. SPY.note
  lines[#lines + 1] = "hook   : " .. (SPY.hooked and "aktif" or "TIDAK aktif")
  lines[#lines + 1] = "rekam  : " .. (SPY.recording and "MENYALA" or "mati")
  lines[#lines + 1] = "tembakan tercatat: " .. SPY.fires
  lines[#lines + 1] = "berkas : " .. (SPY.onDisk and "resep tersimpan (dimuat otomatis)" or "belum ada resep tersimpan")
  if SPY.learned then
    lines[#lines + 1] = "dipakai: " .. SPY.learned.name
      .. ":" .. SPY.learned.method
      .. "(" .. describeTemplate(SPY.learned.template) .. ")"
  elseif SPY.learnedFrom then
    lines[#lines + 1] = "dipakai: cara " .. SPY.learnedFrom
  end
  if #SPY.log > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "remote terakhir:"
    for i = 1, math.min(6, #SPY.log) do
      local e = SPY.log[i]
      lines[#lines + 1] = "  " .. e.name .. "(" .. e.argdesc:sub(1, 46) .. ")"
    end
  end
  return table.concat(lines, "\n")
end


-- ============ PREDIKSI SIKLUS TELUR ============
-- Jujur soal batasnya: spawn Secret/Eternal/Divine di Steal An Egg adalah
-- UNDIAN ACAK tiap reset (±5 menit), bukan jadwal tetap. Jadi "Divine jam 14:32"
-- tidak bisa dijanjikan siapa pun. Yang BISA nyata:
--   1. periode reset diukur sendiri dari perubahan isi map  -> waktu reset berikutnya presisi
--   2. deteksi instan begitu telur langka muncul (+ lokasi, jarak, ETA)
--   3. peluang empiris dari reset yang benar-benar tercatat  -> perkiraan waktu tunggu
--   4. probe state "telur berikutnya" kalau server memang mereplikasi datanya
-- Tidak ada angka yang dikarang. Sebelum ada data, tampilannya kosong.

local PRED = {
  watch      = false,
  autoGo     = false,
  notify     = { Secret = true, Eternal = true, Divine = true },

  period     = nil,      -- detik, hasil ukur sendiri
  lastReset  = nil,      -- tick() reset terakhir
  resetTimes = {},       -- riwayat tick() reset
  observed   = 0,        -- jumlah reset tercatat
  counts     = {},       -- rarity -> berapa reset memuat rarity itu
  seenNames  = {},       -- rarity -> nama telur terakhir
  alerts     = {},       -- temuan langka terbaru
  probe      = nil,      -- hasil probe state next-egg
  sig        = nil,      -- sidik jari isi map
  liveTimer  = nil,      -- hitung mundur bawaan game kalau ketemu
  announces  = 0,        -- jumlah pengumuman server tertangkap
  lastAnn    = nil,
}

local function fmtDur(s)
  if not s then return "-" end
  s = math.max(0, math.floor(s))
  if s < 60 then return s .. "s" end
  if s < 3600 then return string.format("%dm %02ds", s // 60, s % 60) end
  if s < 86400 then return string.format("%dj %02dm", s // 3600, (s % 3600) // 60) end
  return string.format("%dh %02dj", s // 86400, (s % 86400) // 3600)
end

-- sidik jari isi map: nama + posisi dibulatkan
local function eggSignature()
  local eggs = scanEggs()
  local ids = {}
  for _, e in ipairs(eggs) do
    ids[#ids + 1] = e.obj.Name .. "@" .. math.floor(e.pos.X) .. "," .. math.floor(e.pos.Z)
  end
  table.sort(ids)
  return table.concat(ids, ";"), eggs
end

local function setFromList(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

local function splitSig(sig)
  local out = {}
  if not sig then return out end
  for part in string.gmatch(sig, "[^;]+") do out[#out + 1] = part end
  return out
end

-- seberapa mirip dua isi map (0 = beda total, 1 = sama)
local function similarity(a, b)
  local la, lb = splitSig(a), splitSig(b)
  if #la == 0 and #lb == 0 then return 1 end
  local sa = setFromList(la)
  local inter = 0
  for _, v in ipairs(lb) do if sa[v] then inter = inter + 1 end end
  local union = #la + #lb - inter
  if union == 0 then return 1 end
  return inter / union
end

-- hitung mundur bawaan game: cari label m:ss / NNs dekat kata reset/night/egg
local function findLiveTimer()
  local best = nil
  local function consider(txt)
    if type(txt) ~= "string" then return end
    local m, s = txt:match("^%s*(%d+):(%d%d)%s*$")
    if m then
      local v = tonumber(m) * 60 + tonumber(s)
      if v <= 900 then best = best or v end
      return
    end
    local only = txt:match("^%s*(%d+)%s*[sS]%s*$")
    if only then
      local v = tonumber(only)
      if v <= 900 then best = best or v end
    end
  end
  local pg = LP:FindFirstChild("PlayerGui")
  if pg then
    for _, d in ipairs(pg:GetDescendants()) do
      if d:IsA("TextLabel") then consider(d.Text) end
    end
  end
  for _, d in ipairs(Workspace:GetDescendants()) do
    if d:IsA("TextLabel") then consider(d.Text) end
  end
  return best
end

-- periode = median selisih antar reset yang tercatat
local function computePeriod()
  local t = PRED.resetTimes
  if #t < 2 then return nil end
  local diffs = {}
  for i = 2, #t do diffs[#diffs + 1] = t[i] - t[i - 1] end
  table.sort(diffs)
  local mid = #diffs // 2 + 1
  local med = (#diffs % 2 == 1) and diffs[mid] or ((diffs[mid - 1] + diffs[mid]) / 2)
  return med, #diffs
end

-- reset berikutnya: pakai timer game kalau ada, kalau tidak pakai periode terukur
local function nextResetIn()
  if PRED.liveTimer then return PRED.liveTimer, "timer game" end
  if PRED.period and PRED.lastReset then
    local left = PRED.period - (tick() - PRED.lastReset)
    while left < 0 do left = left + PRED.period end
    return left, "periode terukur"
  end
  return nil, "belum cukup data"
end

-- peluang & perkiraan tunggu untuk satu rarity — nil kalau datanya belum ada
local function odds(rar)
  local n = PRED.observed
  if n < 1 then return nil, 0, 0 end
  local c = PRED.counts[rar] or 0
  if c == 0 then return nil, n, 0 end
  local rate = c / n
  local per = PRED.period or 300
  return per / rate, n, rate
end

local function pushAlert(e, source)
  table.insert(PRED.alerts, 1, {
    t    = tick(),
    rar  = e.rar,
    mut  = e.mut,
    name = e.obj and e.obj.Name or "?",
    pos  = e.pos,
    src  = source or "scan",
  })
  while #PRED.alerts > 8 do table.remove(PRED.alerts) end
end

-- probe: apakah server benar-benar mereplikasi "telur berikutnya"?
local function probeNextEgg()
  local hits = {}
  local KEY = { "next", "upcoming", "queue", "pool", "incoming", "schedule", "rolled" }
  local function nameLooksRight(n)
    n = lower(n)
    if not (n:find("egg") or n:find("rarity") or n:find("spawn") or n:find("reset")) then return false end
    for _, k in ipairs(KEY) do if n:find(k) then return true end end
    return false
  end
  local roots = { RS, Workspace }
  for _, root in ipairs(roots) do
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("ValueBase") and nameLooksRight(d.Name) then
        hits[#hits + 1] = d.Name .. " = " .. tostring(d.Value)
      end
    end
  end
  PRED.probe = {
    t     = tick(),
    found = #hits,
    list  = hits,
  }
  return PRED.probe
end

-- hook pengumuman server (kalau gamenya memang mengirim lewat RemoteEvent)
local annHooked = {}
local function hookAnnouncements()
  local n = 0
  for _, r in ipairs(remotes) do
    if r:IsA("RemoteEvent") and not annHooked[r] then
      local nm = lower(r.Name)
      if nm:find("announce") or nm:find("notif") or nm:find("broadcast")
        or nm:find("global") or nm:find("alert") or nm:find("message") then
        annHooked[r] = true
        n = n + 1
        pcall(function()
          r.OnClientEvent:Connect(function(...)
            local blob = ""
            for _, a in ipairs({ ... }) do
              if type(a) == "string" then blob = blob .. " " .. a
              elseif type(a) == "table" then
                for _, v in pairs(a) do
                  if type(v) == "string" then blob = blob .. " " .. v end
                end
              end
            end
            local lb = lower(blob)
            for i = #RARITY, 1, -1 do
              if lb:find(lower(RARITY[i]), 1, true) then
                PRED.announces = PRED.announces + 1
                PRED.lastAnn = { t = tick(), rar = RARITY[i], text = blob:sub(1, 90) }
                break
              end
            end
          end)
        end)
      end
    end
  end
  return n
end


-- ============ AMBIL TELUR: banyak cara, dicoba berurutan ============
-- Penyebab "steal ga ke-steal": v3 hanya menembak prompt + touch sekali lalu
-- langsung pergi. Sekarang: dekati sampai benar-benar dekat, tekan prompt di
-- dalam objek telur itu sendiri, sentuh SEMUA part-nya, tembak remote dengan
-- beberapa bentuk argumen, lalu VERIFIKASI apakah telur benar-benar terbawa.

local function promptsInside(obj, radius)
  local h = hrp(); if not h then return 0 end
  local n = 0
  for _, p in ipairs(obj:GetDescendants()) do
    if p:IsA("ProximityPrompt") then
      pcall(function()
        p.Enabled = true
        p.MaxActivationDistance = math.max(p.MaxActivationDistance or 0, 80)
        p.RequiresLineOfSight = false
        p.HoldDuration = 0
        fireproximityprompt(p)
      end)
      n = n + 1
    end
  end
  if obj:IsA("ProximityPrompt") then
    pcall(function() fireproximityprompt(obj) end)
    n = n + 1
  end
  return n
end

local function touchAllParts(obj)
  local h = hrp(); if not h then return 0 end
  local n = 0
  local parts = {}
  if obj:IsA("BasePart") then parts[1] = obj end
  for _, d in ipairs(obj:GetDescendants()) do
    if d:IsA("BasePart") then parts[#parts + 1] = d end
  end
  for _, p in ipairs(parts) do
    pcall(function()
      firetouchinterest(h, p, 0)
      firetouchinterest(h, p, 1)
      firetouchinterest(h, p, 0)
      firetouchinterest(h, p, 1)
      n = n + 1
    end)
  end
  return n
end

-- Apakah telur BENAR-BENAR terbawa? Kedekatan posisi BUKAN bukti — berdiri di
-- sebelah telur tidak berarti memegangnya, dan itulah yang membuat v3 mengaku
-- berhasil lalu pulang dengan tangan kosong. Bukti yang diterima hanya:
--   a) telur menjadi keturunan karakter kita, atau
--   b) telur di-weld ke HumanoidRootPart kita, atau
--   c) telur hilang dari dunia SAAT kita berdiri di sisinya (<16 stud)
-- `nearDist` = jarak kita ke telur pada percobaan terakhir.
local function heldByMe(obj, nearDist)
  local c = char(); if not c then return false end
  local h = hrp()

  if not obj.Parent then
    return (nearDist ~= nil) and (nearDist < 16)
  end

  local p = obj.Parent
  while p do
    if p == c then return true end
    p = p.Parent
  end

  if h then
    for _, d in ipairs(obj:GetDescendants()) do
      if d:IsA("WeldConstraint") or d:IsA("Weld") then
        local ok = false
        pcall(function()
          if d.Part0 == h or d.Part1 == h then ok = true end
        end)
        if ok then return true end
      end
    end
  end
  return false
end

-- satu percobaan ambil penuh.
-- Urutan penting: kalau cara ambil sudah DIPELAJARI dari rekaman nyata, itu
-- yang dipakai lebih dulu. Tebakan nama remote hanya cadangan terakhir, dan
-- hanya kalau S.blindFire menyala — menembak remote secara buta bisa memicu
-- anti-cheat dan itu yang gagal di v3/v4.
local function grabAttempt(e)
  local acts = 0

  -- 1. selalu: prompt di dalam telur + SmartPromptPart (pusat prompt game ini)
  --    + prompt lain yang dekat + sentuh semua part (cara pemain asli)
  acts = acts + promptsInside(e.obj, 26)
  acts = acts + fireSmartPrompts()
  acts = acts + pressPromptsNear(30)
  acts = acts + touchAllParts(e.obj)

  -- 2. resep hasil belajar
  if SPY and SPY.learned then
    if SPY.replay(e.obj) then acts = acts + 1 end
    return acts
  end

  -- 3. kalau yang dipelajari adalah "prompt saja" atau "sentuhan saja",
  --    jangan menembak remote apa pun
  if SPY and (SPY.learnedFrom == "prompt" or SPY.learnedFrom == "touch") then
    return acts
  end

  -- 4. cadangan tebakan (bisa dimatikan)
  if S.blindFire then
    local words = { "steal", "pickup", "pick", "grab", "take", "collect", "carry", "hold" }
    fireMatch(words, e.obj)
    fireMatch(words, e.obj.Name)
    fireMatch(words)
    acts = acts + 1
  end
  return acts
end

-- ============ LOOP: STEAL EGG ============
task.spawn(function()
  while true do
    task.wait(S.stealDelay)
    if S.stealOn and alive() then
      local ok, err = pcall(function()
        local e = pickEgg()
        if not e then
          -- jujur soal kenapa tidak ada target: peta kosong, filter, atau
          -- semua telur memang di base pemain lain (bukan sasaran default)
          local wild, total = 0, 0
          for _, x in ipairs(scanEggs()) do
            if not x.mine then
              total = total + 1
              if not x.owned then wild = wild + 1 end
            end
          end
          S.status = (total > 0 and wild == 0)
            and "semua telur di base pemain — nyalakan toggle 'Ambil dari base pemain' kalau mau"
            or "nunggu telur cocok"
          return
        end

        local tag = (e.rar or "?")
        if e.pet then tag = tag .. " " .. e.pet end
        if e.mut then tag = e.mut .. " " .. tag end

        -- 1. dekati sampai benar-benar dekat, bukan cuma "kira-kira sampai"
        S.status = "menuju " .. tag
        moveTo(e.pos, 25, S.stealSpeed)
        if not S.stealOn then S.status = "dibatalkan"; return end

        -- 2. koreksi jarak: benar-benar sampai di sisi telur, bukan "kira-kira".
        -- Jarak yang terlalu jauh adalah penyebab paling umum prompt/sentuhan
        -- tidak berefek sama sekali.
        for _ = 1, 3 do
          local h = hrp()
          if not (h and e.obj.Parent) then break end
          local now = posOf(e.obj) or e.pos
          local d = dist(h.Position, now)
          if d <= S.approachDist then break end
          moveTo(now, 10, S.stealSpeed)
        end

        -- 3. usaha ambil beberapa kali, berhenti begitu terbukti terbawa
        local got = false
        for i = 1, math.max(1, S.grabTries) do
          if not S.stealOn then S.status = "dibatalkan"; return end

          local hh = hrp()
          local ep = posOf(e.obj)
          local dNow = (hh and ep) and dist(hh.Position, ep) or nil

          -- kalau telur sudah hilang sebelum kita sempat menyentuh, itu bukan
          -- keberhasilan kita — kecuali kita memang sedang berdiri di sisinya
          if not e.obj.Parent then
            got = heldByMe(e.obj, dNow)
            break
          end

          grabAttempt(e)
          task.wait(0.35)

          local hh2 = hrp()
          local ep2 = posOf(e.obj)
          local d2 = (hh2 and ep2) and dist(hh2.Position, ep2) or dNow
          if heldByMe(e.obj, d2) then got = true break end

          local cur = posOf(e.obj)
          if cur then moveTo(cur, 4, S.stealSpeed) end
        end

        S.lastGrab = got and ("berhasil: " .. tag) or ("gagal ambil: " .. tag)
        if not got then
          S.fails = S.fails + 1
          S.status = "gagal ambil, cari yang lain"
          return                      -- JANGAN pulang kalau tangan kosong
        end

        -- 4. baru pulang setelah telur benar-benar terbawa
        if S.returnBase then
          local b = myBase()
          if b then
            S.status = "bawa pulang " .. tag
            moveTo(b, 35, S.stealSpeed)
            if not S.stealOn then S.status = "dibatalkan"; return end
            pressPromptsNear(30)
            fireMatch({ "deposit", "deliver", "place", "store", "submit", "drop" }, e.obj)
            fireMatch({ "deposit", "deliver", "place", "store", "submit", "drop" })
            task.wait(0.3)
          end
        end

        S.stolen = S.stolen + 1
        S.lastEgg = tag .. (e.income and (" · " .. (money(e.income * (e.mult or 1)) or "?")) or "")
        S.status = "selesai #" .. S.stolen
      end)
      if not ok then
        S.fails = S.fails + 1
        S.status = "error: " .. tostring(err):sub(1, 44)
      end
    end
  end
end)

-- ============ LOOP: FARM ============
task.spawn(function()
  while true do
    task.wait(2.2)
    if alive() then
      pcall(function()
        if S.autoHatch   then fireMatch({ "hatch", "openegg", "incubat" }) end
        if S.autoClaim   then fireMatch({ "claim", "collectmoney", "collectcash", "collectincome" }) end
        if S.autoTrain   then fireMatch({ "train", "treadmill", "speedtrain" }) end
        if S.autoSell    then fireMatch({ "sellpet", "sell" }) end
        if S.autoUpgrade then fireMatch({ "upgrade", "buyupgrade", "levelup" }) end
      end)
    end
  end
end)

task.spawn(function()
  while true do
    task.wait(6)
    if S.autoTrain and alive() and not S.stealOn then
      pcall(function()
        for _, v in ipairs(Workspace:GetDescendants()) do
          if (v:IsA("BasePart") or v:IsA("Model")) and lower(v.Name):find("treadmill") then
            local p = posOf(v)
            if p and hrp() and dist(hrp().Position, p) > 12 then moveTo(p, 20) end
            pressPromptsNear(24)
            break
          end
        end
      end)
    end
  end
end)

-- ============ PLAYER: speed, anti stun, no fall ============
task.spawn(function()
  while true do
    task.wait(0.25)
    pcall(function()
      local h = hum()
      if not h then return end

      -- jangan ganggu WalkSpeed saat gerak sedang mengatur kecepatan
      if not moving then
        if S.speedOn then
          h.WalkSpeed = math.clamp(S.speed, 8, 1000)
        elseif h.WalkSpeed > 40 then
          h.WalkSpeed = 16
        end
      end

      -- PlatformStand tidak boleh pernah nyangkut true
      if h.PlatformStand and not moving then h.PlatformStand = false end

      if S.antiStun then
        h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        h:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        h.Sit = false
      end
      if S.noFall then
        local hp = hrp()
        if hp and hp.Velocity.Y < -120 then
          hp.Velocity = Vector3.new(hp.Velocity.X, -20, hp.Velocity.Z)
        end
      end
    end)
  end
end)

-- ============ ESP ============
local espF = Instance.new("Folder")
espF.Name = "SAE_ESP"
espF.Parent = CoreGui

local function tagBox(inst, color, lines)
  local hl = Instance.new("Highlight")
  hl.Adornee = inst
  hl.FillColor = color
  hl.OutlineColor = color
  hl.FillTransparency = 0.62
  hl.OutlineTransparency = 0
  hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
  hl.Parent = espF

  if lines and #lines > 0 then
    local p = partOf(inst)
    if p then
      local bb = Instance.new("BillboardGui")
      bb.Adornee = p
      bb.Size = UDim2.new(0, 200, 0, 16 * #lines + 6)
      bb.StudsOffset = Vector3.new(0, 2.8, 0)
      bb.AlwaysOnTop = true
      bb.Parent = espF
      local ll = Instance.new("UIListLayout")
      ll.Parent = bb
      for i, ln in ipairs(lines) do
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, 0, 0, 16)
        tl.BackgroundTransparency = 1
        tl.Text = ln
        tl.Font = (i == 1) and Enum.Font.GothamBold or Enum.Font.Code
        tl.TextSize = (i == 1) and 13 or 11
        tl.TextColor3 = (i == 1) and color or Color3.fromRGB(225, 232, 242)
        tl.TextStrokeTransparency = 0.25
        tl.Parent = bb
      end
    end
  end
end

task.spawn(function()
  while true do
    task.wait(2)
    pcall(function()
      espF:ClearAllChildren()
      local h = hrp(); if not h then return end

      if S.espEgg then
        for _, e in ipairs(scanEggs()) do
          local d = dist(h.Position, e.pos)
          if d <= S.espRange then
            local idx = 0
            if e.rar then
              for i, r in ipairs(RARITY) do if r == e.rar then idx = i break end end
            end
            local show
            if idx == 0 then show = S.espUnknown else show = (idx >= S.espMinRarity) end
            if show then
              local col = (e.rar and RCOLOR[e.rar]) or Color3.fromRGB(190, 195, 205)

              -- baris 1: mutasi + rarity + nama pet
              local head
              if e.pet then
                head = (e.rar or "?") .. " · " .. e.pet
              elseif e.rar then
                head = e.rar
              else
                -- nama slot game ini adalah UUID — tampilkan label yang bisa
                -- dibaca, bukan deretan huruf acak
                local nm = tostring(e.obj.Name)
                if #nm == 32 and nm:match("^%x+$") then nm = "Telur zona" end
                head = nm:gsub("_", " ")
              end
              if e.mut then head = e.mut .. " " .. head end

              -- baris 2: income
              local l2
              if e.income then
                local base = money(e.income)
                if e.mut and (e.mult or 1) > 1 then
                  l2 = (money(e.income * e.mult) or "?") .. "  (" .. base .. " ×" .. e.mult .. ")"
                else
                  l2 = base
                end
              elseif e.rar then
                l2 = e.rar .. " · income tak dipublikasikan"
              else
                l2 = "pet belum ada di database"
              end

              -- baris 3: biome, berat, jarak
              local bits = {}
              if e.rare then bits[#bits + 1] = "RARE" end
              if e.kind == "parasite" then bits[#bits + 1] = "PARASIT" end
              if e.owned and not e.mine then bits[#bits + 1] = "MILIK PEMAIN" end
              if e.biome then bits[#bits + 1] = e.biome end
              local w = kg(e.wt)
              if w then bits[#bits + 1] = w end
              bits[#bits + 1] = math.floor(d) .. "m"
              if e.mine then bits[#bits + 1] = "MILIKKU" end

              tagBox(e.obj, col, { head, l2, table.concat(bits, " · ") })
            end
          end
        end
      end

      if S.espTrap then
        for _, t in ipairs(scanTraps()) do
          local d = dist(h.Position, t.pos)
          if d < 900 then tagBox(t.obj, Color3.fromRGB(255, 90, 90), { "TRAP", math.floor(d) .. "m" }) end
        end
      end
      if S.espGuard then
        for _, m in ipairs(scanHostiles()) do
          local d = dist(h.Position, m.pos)
          if d < 1200 then
            tagBox(m.obj, Color3.fromRGB(255, 160, 60), { string.upper(m.kind), math.floor(d) .. "m" })
          end
        end
      end
      if S.espPlayer then
        for _, pl in ipairs(Players:GetPlayers()) do
          if pl ~= LP and pl.Character then
            local pp = pl.Character:FindFirstChild("HumanoidRootPart")
            if pp then
              tagBox(pl.Character, Color3.fromRGB(90, 200, 255),
                { pl.Name, math.floor(dist(h.Position, pp.Position)) .. "m" })
            end
          end
        end
      end
    end)
  end
end)


-- ============ PEMANTAU BELAJAR OTOMATIS ============
-- Menyalakan rekaman lalu menunggu pengguna mengambil satu telur dengan tangan
-- sendiri. Begitu ada telur yang benar-benar berpindah ke karakter (atau hilang
-- saat pengguna berdiri di sisinya), rekaman terakhir dipakai sebagai resep.

local LEARN = {
  active   = false,
  started  = nil,
  watching = {},          -- obj -> {pos, t}
  done     = false,
}

local function snapshotNearby()
  local h = hrp(); if not h then return end
  LEARN.watching = {}
  for _, e in ipairs(scanEggs()) do
    if not e.mine and dist(h.Position, e.pos) < 120 then
      LEARN.watching[e.obj] = { pos = e.pos, t = tick() }
    end
  end
end

function startLearning()
  local ok = SPY.install()
  SPY.recording = true
  SPY.log = {}
  SPY.prompts = {}
  SPY.fires = 0
  LEARN.active = true
  LEARN.done = false
  LEARN.started = tick()
  snapshotNearby()
  S.status = ok and "MODE BELAJAR: ambil 1 telur manual"
    or "hook gagal — masih bisa belajar dari prompt/sentuhan"
  return ok
end

function stopLearning()
  LEARN.active = false
  SPY.recording = false
  S.status = "mode belajar berhenti"
end

-- pantau: apakah salah satu telur yang diawasi kini terbawa pengguna?
task.spawn(function()
  while true do
    task.wait(0.35)
    if LEARN.active and alive() then
      pcall(function()
        local h = hrp(); if not h then return end
        local c = char()

        for obj, info in pairs(LEARN.watching) do
          local taken = false

          if not obj.Parent then
            -- hilang: hanya dihitung kalau pengguna sedang di sisinya
            if dist(h.Position, info.pos) < 18 then taken = true end
          else
            local p = obj.Parent
            while p do
              if p == c then taken = true break end
              p = p.Parent
            end
            -- atau telur ikut bergerak bersama pemain (dibawa)
            if not taken then
              local np = posOf(obj)
              if np and (np - info.pos).Magnitude > 12 and dist(h.Position, np) < 14 then
                taken = true
              end
            end
          end

          if taken then
            SPY.learnFrom(obj, LEARN.started)
            -- v6: resep langsung ditulis ke berkas — AJARI cukup sekali,
            -- sesi berikutnya memuatnya otomatis
            pcall(function()
              if SPY.saveRecipe() then
                SPY.note = SPY.note .. " · tersimpan di berkas"
              end
            end)
            SPY.lastPickup = tostring(obj.Name)
            LEARN.active = false
            LEARN.done = true
            SPY.recording = false
            S.status = "TERPELAJARI: " .. SPY.note:sub(1, 46)
            return
          end
        end

        -- perbarui daftar awasan tiap 3 detik supaya telur baru ikut terpantau
        if tick() - (LEARN.lastSnap or 0) > 3 then
          LEARN.lastSnap = tick()
          local h2 = hrp()
          if h2 then
            for _, e in ipairs(scanEggs()) do
              if not e.mine and not LEARN.watching[e.obj]
                and dist(h2.Position, e.pos) < 120 then
                LEARN.watching[e.obj] = { pos = e.pos, t = tick() }
              end
            end
          end
        end
      end)
    end
  end
end)


-- ============ LOOP PENGAMAT SIKLUS ============
-- Belajar periode reset dari perubahan nyata isi map, bukan dari angka hafalan.
task.spawn(function()
  -- ambil sidik jari awal supaya reset pertama tidak dihitung palsu
  local ok0 = pcall(function() PRED.sig = (eggSignature()) end)
  if not ok0 then PRED.sig = nil end

  while true do
    task.wait(1)
    if PRED.watch then
      pcall(function()
        PRED.liveTimer = findLiveTimer()

        local sig, eggs = eggSignature()

        -- reset terdeteksi kalau isi map berubah drastis (mirip < 35%)
        if PRED.sig and sig ~= PRED.sig then
          local sim = similarity(PRED.sig, sig)
          if sim < 0.35 and #eggs > 0 then
            local now = tick()
            -- tolak deteksi ganda dalam 20 detik (gemerlap render, bukan reset)
            if not PRED.lastReset or (now - PRED.lastReset) > 20 then
              PRED.lastReset = now
              table.insert(PRED.resetTimes, now)
              while #PRED.resetTimes > 40 do table.remove(PRED.resetTimes, 1) end
              PRED.period = computePeriod()
              PRED.observed = PRED.observed + 1

              -- catat rarity apa saja yang muncul di reset ini
              local seen = {}
              for _, e in ipairs(eggs) do
                if e.rar and not seen[e.rar] then
                  seen[e.rar] = true
                  PRED.counts[e.rar] = (PRED.counts[e.rar] or 0) + 1
                  PRED.seenNames[e.rar] = e.obj.Name
                end
              end

              -- alarm untuk rarity yang dipantau
              for _, e in ipairs(eggs) do
                if e.rar and PRED.notify[e.rar] then
                  pushAlert(e, "reset")
                end
              end
            end
          end
        end
        PRED.sig = sig

        -- deteksi instan: telur langka muncul di luar siklus reset
        for _, e in ipairs(eggs) do
          if e.rar and PRED.notify[e.rar] then
            local fresh = true
            for _, a in ipairs(PRED.alerts) do
              if a.name == e.obj.Name and (tick() - a.t) < 60 then fresh = false break end
            end
            if fresh then pushAlert(e, "muncul") end
          end
        end
      end)
    end
  end
end)

-- auto kejar telur langka begitu terdeteksi
task.spawn(function()
  while true do
    task.wait(1.5)
    if PRED.watch and PRED.autoGo and alive() and not S.stealOn then
      pcall(function()
        local target = nil
        for _, e in ipairs(scanEggs()) do
          if e.rar and PRED.notify[e.rar] then
            if not target or eggScore(e) > eggScore(target) then target = e end
          end
        end
        if target then
          S.status = "kejar " .. target.rar .. (target.mut and (" " .. target.mut) or "")
          glideTo(target.pos, 25)
          pressPromptsNear(26)
          local p = partOf(target.obj)
          if p then touchPart(p) end
          fireMatch({ "steal", "pickup", "grabegg", "takeegg", "collectegg" }, target.obj)
          task.wait(0.5)
          local b = myBase()
          if b and S.returnBase then
            glideTo(b, 30)
            pressPromptsNear(26)
            fireMatch({ "deposit", "deliver", "placeegg", "storeegg", "submit" }, target.obj)
          end
        end
      end)
    end
  end
end)


-- ============ UI: tema & helper ============
local T = {
  bg      = Color3.fromRGB(13, 15, 21),
  panel   = Color3.fromRGB(19, 22, 30),
  panel2  = Color3.fromRGB(25, 29, 39),
  line    = Color3.fromRGB(38, 44, 58),
  txt     = Color3.fromRGB(232, 238, 247),
  txt2    = Color3.fromRGB(146, 160, 182),
  gold    = Color3.fromRGB(232, 163, 61),
  jade    = Color3.fromRGB(62, 207, 154),
  red     = Color3.fromRGB(217, 117, 95),
}

local function corner(o, r)
  local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 10); c.Parent = o; return c
end
local function stroke(o, col, th)
  local s = Instance.new("UIStroke")
  s.Color = col or T.line; s.Thickness = th or 1
  s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = o; return s
end
local function pad(o, v)
  local p = Instance.new("UIPadding")
  p.PaddingTop = UDim.new(0, v); p.PaddingBottom = UDim.new(0, v)
  p.PaddingLeft = UDim.new(0, v); p.PaddingRight = UDim.new(0, v)
  p.Parent = o; return p
end
local function label(parent, text, size, color, bold)
  local l = Instance.new("TextLabel")
  l.BackgroundTransparency = 1
  l.Size = UDim2.new(1, 0, 0, size + 8)
  l.Text = text
  l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
  l.TextSize = size
  l.TextColor3 = color or T.txt
  l.TextXAlignment = Enum.TextXAlignment.Left
  l.Parent = parent
  return l
end

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_Hub_v2"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

-- tombol bulat pembuka (kalau hub disembunyikan)
local orb = Instance.new("TextButton")
orb.Size = UDim2.new(0, 52, 0, 52)
orb.Position = UDim2.new(0, 14, 0.42, 0)
orb.BackgroundColor3 = T.gold
orb.Text = "EGG"
orb.Font = Enum.Font.GothamBlack
orb.TextSize = 13
orb.TextColor3 = Color3.fromRGB(20, 14, 4)
orb.Visible = false
orb.Active = true
orb.Draggable = true
orb.Parent = gui
corner(orb, 26)

-- jendela utama
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 330, 0, 412)
win.Position = UDim2.new(0, 18, 0.5, -206)
win.BackgroundColor3 = T.bg
win.BorderSizePixel = 0
win.Active = true
win.Draggable = true
win.Parent = gui
corner(win, 14)
stroke(win, T.line, 1)

-- header
local head = Instance.new("Frame")
head.Size = UDim2.new(1, 0, 0, 46)
head.BackgroundTransparency = 1
head.Parent = win

local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 8, 0, 8)
dot.Position = UDim2.new(0, 16, 0, 19)
dot.BackgroundColor3 = T.jade
dot.BorderSizePixel = 0
dot.Parent = head
corner(dot, 4)

local ttl = Instance.new("TextLabel")
ttl.Size = UDim2.new(1, -110, 1, 0)
ttl.Position = UDim2.new(0, 32, 0, 0)
ttl.BackgroundTransparency = 1
ttl.Text = "STEAL AN EGG"
ttl.Font = Enum.Font.GothamBlack
ttl.TextSize = 14
ttl.TextColor3 = T.txt
ttl.TextXAlignment = Enum.TextXAlignment.Left
ttl.Parent = head

local ver = Instance.new("TextLabel")
ver.Size = UDim2.new(0, 40, 1, 0)
ver.Position = UDim2.new(1, -86, 0, 0)
ver.BackgroundTransparency = 1
ver.Text = "v2"
ver.Font = Enum.Font.Code
ver.TextSize = 11
ver.TextColor3 = T.txt2
ver.Parent = head

local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.new(0, 34, 0, 34)
hideBtn.Position = UDim2.new(1, -44, 0, 6)
hideBtn.BackgroundColor3 = T.panel2
hideBtn.Text = "—"
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextSize = 16
hideBtn.TextColor3 = T.txt2
hideBtn.Parent = head
corner(hideBtn, 9)

-- tab bar
local tabbar = Instance.new("Frame")
tabbar.Size = UDim2.new(1, -24, 0, 38)
tabbar.Position = UDim2.new(0, 12, 0, 44)
tabbar.BackgroundColor3 = T.panel
tabbar.BorderSizePixel = 0
tabbar.Parent = win
corner(tabbar, 10)

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Parent = tabbar
pad(tabbar, 4)

-- area konten
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -24, 1, -132)
content.Position = UDim2.new(0, 12, 0, 90)
content.BackgroundTransparency = 1
content.Parent = win

-- status bar bawah
local statusBar = Instance.new("Frame")
statusBar.Size = UDim2.new(1, -24, 0, 34)
statusBar.Position = UDim2.new(0, 12, 1, -40)
statusBar.BackgroundColor3 = T.panel
statusBar.BorderSizePixel = 0
statusBar.Parent = win
corner(statusBar, 9)

local statusTxt = Instance.new("TextLabel")
statusTxt.Size = UDim2.new(1, -16, 1, 0)
statusTxt.Position = UDim2.new(0, 10, 0, 0)
statusTxt.BackgroundTransparency = 1
statusTxt.Text = "siap"
statusTxt.Font = Enum.Font.Code
statusTxt.TextSize = 11
statusTxt.TextColor3 = T.txt2
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.TextTruncate = Enum.TextTruncate.AtEnd
statusTxt.Parent = statusBar

hideBtn.MouseButton1Click:Connect(function()
  win.Visible = false; orb.Visible = true
end)
orb.MouseButton1Click:Connect(function()
  win.Visible = true; orb.Visible = false
end)


-- ============ UI: komponen ============
local pages, tabs = {}, {}
local activePage = nil

local function makePage(name)
  local sc = Instance.new("ScrollingFrame")
  sc.Size = UDim2.new(1, 0, 1, 0)
  sc.BackgroundTransparency = 1
  sc.BorderSizePixel = 0
  sc.ScrollBarThickness = 3
  sc.ScrollBarImageColor3 = T.line
  sc.CanvasSize = UDim2.new(0, 0, 0, 0)
  sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
  sc.Visible = false
  sc.Parent = content

  local ll = Instance.new("UIListLayout")
  ll.Padding = UDim.new(0, 7)
  ll.SortOrder = Enum.SortOrder.LayoutOrder
  ll.Parent = sc

  local pd = Instance.new("UIPadding")
  pd.PaddingRight = UDim.new(0, 8); pd.PaddingBottom = UDim.new(0, 10)
  pd.Parent = sc

  pages[name] = sc
  return sc
end

local function showPage(name)
  for n, p in pairs(pages) do p.Visible = (n == name) end
  for n, b in pairs(tabs) do
    local on = (n == name)
    b.BackgroundColor3 = on and T.panel2 or T.panel
    b.TextColor3 = on and T.gold or T.txt2
  end
  activePage = name
end

local function makeTab(name, w)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, w, 1, 0)
  b.BackgroundColor3 = T.panel
  b.Text = name
  b.Font = Enum.Font.GothamBold
  b.TextSize = 12
  b.TextColor3 = T.txt2
  b.AutoButtonColor = false
  b.Parent = tabbar
  corner(b, 8)
  tabs[name] = b
  b.MouseButton1Click:Connect(function() showPage(name) end)
  return b
end

-- baris toggle
local function toggle(page, text, sub, get, set)
  local row = Instance.new("Frame")
  row.Size = UDim2.new(1, 0, 0, sub and 50 or 42)
  row.BackgroundColor3 = T.panel
  row.BorderSizePixel = 0
  row.Parent = page
  corner(row, 9)

  local t = Instance.new("TextLabel")
  t.Size = UDim2.new(1, -70, 0, sub and 20 or 42)
  t.Position = UDim2.new(0, 12, 0, sub and 7 or 0)
  t.BackgroundTransparency = 1
  t.Text = text
  t.Font = Enum.Font.GothamMedium
  t.TextSize = 13
  t.TextColor3 = T.txt
  t.TextXAlignment = Enum.TextXAlignment.Left
  t.Parent = row

  if sub then
    local s = Instance.new("TextLabel")
    s.Size = UDim2.new(1, -70, 0, 16)
    s.Position = UDim2.new(0, 12, 0, 26)
    s.BackgroundTransparency = 1
    s.Text = sub
    s.Font = Enum.Font.Gotham
    s.TextSize = 10
    s.TextColor3 = T.txt2
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.Parent = row
  end

  local sw = Instance.new("TextButton")
  sw.Size = UDim2.new(0, 44, 0, 24)
  sw.Position = UDim2.new(1, -56, 0.5, -12)
  sw.BackgroundColor3 = T.panel2
  sw.Text = ""
  sw.AutoButtonColor = false
  sw.Parent = row
  corner(sw, 12)

  local knob = Instance.new("Frame")
  knob.Size = UDim2.new(0, 18, 0, 18)
  knob.Position = UDim2.new(0, 3, 0.5, -9)
  knob.BackgroundColor3 = T.txt2
  knob.BorderSizePixel = 0
  knob.Parent = sw
  corner(knob, 9)

  local function paint()
    local on = get()
    TweenService:Create(sw, TweenInfo.new(0.16), {
      BackgroundColor3 = on and T.jade or T.panel2 }):Play()
    TweenService:Create(knob, TweenInfo.new(0.16), {
      Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
      BackgroundColor3 = on and Color3.fromRGB(6, 24, 16) or T.txt2 }):Play()
  end
  sw.MouseButton1Click:Connect(function() set(not get()); paint() end)
  paint()
  return row
end

-- slider
local function slider(page, text, min, max, get, set, fmt)
  local row = Instance.new("Frame")
  row.Size = UDim2.new(1, 0, 0, 58)
  row.BackgroundColor3 = T.panel
  row.BorderSizePixel = 0
  row.Parent = page
  corner(row, 9)

  local t = Instance.new("TextLabel")
  t.Size = UDim2.new(1, -24, 0, 20)
  t.Position = UDim2.new(0, 12, 0, 8)
  t.BackgroundTransparency = 1
  t.Text = text
  t.Font = Enum.Font.GothamMedium
  t.TextSize = 12
  t.TextColor3 = T.txt
  t.TextXAlignment = Enum.TextXAlignment.Left
  t.Parent = row

  local val = Instance.new("TextLabel")
  val.Size = UDim2.new(0, 90, 0, 20)
  val.Position = UDim2.new(1, -102, 0, 8)
  val.BackgroundTransparency = 1
  val.Text = ""
  val.Font = Enum.Font.Code
  val.TextSize = 12
  val.TextColor3 = T.gold
  val.TextXAlignment = Enum.TextXAlignment.Right
  val.Parent = row

  local track = Instance.new("Frame")
  track.Size = UDim2.new(1, -24, 0, 8)
  track.Position = UDim2.new(0, 12, 0, 38)
  track.BackgroundColor3 = T.panel2
  track.BorderSizePixel = 0
  track.Parent = row
  corner(track, 4)

  local fill = Instance.new("Frame")
  fill.Size = UDim2.new(0, 0, 1, 0)
  fill.BackgroundColor3 = T.gold
  fill.BorderSizePixel = 0
  fill.Parent = track
  corner(fill, 4)

  local grab = Instance.new("TextButton")
  grab.Size = UDim2.new(1, 0, 0, 30)
  grab.Position = UDim2.new(0, 0, 0, -11)
  grab.BackgroundTransparency = 1
  grab.Text = ""
  grab.Parent = track

  local function paint()
    local v = get()
    local a = (v - min) / (max - min)
    fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
    val.Text = fmt and fmt(v) or tostring(math.floor(v))
  end

  local dragging = false
  local function setFromX(x)
    local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
    set(math.floor(min + a * (max - min)))
    paint()
  end
  grab.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
      dragging = true; setFromX(i.Position.X)
    end
  end)
  grab.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
      dragging = false
    end
  end)
  game:GetService("UserInputService").InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
      setFromX(i.Position.X)
    end
  end)
  paint()
  return row
end

-- judul seksi
local function section(page, text)
  local l = Instance.new("TextLabel")
  l.Size = UDim2.new(1, 0, 0, 24)
  l.BackgroundTransparency = 1
  l.Text = string.upper(text)
  l.Font = Enum.Font.GothamBold
  l.TextSize = 10
  l.TextColor3 = T.txt2
  l.TextXAlignment = Enum.TextXAlignment.Left
  l.Parent = page
  return l
end

-- tombol aksi
local function action(page, text, fn, tone)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(1, 0, 0, 40)
  b.BackgroundColor3 = tone == "gold" and T.gold or T.panel2
  b.Text = text
  b.Font = Enum.Font.GothamBold
  b.TextSize = 12
  b.TextColor3 = tone == "gold" and Color3.fromRGB(20, 14, 4) or T.txt
  b.AutoButtonColor = false
  b.Parent = page
  corner(b, 9)
  b.MouseButton1Click:Connect(function() pcall(fn) end)
  return b
end


-- ============ TAB: STEAL / FARM / PLAYER / ESP ============
makeTab("STEAL", 70)
makeTab("FARM", 62)
makeTab("PLAYER", 74)
makeTab("ESP", 56)

local pSteal  = makePage("STEAL")
local pFarm   = makePage("FARM")
local pPlayer = makePage("PLAYER")
local pEsp    = makePage("ESP")

-- --- STEAL ---
toggle(pSteal, "Auto Steal Egg", "terbang datar, ambil, baru pulang",
  function() return S.stealOn end,
  function(v) S.stealOn = v; if not v then stopGlide() end end)

toggle(pSteal, "Bawa pulang ke base", "matikan kalau mau kumpul dulu",
  function() return S.returnBase end, function(v) S.returnBase = v end)

toggle(pSteal, "Ambil telur tak dikenal", "telur di luar database tetap diambil",
  function() return S.takeUnknown end, function(v) S.takeUnknown = v end)

toggle(pSteal, "Ambil telur dari base pemain lain", "default MATI: hanya telur liar di zona. nyala = boleh garong base orang",
  function() return S.takePlots end, function(v) S.takePlots = v end)

toggle(pSteal, "Prioritas telur mutasi", "Spirit Bloom 3x > Rainbow 2.5x > Golden 2x",
  function() return S.preferMutasi end, function(v) S.preferMutasi = v end)

section(pSteal, "cara ambil (penting)")
-- Kalau auto steal tidak pernah berhasil, ini yang harus dipakai: script
-- merekam cara ambil yang BENAR dari tanganmu sendiri, lalu memutarnya ulang.
local learnBox = Instance.new("Frame")
learnBox.Size = UDim2.new(1, 0, 0, 132)
learnBox.BackgroundColor3 = T.panel
learnBox.BorderSizePixel = 0
learnBox.Parent = pSteal
corner(learnBox, 9)

local learnScroll = Instance.new("ScrollingFrame")
learnScroll.Size = UDim2.new(1, -14, 1, -12)
learnScroll.Position = UDim2.new(0, 8, 0, 6)
learnScroll.BackgroundTransparency = 1
learnScroll.BorderSizePixel = 0
learnScroll.ScrollBarThickness = 3
learnScroll.ScrollBarImageColor3 = T.line
learnScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
learnScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
learnScroll.Parent = learnBox

local learnTxt = Instance.new("TextLabel")
learnTxt.Size = UDim2.new(1, 0, 0, 0)
learnTxt.AutomaticSize = Enum.AutomaticSize.Y
learnTxt.BackgroundTransparency = 1
learnTxt.Text = SPY.onDisk
  and ("resep tersimpan di berkas executor — dimuat otomatis.\ntekan 'Lihat cara ambil terpelajari' untuk melihatnya.")
  or  ("belum ada resep tersimpan.\ntekan tombol di bawah, lalu ambil SATU telur pakai tanganmu sendiri.\n(sekali saja — hasilnya tersimpan permanen)")
learnTxt.Font = Enum.Font.Code
learnTxt.TextSize = 10
learnTxt.TextColor3 = T.txt2
learnTxt.TextXAlignment = Enum.TextXAlignment.Left
learnTxt.TextYAlignment = Enum.TextYAlignment.Top
learnTxt.TextWrapped = true
learnTxt.Parent = learnScroll

action(pSteal, "AJARI: ambil 1 telur manual", function()
  S.stealOn = false
  stopGlide()
  local ok = startLearning()
  learnTxt.Text = (ok
    and "MEREKAM. Sekarang ambil SATU telur seperti biasa (jalan ke telur,\ntekan tombol ambil di game).\n\nBegitu telur terbawa, cara ambilnya langsung dipelajari."
    or  "Executor tidak mendukung hook remote.\nMasih bisa belajar dari prompt/sentuhan: ambil satu telur manual sekarang.")
end, "gold")

action(pSteal, "Berhenti merekam", function()
  stopLearning()
  learnTxt.Text = SPY.summary()
end)

action(pSteal, "Lihat cara ambil terpelajari", function()
  learnTxt.Text = SPY.summary()
  pcall(function() setclipboard(SPY.summary()) end)
end)

toggle(pSteal, "Tembak remote tebakan", "HANYA kalau belum pernah diajari",
  function() return S.blindFire end, function(v) S.blindFire = v end)

slider(pSteal, "Jarak mendekat sebelum ambil", 3, 20,
  function() return S.approachDist end, function(v) S.approachDist = v end,
  function(v) return v .. " stud" end)

section(pSteal, "kecepatan steal")
slider(pSteal, "Kecepatan saat steal", 16, 1000,
  function() return S.stealSpeed end, function(v) S.stealSpeed = v end,
  function(v) return v .. " stud" end)
slider(pSteal, "Jeda antar steal", 0, 30,
  function() return math.floor(S.stealDelay * 10) end,
  function(v) S.stealDelay = v / 10 end,
  function(v) return string.format("%.1f s", v / 10) end)
slider(pSteal, "Jarak maksimum telur", 100, 5000,
  function() return S.maxRange end, function(v) S.maxRange = v end,
  function(v) return v .. " stud" end)
slider(pSteal, "Usaha ambil per telur", 1, 8,
  function() return S.grabTries end, function(v) S.grabTries = v end,
  function(v) return v .. "x" end)
slider(pSteal, "Radius abaikan base", 0, 200,
  function() return S.baseGuard end, function(v) S.baseGuard = v end,
  function(v) return v <= 0 and "mati" or (v .. " stud") end)

section(pSteal, "pilih rarity")

local rgrid = Instance.new("Frame")
rgrid.Size = UDim2.new(1, 0, 0, 0)
rgrid.AutomaticSize = Enum.AutomaticSize.Y
rgrid.BackgroundTransparency = 1
rgrid.Parent = pSteal

local gl = Instance.new("UIGridLayout")
gl.CellSize = UDim2.new(0.5, -4, 0, 36)
gl.CellPadding = UDim2.new(0, 7, 0, 7)
gl.Parent = rgrid

local rarityBtns = {}
for _, r in ipairs(RARITY) do
  local b = Instance.new("TextButton")
  b.BackgroundColor3 = T.panel
  b.Text = r
  b.Font = Enum.Font.GothamBold
  b.TextSize = 11
  b.AutoButtonColor = false
  b.Parent = rgrid
  corner(b, 8)
  local st = stroke(b, T.line, 1)

  local function paint()
    local on = S.rarityPick[r]
    b.BackgroundColor3 = on and T.panel2 or T.panel
    b.TextColor3 = on and RCOLOR[r] or T.txt2
    st.Color = on and RCOLOR[r] or T.line
    st.Thickness = on and 1.6 or 1
  end
  b.MouseButton1Click:Connect(function()
    S.rarityPick[r] = not S.rarityPick[r]; paint()
  end)
  paint()
  rarityBtns[r] = paint
end

local rowQuick = Instance.new("Frame")
rowQuick.Size = UDim2.new(1, 0, 0, 34)
rowQuick.BackgroundTransparency = 1
rowQuick.Parent = pSteal
local qll = Instance.new("UIListLayout")
qll.FillDirection = Enum.FillDirection.Horizontal
qll.Padding = UDim.new(0, 6)
qll.Parent = rowQuick

local function quick(text, fn)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0.25, -5, 1, 0)
  b.BackgroundColor3 = T.panel2
  b.Text = text
  b.Font = Enum.Font.GothamBold
  b.TextSize = 10
  b.TextColor3 = T.txt
  b.AutoButtonColor = false
  b.Parent = rowQuick
  corner(b, 8)
  b.MouseButton1Click:Connect(function()
    fn()
    for _, paint in pairs(rarityBtns) do paint() end
  end)
end
quick("Semua", function() for _, r in ipairs(RARITY) do S.rarityPick[r] = true end end)
quick("Kosong", function() for _, r in ipairs(RARITY) do S.rarityPick[r] = false end end)
quick("Top 3", function()
  for _, r in ipairs(RARITY) do S.rarityPick[r] = false end
  S.rarityPick.Secret = true; S.rarityPick.Eternal = true; S.rarityPick.Divine = true
end)
quick("Cosmic+", function()
  for _, r in ipairs(RARITY) do S.rarityPick[r] = false end
  S.rarityPick.Cosmic = true; S.rarityPick.Secret = true
  S.rarityPick.Eternal = true; S.rarityPick.Divine = true
end)

section(pSteal, "filter nilai")
slider(pSteal, "Income minimum", 0, 100,
  function()
    -- slider 0..100 dipetakan ke skala log $0 .. $1B
    if S.minIncome <= 0 then return 0 end
    return math.floor(math.log(S.minIncome) / math.log(10) * 100 / 9)
  end,
  function(v)
    if v <= 0 then S.minIncome = 0
    else S.minIncome = math.floor(10 ^ (v * 9 / 100)) end
  end,
  function(v)
    if v <= 0 then return "abaikan" end
    return money(math.floor(10 ^ (v * 9 / 100)))
  end)
slider(pSteal, "Berat minimum", 0, 5000000,
  function() return S.minWeight end, function(v) S.minWeight = v end,
  function(v) return v <= 0 and "abaikan" or (kg(v) or tostring(v)) end)

-- --- FARM ---
section(pFarm, "otomatis")
toggle(pFarm, "Auto Hatch", "tetaskan telur begitu siap",
  function() return S.autoHatch end, function(v) S.autoHatch = v end)
toggle(pFarm, "Auto Claim uang", "ambil income pet",
  function() return S.autoClaim end, function(v) S.autoClaim = v end)
toggle(pFarm, "Auto Treadmill", "latih Speed saat idle",
  function() return S.autoTrain end, function(v) S.autoTrain = v end)
toggle(pFarm, "Auto Upgrade", "beli upgrade base bila mampu",
  function() return S.autoUpgrade end, function(v) S.autoUpgrade = v end)
toggle(pFarm, "Auto Sell pet", "jual pet duplikat",
  function() return S.autoSell end, function(v) S.autoSell = v end)

section(pFarm, "manual")
action(pFarm, "Hatch sekarang", function() fireMatch({ "hatch", "openegg", "incubat" }) end)
action(pFarm, "Claim semua uang", function() fireMatch({ "claim", "collectcash", "collectincome" }) end)
action(pFarm, "Tekan prompt terdekat", function() pressPromptsNear(30) end)

-- --- PLAYER ---
section(pPlayer, "gerak")
toggle(pPlayer, "Mode jalan kaki", "matikan = terbang datar (lebih cepat)",
  function() return S.walkMode end,
  function(v) S.walkMode = v; stopGlide() end)
toggle(pPlayer, "Speed custom", "kecepatan gerak umum",
  function() return S.speedOn end, function(v) S.speedOn = v end)
slider(pPlayer, "Kecepatan", 16, 1000,
  function() return S.speed end, function(v) S.speed = v end,
  function(v) return v .. " stud" end)

section(pPlayer, "keamanan")
toggle(pPlayer, "Anti Trap", "geser jalur menjauh dari trap",
  function() return S.antiTrap end, function(v) S.antiTrap = v end)
toggle(pPlayer, "Anti Bat / Guard", "geser jalur menjauh dari musuh",
  function() return S.antiBat end, function(v) S.antiBat = v end)
toggle(pPlayer, "Anti Stun / Ragdoll", "tolak state jatuh & duduk",
  function() return S.antiStun end, function(v) S.antiStun = v end)
toggle(pPlayer, "No Fall Damage", "redam kecepatan jatuh",
  function() return S.noFall end, function(v) S.noFall = v end)
slider(pPlayer, "Radius hindar", 10, 80,
  function() return S.avoidRadius end, function(v) S.avoidRadius = v end,
  function(v) return v .. " stud" end)

section(pPlayer, "darurat")
action(pPlayer, "STOP semua", function()
  S.stealOn = false; S.autoHatch = false; S.autoClaim = false
  S.autoTrain = false; S.autoSell = false; S.autoUpgrade = false
  stopGlide()
  local h = hum(); if h then h.WalkSpeed = 16; h.PlatformStand = false end
  S.status = "semua dimatikan"
end, "gold")
action(pPlayer, "Perbaiki karakter", function()
  -- lepas semua sisa gaya + PlatformStand: obat kalau karakter terhuyung
  stopGlide()
  local h = hum()
  if h then
    h.PlatformStand = false
    h.Sit = false
    h:ChangeState(Enum.HumanoidStateType.GettingUp)
    h.WalkSpeed = S.speedOn and S.speed or 16
  end
  S.status = "karakter dibereskan"
end)
action(pPlayer, "Reset karakter", function()
  local h = hum(); if h then h.Health = 0 end
end)

-- --- ESP ---
section(pEsp, "tampilkan")
toggle(pEsp, "ESP Telur", "rarity + nama pet + income $/s",
  function() return S.espEgg end, function(v) S.espEgg = v end)
toggle(pEsp, "ESP Trap", "tandai semua trap merah",
  function() return S.espTrap end, function(v) S.espTrap = v end)
toggle(pEsp, "ESP Bat / Guard", "musuh penjaga nest",
  function() return S.espGuard end, function(v) S.espGuard = v end)
toggle(pEsp, "ESP Pemain", "nama + jarak pemain lain",
  function() return S.espPlayer end, function(v) S.espPlayer = v end)

section(pEsp, "saringan tampilan")
toggle(pEsp, "Tampilkan telur tak dikenal", "pet di luar database tetap ditandai",
  function() return S.espUnknown end, function(v) S.espUnknown = v end)
slider(pEsp, "Rarity minimum", 1, 10,
  function() return S.espMinRarity end, function(v) S.espMinRarity = v end,
  function(v) return RARITY[math.clamp(v, 1, 10)] or "?" end)
slider(pEsp, "Jarak ESP", 200, 5000,
  function() return S.espRange end, function(v) S.espRange = v end,
  function(v) return v .. " stud" end)

section(pEsp, "isi map sekarang")
local infoBox = Instance.new("Frame")
infoBox.Size = UDim2.new(1, 0, 0, 138)
infoBox.BackgroundColor3 = T.panel
infoBox.BorderSizePixel = 0
infoBox.Parent = pEsp
corner(infoBox, 9)
local infoTxt = Instance.new("TextLabel")
infoTxt.Size = UDim2.new(1, -20, 1, -16)
infoTxt.Position = UDim2.new(0, 10, 0, 8)
infoTxt.BackgroundTransparency = 1
infoTxt.Text = "memindai..."
infoTxt.Font = Enum.Font.Code
infoTxt.TextSize = 11
infoTxt.TextColor3 = T.txt2
infoTxt.TextXAlignment = Enum.TextXAlignment.Left
infoTxt.TextYAlignment = Enum.TextYAlignment.Top
infoTxt.Parent = infoBox

action(pEsp, "Scan ulang remote", function()
  local n = indexRemotes()
  S.status = "remote terindeks: " .. n
end)

-- ============ DIAGNOSA NAMA TELUR ============
-- Kalau ESP bilang "pet belum ada di database", masalahnya bukan datanya
-- kurang — tapi nama objek di game tidak cocok dengan pola yang dicari.
-- Tombol ini menampilkan nama MENTAH objek telur di sekitar (dan menyalinnya
-- ke clipboard) supaya nama aslinya bisa ditambahkan ke database.
section(pEsp, "diagnosa nama")
local diagBox = Instance.new("Frame")
diagBox.Size = UDim2.new(1, 0, 0, 150)
diagBox.BackgroundColor3 = T.panel
diagBox.BorderSizePixel = 0
diagBox.Parent = pEsp
corner(diagBox, 9)

local diagScroll = Instance.new("ScrollingFrame")
diagScroll.Size = UDim2.new(1, -14, 1, -12)
diagScroll.Position = UDim2.new(0, 8, 0, 6)
diagScroll.BackgroundTransparency = 1
diagScroll.BorderSizePixel = 0
diagScroll.ScrollBarThickness = 3
diagScroll.ScrollBarImageColor3 = T.line
diagScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
diagScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
diagScroll.Parent = diagBox

local diagTxt = Instance.new("TextLabel")
diagTxt.Size = UDim2.new(1, 0, 0, 0)
diagTxt.AutomaticSize = Enum.AutomaticSize.Y
diagTxt.BackgroundTransparency = 1
diagTxt.Text = "tekan 'Lihat nama asli telur' di bawah"
diagTxt.Font = Enum.Font.Code
diagTxt.TextSize = 10
diagTxt.TextColor3 = T.txt2
diagTxt.TextXAlignment = Enum.TextXAlignment.Left
diagTxt.TextYAlignment = Enum.TextYAlignment.Top
diagTxt.TextWrapped = true
diagTxt.Parent = diagScroll

action(pEsp, "Geledah struktur game (slot telur + prompt)", function()
  local lines = {}
  local sl = Workspace:FindFirstChild("AreaEggSlotsClient")
  lines[#lines + 1] = "AreaEggSlotsClient: " .. (sl and #sl:GetChildren() or 0) .. " slot"
  if sl then
    for i, s in ipairs(sl:GetChildren()) do
      if i > 3 then break end
      lines[#lines + 1] = "  slot " .. tostring(s.Name) .. " [anak " .. #s:GetChildren() .. "]"
      local shown = 0
      for _, d in ipairs(s:GetDescendants()) do
        if shown >= 12 then break end
        local desc = "    " .. tostring(d.Name) .. " [" .. tostring(d.ClassName) .. "]"
        local a = {}
        pcall(function()
          for k, v in pairs(d:GetAttributes()) do
            a[#a + 1] = k .. "=" .. tostring(v)
          end
        end)
        if #a > 0 then desc = desc .. " attr:" .. table.concat(a, ",") end
        if d:IsA("TextLabel") or d:IsA("TextBox") then
          desc = desc .. ' teks:"' .. tostring(d.Text):sub(1, 40) .. '"'
        end
        lines[#lines + 1] = desc
        shown = shown + 1
      end
    end
  end
  local ns = 0
  local sp = Workspace:FindFirstChild("SmartPromptPart")
  if sp then
    for _, p in ipairs(sp:GetChildren()) do
      if p:IsA("ProximityPrompt") then
        ns = ns + 1
        if ns <= 3 then
          local desc = "  prompt " .. tostring(p.Name)
          local pa = {}
          pcall(function()
            for k, v in pairs(p:GetAttributes()) do
              pa[#pa + 1] = k .. "=" .. tostring(v)
            end
          end)
          if #pa > 0 then desc = desc .. " attr:" .. table.concat(pa, ",") end
          for _, c in ipairs(p:GetChildren()) do
            if c:IsA("ObjectValue") and c.Value then
              desc = desc .. " -> " .. tostring(c.Value.Name)
            end
          end
          lines[#lines + 1] = desc
        end
      end
    end
  end
  lines[#lines + 1] = "SmartPromptPart: " .. ns .. " prompt"
  local plots = Workspace:FindFirstChild("Plots")
  lines[#lines + 1] = "Plots: " .. (plots and #plots:GetChildren() or 0) .. " plot"
  for _, fold in ipairs({ "Data", "Shared", "Packages" }) do
    local f = RS:FindFirstChild(fold)
    if f then
      local kids = {}
      for _, d in ipairs(f:GetChildren()) do
        kids[#kids + 1] = d.Name
        if #kids >= 10 then break end
      end
      lines[#lines + 1] = "RS." .. fold .. ": " .. table.concat(kids, ", ")
    end
  end
  -- module data game: di sinilah rarity/pet asli disimpan (RS.Data.Rarity,
  -- Assets, LimitedEgg, AreaEggResetCycle). require() penuh pcall.
  local dataF = RS:FindFirstChild("Data")
  if dataF then
    for _, mn in ipairs({ "Rarity", "Assets", "LimitedEgg", "AreaEggResetCycle" }) do
      local m = dataF:FindFirstChild(mn)
      if m then
        local ok, mod = pcall(function() return require(m) end)
        if ok and type(mod) == "table" then
          local keys, total = {}, 0
          for k in pairs(mod) do
            total = total + 1
            if #keys < 20 then keys[#keys + 1] = tostring(k) end
          end
          lines[#lines + 1] = "module Data." .. mn .. " (" .. total .. " kunci): "
            .. table.concat(keys, ",")
        end
      end
    end
  end
  diagTxt.Text = table.concat(lines, "\n")
    .. "\n\n(disalin ke clipboard kalau executor mendukung)"
  pcall(function() setclipboard(table.concat(lines, "\n")) end)
  S.status = "geledah struktur: " .. (sl and #sl:GetChildren() or 0) .. " slot, " .. ns .. " prompt"
end, "gold")

action(pEsp, "Lihat nama asli telur", function()
  local eggs = scanEggs()
  local lines = {}
  local unknown = {}
  for i, e in ipairs(eggs) do
    if i > 14 then break end
    local mark = e.key and ("OK " .. e.key) or "?? TAK COCOK"
    lines[#lines + 1] = mark .. "  <- " .. tostring(e.obj.Name)
      .. "  [" .. tostring(e.obj.ClassName) .. "]"
    if not e.key then
      unknown[#unknown + 1] = tostring(e.obj.Name)
      -- tampilkan juga nama induk & anak: nama pet sering ada di sana
      local kids = {}
      for _, d in ipairs(e.obj:GetChildren()) do
        kids[#kids + 1] = d.Name
        if #kids >= 5 then break end
      end
      lines[#lines + 1] = "     induk: " .. tostring(e.obj.Parent and e.obj.Parent.Name)
      if #kids > 0 then lines[#lines + 1] = "     anak : " .. table.concat(kids, ", ") end
      local ok, attrs = pcall(function() return e.obj:GetAttributes() end)
      if ok and type(attrs) == "table" then
        local a = {}
        for k, v in pairs(attrs) do a[#a + 1] = k .. "=" .. tostring(v) end
        if #a > 0 then lines[#lines + 1] = "     attr : " .. table.concat(a, ", ") end
      end
    end
  end
  if #eggs == 0 then
    diagTxt.Text = "tidak ada objek telur terdeteksi di sekitar.\n"
      .. "berarti nama objeknya tidak memuat kata 'egg' DAN bukan nama pet.\n"
      .. "pakai tombol di bawah untuk melihat objek apa saja yang dekat."
  else
    diagTxt.Text = table.concat(lines, "\n")
      .. "\n\nnama tak cocok: " .. #unknown .. " dari " .. #eggs
      .. "\n(disalin ke clipboard kalau executor mendukung)"
  end
  local blob = table.concat(unknown, "\n")
  pcall(function() setclipboard(blob) end)
  S.status = "diagnosa: " .. #eggs .. " telur, " .. #unknown .. " tak cocok"
end, "gold")

action(pEsp, "Lihat objek terdekat (semua)", function()
  local h = hrp()
  if not h then diagTxt.Text = "karakter tidak ada"; return end
  local near = {}
  for _, v in ipairs(Workspace:GetDescendants()) do
    if v:IsA("Model") or v:IsA("BasePart") then
      local p = posOf(v)
      if p then
        local d = dist(h.Position, p)
        if d < 90 then near[#near + 1] = { n = v.Name, c = v.ClassName, d = d } end
      end
    end
  end
  table.sort(near, function(a, b) return a.d < b.d end)
  local lines = {}
  for i = 1, math.min(24, #near) do
    lines[#lines + 1] = string.format("%3dm  %s  [%s]",
      math.floor(near[i].d), near[i].n, near[i].c)
  end
  diagTxt.Text = (#lines > 0 and table.concat(lines, "\n") or "tidak ada objek dekat")
    .. "\n\ntotal " .. #near .. " objek dalam 90 stud"
  pcall(function()
    local blob = {}
    for i = 1, math.min(40, #near) do blob[#blob + 1] = near[i].n end
    setclipboard(table.concat(blob, "\n"))
  end)
  S.status = "diagnosa objek: " .. #near .. " dalam 90 stud"
end)

showPage("STEAL")

-- ============ STATUS TICKER ============
task.spawn(function()
  while true do
    task.wait(1)
    pcall(function()
      dot.BackgroundColor3 = S.stealOn and T.jade or T.txt2
      statusTxt.Text = string.format("%s · ok:%d gagal:%d · %s",
        S.status, S.stolen, S.fails, S.lastGrab)
    end)
  end
end)

task.spawn(function()
  while true do
    task.wait(2.5)
    pcall(function()
      if activePage ~= "ESP" then return end
      local eggs = scanEggs()
      local byR, known, best, mine = {}, 0, nil, 0
      for _, e in ipairs(eggs) do
        local k = e.rar or "?"
        byR[k] = (byR[k] or 0) + 1
        if e.mine then mine = mine + 1 end
        if e.income then
          known = known + 1
          local val = e.income * (e.mult or 1)
          if not best or val > (best.income * (best.mult or 1)) then best = e end
        end
      end
      local parts = {}
      for _, r in ipairs(RARITY) do
        if byR[r] then parts[#parts + 1] = r:sub(1, 3) .. ":" .. byR[r] end
      end
      if byR["?"] then parts[#parts + 1] = "??:" .. byR["?"] end

      local bestLine = "-"
      if best then
        bestLine = (best.mut and (best.mut .. " ") or "") .. (best.pet or "?")
          .. " " .. (money(best.income * (best.mult or 1)) or "?")
      end

      infoTxt.Text = table.concat({
        "telur     : " .. #eggs .. "  (income diketahui: " .. known .. ")",
        "milikku   : " .. mine .. "  (diabaikan saat steal)",
        "rincian   : " .. (#parts > 0 and table.concat(parts, " ") or "-"),
        "termahal  : " .. bestLine,
        "trap/musuh: " .. #scanTraps() .. " / " .. #scanHostiles(),
        "remote    : " .. #remotes .. "  · database: " .. DB_COUNT .. " pet",
      }, "\n")
    end)
  end
end)

-- ticker: perbarui panel belajar supaya hasilnya terlihat tanpa menekan apa pun
task.spawn(function()
  local last = ""
  while true do
    task.wait(1)
    pcall(function()
      if activePage ~= "STEAL" then return end
      local s = SPY.summary()
      if s ~= last then last = s; learnTxt.Text = s end
    end)
  end
end)

print("[SAE v6] loaded · remote=" .. #remotes .. " · db=" .. DB_COUNT
  .. " · resep=" .. (SPY.onDisk and "termuat" or "belum ada"))


-- ============ TAB PREDIKSI ============
makeTab("PREDIKSI", 92)
local pPred = makePage("PREDIKSI")

-- panel peringatan jujur di paling atas
local warnBox = Instance.new("Frame")
warnBox.Size = UDim2.new(1, 0, 0, 58)
warnBox.BackgroundColor3 = Color3.fromRGB(38, 30, 18)
warnBox.BorderSizePixel = 0
warnBox.Parent = pPred
corner(warnBox, 9)
stroke(warnBox, Color3.fromRGB(90, 70, 30), 1)

local warnTxt = Instance.new("TextLabel")
warnTxt.Size = UDim2.new(1, -20, 1, -12)
warnTxt.Position = UDim2.new(0, 10, 0, 6)
warnTxt.BackgroundTransparency = 1
warnTxt.Text = "Spawn Secret/Eternal/Divine itu undian acak tiap reset — tidak ada jadwal jam pasti. Yang di bawah diukur dari server ini, bukan dikarang."
warnTxt.Font = Enum.Font.Gotham
warnTxt.TextSize = 10
warnTxt.TextColor3 = Color3.fromRGB(235, 200, 130)
warnTxt.TextWrapped = true
warnTxt.TextXAlignment = Enum.TextXAlignment.Left
warnTxt.TextYAlignment = Enum.TextYAlignment.Top
warnTxt.Parent = warnBox

section(pPred, "pengamat siklus")
toggle(pPred, "Pantau siklus telur", "ukur periode reset dari map",
  function() return PRED.watch end, function(v) PRED.watch = v end)
toggle(pPred, "Auto kejar telur langka", "otomatis ambil begitu muncul",
  function() return PRED.autoGo end, function(v) PRED.autoGo = v end)

section(pPred, "rarity yang dipantau")
local pgrid = Instance.new("Frame")
pgrid.Size = UDim2.new(1, 0, 0, 0)
pgrid.AutomaticSize = Enum.AutomaticSize.Y
pgrid.BackgroundTransparency = 1
pgrid.Parent = pPred
local pgl = Instance.new("UIGridLayout")
pgl.CellSize = UDim2.new(0.5, -4, 0, 34)
pgl.CellPadding = UDim2.new(0, 7, 0, 7)
pgl.Parent = pgrid

local WATCHABLE = { "Legendary", "Mythic", "Cosmic", "Secret", "Eternal", "Divine" }
for _, r in ipairs(WATCHABLE) do
  local b = Instance.new("TextButton")
  b.BackgroundColor3 = T.panel
  b.Text = r
  b.Font = Enum.Font.GothamBold
  b.TextSize = 11
  b.AutoButtonColor = false
  b.Parent = pgrid
  corner(b, 8)
  local st = stroke(b, T.line, 1)
  local function paint()
    local on = PRED.notify[r] == true
    b.BackgroundColor3 = on and T.panel2 or T.panel
    b.TextColor3 = on and (RCOLOR[r] or T.txt) or T.txt2
    st.Color = on and (RCOLOR[r] or T.line) or T.line
    st.Thickness = on and 1.6 or 1
  end
  b.MouseButton1Click:Connect(function()
    PRED.notify[r] = not PRED.notify[r]; paint()
  end)
  paint()
end

section(pPred, "hitung mundur reset")
local cdBox = Instance.new("Frame")
cdBox.Size = UDim2.new(1, 0, 0, 76)
cdBox.BackgroundColor3 = T.panel
cdBox.BorderSizePixel = 0
cdBox.Parent = pPred
corner(cdBox, 9)

local cdBig = Instance.new("TextLabel")
cdBig.Size = UDim2.new(1, -20, 0, 40)
cdBig.Position = UDim2.new(0, 10, 0, 8)
cdBig.BackgroundTransparency = 1
cdBig.Text = "--"
cdBig.Font = Enum.Font.GothamBlack
cdBig.TextSize = 30
cdBig.TextColor3 = T.gold
cdBig.TextXAlignment = Enum.TextXAlignment.Left
cdBig.Parent = cdBox

local cdSub = Instance.new("TextLabel")
cdSub.Size = UDim2.new(1, -20, 0, 20)
cdSub.Position = UDim2.new(0, 10, 0, 50)
cdSub.BackgroundTransparency = 1
cdSub.Text = "nyalakan pantau siklus dulu"
cdSub.Font = Enum.Font.Code
cdSub.TextSize = 10
cdSub.TextColor3 = T.txt2
cdSub.TextXAlignment = Enum.TextXAlignment.Left
cdSub.Parent = cdBox

section(pPred, "peluang terukur")
local oddsBox = Instance.new("Frame")
oddsBox.Size = UDim2.new(1, 0, 0, 118)
oddsBox.BackgroundColor3 = T.panel
oddsBox.BorderSizePixel = 0
oddsBox.Parent = pPred
corner(oddsBox, 9)
local oddsTxt = Instance.new("TextLabel")
oddsTxt.Size = UDim2.new(1, -20, 1, -14)
oddsTxt.Position = UDim2.new(0, 10, 0, 7)
oddsTxt.BackgroundTransparency = 1
oddsTxt.Text = "belum ada reset tercatat"
oddsTxt.Font = Enum.Font.Code
oddsTxt.TextSize = 10
oddsTxt.TextColor3 = T.txt2
oddsTxt.TextXAlignment = Enum.TextXAlignment.Left
oddsTxt.TextYAlignment = Enum.TextYAlignment.Top
oddsTxt.Parent = oddsBox

section(pPred, "temuan langka")
local alertBox = Instance.new("Frame")
alertBox.Size = UDim2.new(1, 0, 0, 108)
alertBox.BackgroundColor3 = T.panel
alertBox.BorderSizePixel = 0
alertBox.Parent = pPred
corner(alertBox, 9)
local alertTxt = Instance.new("TextLabel")
alertTxt.Size = UDim2.new(1, -20, 1, -14)
alertTxt.Position = UDim2.new(0, 10, 0, 7)
alertTxt.BackgroundTransparency = 1
alertTxt.Text = "belum ada"
alertTxt.Font = Enum.Font.Code
alertTxt.TextSize = 10
alertTxt.TextColor3 = T.txt2
alertTxt.TextXAlignment = Enum.TextXAlignment.Left
alertTxt.TextYAlignment = Enum.TextYAlignment.Top
alertTxt.Parent = alertBox

section(pPred, "uji kejujuran")
local probeBox = Instance.new("Frame")
probeBox.Size = UDim2.new(1, 0, 0, 92)
probeBox.BackgroundColor3 = T.panel
probeBox.BorderSizePixel = 0
probeBox.Parent = pPred
corner(probeBox, 9)
local probeTxt = Instance.new("TextLabel")
probeTxt.Size = UDim2.new(1, -20, 1, -14)
probeTxt.Position = UDim2.new(0, 10, 0, 7)
probeTxt.BackgroundTransparency = 1
probeTxt.Text = "tekan tombol di bawah untuk cek apakah server\nmengirim data telur berikutnya"
probeTxt.Font = Enum.Font.Code
probeTxt.TextSize = 10
probeTxt.TextColor3 = T.txt2
probeTxt.TextXAlignment = Enum.TextXAlignment.Left
probeTxt.TextYAlignment = Enum.TextYAlignment.Top
probeTxt.Parent = probeBox

action(pPred, "Cek data 'telur berikutnya'", function()
  local p = probeNextEgg()
  local n = hookAnnouncements()
  if p.found == 0 then
    probeTxt.Text = "HASIL: server TIDAK mengirim data telur berikutnya.\n"
      .. "Jadi prediksi rarity pasti memang mustahil dari klien.\n"
      .. "hook pengumuman aktif: " .. n .. " remote"
    probeTxt.TextColor3 = Color3.fromRGB(235, 170, 140)
  else
    local lines = { "HASIL: ada " .. p.found .. " nilai yang mungkin relevan:" }
    for i = 1, math.min(4, #p.list) do lines[#lines + 1] = "  " .. p.list[i] end
    probeTxt.Text = table.concat(lines, "\n")
    probeTxt.TextColor3 = T.jade
  end
end, "gold")

action(pPred, "Reset data pengamatan", function()
  PRED.resetTimes = {}; PRED.counts = {}; PRED.seenNames = {}
  PRED.observed = 0; PRED.period = nil; PRED.lastReset = nil
  PRED.alerts = {}; PRED.sig = nil
end)

-- ticker halaman prediksi
task.spawn(function()
  while true do
    task.wait(1)
    pcall(function()
      if activePage ~= "PREDIKSI" then return end

      local left, src = nextResetIn()
      cdBig.Text = left and fmtDur(left) or "--"
      cdBig.TextColor3 = (left and left < 25) and T.jade or T.gold
      local perTxt = PRED.period and (fmtDur(PRED.period) .. "/siklus") or "periode belum terukur"
      cdSub.Text = string.format("%s · %s · reset tercatat: %d", src, perTxt, PRED.observed)

      -- peluang
      if PRED.observed < 1 then
        oddsTxt.Text = PRED.watch
          and "mengamati... butuh minimal 2 reset (~10 menit)"
          or  "nyalakan 'Pantau siklus telur'"
      else
        local lines = {}
        for _, r in ipairs({ "Cosmic", "Secret", "Eternal", "Divine" }) do
          local wait, n, rate = odds(r)
          if wait then
            lines[#lines + 1] = string.format("%-8s %5.1f%% · tiap ~%s",
              r, rate * 100, fmtDur(wait))
          else
            lines[#lines + 1] = string.format("%-8s   belum pernah terlihat (%d reset)", r, n)
          end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "angka dari server ini saja, bukan global"
        oddsTxt.Text = table.concat(lines, "\n")
      end

      -- temuan
      if #PRED.alerts == 0 then
        alertTxt.Text = PRED.watch and "belum ada telur langka terdeteksi" or "pengamat mati"
      else
        local lines = {}
        local h = hrp()
        for i = 1, math.min(5, #PRED.alerts) do
          local a = PRED.alerts[i]
          local ago = fmtDur(tick() - a.t)
          local d = (h and a.pos) and (math.floor(dist(h.Position, a.pos)) .. "m") or "?"
          lines[#lines + 1] = string.format("%s%s · %s · %s lalu",
            (a.mut and (a.mut .. " ") or ""), a.rar, d, ago)
        end
        if PRED.lastAnn then
          lines[#lines + 1] = "pengumuman server: " .. PRED.lastAnn.rar
        end
        alertTxt.Text = table.concat(lines, "\n")
      end
    end)
  end
end)


-- ============ TEST HOOK ============
-- Publishes internals only when a harness sets SAE_TEST as a global first.
-- Roblox/Delta never set it, so nothing leaks into the game environment.
-- Note: in the standalone Luau CLI, top-level globals land in getfenv(0),
-- which is NOT the same table as _G — so both are checked and written.
do
  local env = getfenv(0)
  local flagged = rawget(env, "SAE_TEST") or (type(_G) == "table" and rawget(_G, "SAE_TEST"))
  if flagged then
    local api = {
      S            = S,
      RARITY       = RARITY,
      MUTATION     = MUTATION,
      RCOLOR       = RCOLOR,
      scanEggs     = scanEggs,
      scanTraps    = scanTraps,
      scanHostiles = scanHostiles,
      rarityOf     = rarityOf,
      mutationOf   = mutationOf,
      weightOf     = weightOf,
      myBase       = myBase,
      pickEgg      = pickEgg,
      eggScore     = eggScore,
      glideTo      = glideTo,
      stopGlide    = stopGlide,
      fireMatch    = fireMatch,
      indexRemotes = indexRemotes,
      getRemotes   = function() return remotes end,
      pressPromptsNear = pressPromptsNear,
      findRemoteByName   = findRemoteByName,
      fireSmartPrompts   = fireSmartPrompts,
      zoneOf             = zoneOf,
      scanSlotEggs       = scanSlotEggs,
      plotState          = plotState,
      firstPartOf        = firstPartOf,
      findNamed          = findNamed,
      heldByOther        = heldByOther,
      flushBaseCache     = flushBaseCache,
      -- database pet
      DB           = DB,
      DB_COUNT     = DB_COUNT,
      DISPLAY      = DISPLAY,
      dbLookup     = dbLookup,
      dbExact      = dbExact,
      dbStripMutation = dbStripMutation,
      incomeOf     = incomeOf,
      money        = money,
      kg           = kg,
      MUT_MULT     = MUT_MULT,
      walkTo       = walkTo,
      hopTo        = hopTo,
      moveTo       = moveTo,
      avoidOffset  = avoidOffset,
      nearOwnBase  = nearOwnBase,
      heldByMe     = heldByMe,
      grabAttempt  = grabAttempt,
      promptsInside = promptsInside,
      touchAllParts = touchAllParts,
      -- perekam & pembelajar cara ambil
      SPY            = SPY,
      startLearning  = startLearning,
      stopLearning   = stopLearning,
      learnTxt       = learnTxt,
      gui          = gui,
      win          = win,
      orb          = orb,
      pages        = pages,
      tabs         = tabs,
      showPage     = showPage,
      espFolder    = espF,
      statusTxt    = statusTxt,
      diagTxt      = diagTxt,
      textBlob     = textBlob,
      attrBlob     = attrBlob,
      rarityOf     = rarityOf,
      scanEggs     = scanEggs,
      hideBtn      = hideBtn,
      rarityBtns   = rarityBtns,
      -- prediksi
      PRED         = PRED,
      eggSignature = eggSignature,
      similarity   = similarity,
      computePeriod = computePeriod,
      nextResetIn  = nextResetIn,
      odds         = odds,
      probeNextEgg = probeNextEgg,
      findLiveTimer = findLiveTimer,
      hookAnnouncements = hookAnnouncements,
      fmtDur       = fmtDur,
      predPage     = pPred,
      cdBig        = cdBig,
      cdSub        = cdSub,
      oddsTxt      = oddsTxt,
      alertTxt     = alertTxt,
      probeTxt     = probeTxt,
    }
    env.SAE = api
    -- _G may be readonly (standalone Luau CLI); ignore if so
    pcall(function()
      if type(_G) == "table" then _G.SAE = api end
    end)
  end
end
