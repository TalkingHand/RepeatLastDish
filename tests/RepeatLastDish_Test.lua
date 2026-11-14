-- Repeat Last Dish in-game test (pzt TEST_FILES only, not shipped). One client, every scenario.
-- RLDTest.start() runs the scenarios as coroutines on OnTick; RLDTest.poll() re-queues itself until done.
-- Results: "[RLDTest] PASS/FAIL" lines; failures also "[PZTest] FAIL". No error() (debugger freezes).

RLDTest = RLDTest or {}
local T = RLDTest
local M = function() return RepeatLastDish end

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	print("[RLDTest] " .. table.concat(parts, " "))
end

T.pass, T.fail = 0, 0
local function check(ok, label, extra)
	if ok then T.pass = T.pass + 1 else T.fail = T.fail + 1 end
	log(ok and "PASS" or "FAIL", T.scenario or "", label, extra ~= nil and tostring(extra) or "")
	if not ok and PZTest and PZTest.fail then PZTest.fail("RLDTest " .. tostring(T.scenario) .. " " .. label .. " " .. tostring(extra or "")) end
	return ok
end

local function p() return getPlayer() end
local function inv() return p():getInventory() end
local function queue() return ISTimedActionQueue.getTimedActionQueue(p()).queue end

local function yield() coroutine.yield() end
local function waitTicks(n) for _ = 1, n do yield() end end
local function waitUntil(fn, ticks, label)
	for _ = 1, ticks do
		local ok, res = pcall(fn)
		if ok and res then return true end
		yield()
	end
	if label then log("timeout:", label, ticks) end
	return false
end
local function idle() return #queue() == 0 and #M().watches == 0 and not (M().task and M().task.waitQueue) end
-- the run is over when the queue stayed empty and no add is being watched for a while
local function waitRunEnd(ticks, label)
	local quiet = 0
	return waitUntil(function()
		if idle() then quiet = quiet + 1 else quiet = 0 end
		return quiet > 30
	end, ticks, label)
end

------------------------------------------------------------------ world setup

local function protect()
	local pl = p()
	pl:setGodMod(true)
	pl:setInvisible(true)
	pl:setZombiesDontAttack(true)
	local list = getCell():getZombieList()
	for i = list:size() - 1, 0, -1 do
		local z = list:get(i)
		if z and z:DistTo(pl) < 60 then z:removeFromSquare(); z:removeFromWorld() end
	end
end

local function clearAll()
	ISTimedActionQueue.clear(p())
	M().task = nil
	inv():clear()
	if T.fridge then T.fridge:clear() end
	ISInventoryPage.dirtyUI()
end

-- a fridge next to the player (falls back to a crate sprite); its container is what the loot pane shows
local function makeFridge()
	local pl = p()
	local sq = getCell():getGridSquare(pl:getX() + 1, pl:getY(), pl:getZ())
	for _, sprite in ipairs({ "appliances_refrigeration_01_0", "carpentry_01_16" }) do
		local ok, obj = pcall(function()
			local o = IsoObject.new(getCell(), sq, sprite)
			o:createContainersFromSpriteProperties()
			sq:AddSpecialObject(o)
			return o
		end)
		if ok and obj and obj:getContainer() then
			T.fridgeObj = obj
			log("container object", sprite, obj:getContainer():getType())
			return obj:getContainer()
		end
	end
	return nil
end

local function add(container, fullType, n)
	local out = {}
	for i = 1, (n or 1) do out[i] = container:AddItem(fullType) end
	return out
end

local function setRotten(item) item:setAge(item:getOffAgeMax() + 5) end
local function setStale(item) item:setAge((item:getOffAge() + item:getOffAgeMax()) / 2) end

local function countType(container, fullType)
	return container:getItemsFromFullType(fullType):size()
end

local function extraList(food)
	local t = {}
	local ex = food:getExtraItems()
	if ex then for i = 0, ex:size() - 1 do t[#t + 1] = tostring(ex:get(i)) end end
	return table.concat(t, ",")
end

local function salads()
	local list = inv():getItemsFromFullType("Base.Salad")
	local t = {}
	for i = 0, list:size() - 1 do t[#t + 1] = list:get(i) end
	return t
end

local function loot()
	ISInventoryPage.dirtyUI()
	waitTicks(10)
	local list = ISInventoryPaneContextMenu.getContainers(p())
	for i = 0, list:size() - 1 do
		if list:get(i) == T.fridge then return true end
	end
	return false
end

local function saladRecipe(bowl)
	local list = RecipeManager.getEvolvedRecipe(bowl, p(), ISInventoryPaneContextMenu.getContainers(p()), false)
	for i = 0, list:size() - 1 do
		local r = list:get(i)
		if r:isResultItem(inv():AddItem("Base.Salad")) then
			inv():RemoveAll("Salad")
			return r
		end
	end
	inv():RemoveAll("Salad")
	return nil
end

-- the same context menu call the inventory pane makes, with a recording stand-in for the menu
local function fakeMenu(items)
	local ctx = { options = {} }
	function ctx:addOption(name, target, fn, a1, a2)
		local o = { name = name, target = target, onSelect = fn, param1 = a1, param2 = a2 }
		self.options[#self.options + 1] = o
		return o
	end
	M().onFillMenu(0, ctx, items)
	local mine
	for _, o in ipairs(ctx.options) do
		if o.onSelect == M().start then mine = o end
	end
	return mine, ctx
end

------------------------------------------------------------------ scenarios

local LETTUCE, TOMATO, CUCUMBER = "Base.Lettuce", "Base.Tomato", "Base.Cucumber"

local function setup()
	protect()
	p():setTimedActionInstantCheat(false)
	T.fridge = makeFridge()
	check(T.fridge ~= nil, "test container made")
	clearAll()
	-- loot() waits ticks itself, so it must not run inside waitUntil's pcall (no yield across pcall)
	local shown = false
	for _ = 1, 12 do
		if loot() then shown = true; break end
	end
	check(shown, "fridge shown in loot containers")
	check(M() and M().installed, "mod installed")
	T.cookLvl = p():getPerkLevel(Perks.Cooking)
end

-- by hand (vanilla flow): bowl + lettuce, tomato, cucumber -> recorded in that order
local function record()
	clearAll()
	p():getModData().RepeatLastDish = nil
	local bowl = inv():AddItem("Base.Bowl")
	add(inv(), LETTUCE); add(inv(), TOMATO); add(inv(), CUCUMBER)
	local recipe = saladRecipe(bowl)
	if not check(recipe ~= nil, "salad recipe for bowl") then return end
	log("recipe name", recipe:getName(), recipe:getUntranslatedName())
	-- nothing recorded yet: no menu option
	check(fakeMenu({ bowl }) == nil, "no option before any dish")
	local base = bowl
	for _, ft in ipairs({ LETTUCE, TOMATO, CUCUMBER }) do
		local item = inv():getFirstTypeRecurse(ft:sub(6))
		ISInventoryPaneContextMenu.onAddItemInEvoRecipe(recipe, base, item, 0)
		waitRunEnd(1200, "hand add " .. ft)
		base = salads()[1]
		if not check(base ~= nil, "salad after " .. ft) then return end
	end
	local last = M().getLast(p())
	check(last ~= nil, "last dish recorded")
	if last then
		check(last.base == "Base.Bowl", "base recorded", last.base)
		check(table.concat(last.items, ",") == "Base.Lettuce,Base.Tomato,Base.Cucumber", "ingredients in order", table.concat(last.items, ","))
		check(last.recipe == recipe:getUntranslatedName(), "recipe recorded (untranslated)", last.recipe)
	end
	T.recipeName = recipe:getUntranslatedName()
	-- adding to a salad we never saw started does not replace the record
	clearAll()
	local stray = inv():AddItem("Base.Salad")
	add(inv(), TOMATO)
	local r2 = M().findRecipe(p(), stray, T.recipeName, ISInventoryPaneContextMenu.getContainers(p()))
	if r2 then
		ISInventoryPaneContextMenu.onAddItemInEvoRecipe(r2, stray, inv():getFirstTypeRecurse("Tomato"), 0)
		waitRunEnd(1200, "stray add")
		local l2 = M().getLast(p())
		check(l2 and #l2.items == 3, "stray salad does not overwrite record", l2 and table.concat(l2.items, ","))
	else
		log("no recipe for stray salad (skipped check)")
	end
end

-- two bowls in the fridge, ingredients in the fridge incl. a rotten lettuce and a stale tomato
local function repeatTwo()
	clearAll()
	local f = T.fridge
	local bowls = add(f, "Base.Bowl", 2)
	local rotten = add(f, LETTUCE)[1]; setRotten(rotten)
	check(rotten:isRotten(), "rotten lettuce is rotten")
	add(f, LETTUCE, 2)
	local stale = add(f, TOMATO)[1]; setStale(stale)
	local staleHunger = stale:getHungChange()
	check(not stale:isRotten() and not stale:isFresh(), "stale tomato is stale, not rotten")
	add(f, TOMATO)
	add(f, CUCUMBER, 2)
	loot()
	local opt = fakeMenu(bowls)
	check(opt ~= nil, "option on two bowls")
	if opt then
		log("option text:", opt.name, "tooltip:", opt.toolTip and opt.toolTip.description)
		check(not opt.notAvailable, "option available")
		check(opt.name:find("2") ~= nil, "option shows count", opt.name)
		M().start(p(), opt.param1)
	end
	waitRunEnd(6000, "repeat two")
	local s = salads()
	check(#s == 2, "two salads made", #s)
	for i, sal in ipairs(s) do
		check(extraList(sal) == "Base.Lettuce,Base.Tomato,Base.Cucumber", "salad " .. i .. " ingredients in order", extraList(sal))
	end
	check(f:contains(rotten), "rotten lettuce left in fridge")
	check(rotten:isRotten(), "rotten lettuce untouched")
	check(not f:contains(stale) or stale:getHungChange() ~= staleHunger, "stale tomato used (older first)",
		tostring(f:contains(stale)) .. " " .. tostring(staleHunger) .. "->" .. tostring(stale:getHungChange()))
	check(countType(f, "Base.Bowl") == 0, "both bowls used")
	-- leftovers go back to the fridge, nothing but salads in the inventory
	local stray = 0
	local items = inv():getItems()
	for i = 0, items:size() - 1 do if items:get(i):getFullType() ~= "Base.Salad" then stray = stray + 1 end end
	check(stray == 0, "only salads in inventory", stray)
	check(M().task == nil, "task ended")
	check(table.concat(M().getLast(p()).items, ",") == "Base.Lettuce,Base.Tomato,Base.Cucumber", "record unchanged after repeat")
end

-- no cucumber: option greyed out; starting anyway makes nothing and leaves the bowl
local function missing()
	clearAll()
	local f = T.fridge
	local bowl = add(f, "Base.Bowl")[1]
	add(f, LETTUCE); add(f, TOMATO)
	local rc = add(f, CUCUMBER)[1]; setRotten(rc)
	loot()
	local opt = fakeMenu({ bowl })
	check(opt ~= nil and opt.notAvailable == true, "option greyed out when cucumber missing (rotten only)")
	if opt then log("tooltip:", opt.toolTip and opt.toolTip.description) end
	M().start(p(), { bowl })
	waitRunEnd(600, "missing")
	check(#salads() == 0, "no salad made")
	check(f:contains(bowl), "bowl stays in fridge")
	check(countType(f, LETTUCE) == 1, "lettuce untouched")
end

-- enough for one of three bowls: one salad, then stop on the missing ingredient
local function partial()
	clearAll()
	local f = T.fridge
	local bowls = add(inv(), "Base.Bowl", 3)
	add(f, LETTUCE); add(f, TOMATO); add(f, CUCUMBER)
	loot()
	M().start(p(), bowls)
	waitRunEnd(6000, "partial")
	local s = salads()
	-- one lettuce can serve more than one dish (portion use); at least one full salad, and it stopped
	check(#s >= 1, "at least one salad", #s)
	check(#s < 3 or countType(inv(), "Base.Bowl") == 0, "stopped or used every bowl", #s)
	if s[1] then check(extraList(s[1]) == "Base.Lettuce,Base.Tomato,Base.Cucumber", "first salad complete", extraList(s[1])) end
	check(M().task == nil, "task ended")
	log("partial made", #s, "bowls left", countType(inv(), "Base.Bowl"))
end

-- other base type: no option; option only on matching bowls in a mixed selection
local function otherBase()
	clearAll()
	local pan = inv():AddItem("Base.Pan")
	check(fakeMenu({ pan }) == nil, "no option on a pan (last dish base is a bowl)")
	local bowl = inv():AddItem("Base.Bowl")
	add(inv(), LETTUCE); add(inv(), TOMATO); add(inv(), CUCUMBER)
	local opt = fakeMenu({ pan, bowl })
	check(opt ~= nil and #opt.param1 == 1 and opt.param1[1] == bowl, "mixed selection: only the bowl")
	-- stack entry as the inventory pane passes it
	local opt2 = fakeMenu({ { items = { bowl, bowl } } })
	check(opt2 ~= nil and #opt2.param1 == 1, "stack entry counted once")
end

-- cancel during the run: nothing more is queued afterwards
local function cancel()
	clearAll()
	local bowls = add(inv(), "Base.Bowl", 2)
	add(T.fridge, LETTUCE, 2); add(T.fridge, TOMATO, 2); add(T.fridge, CUCUMBER, 2)
	loot()
	M().start(p(), bowls)
	waitUntil(function()
		local a = queue()[1]
		return a and a.Type == "ISAddItemInRecipe" and a:isStarted()
	end, 1200, "first add started")
	ISTimedActionQueue.clear(p())
	waitTicks(600)
	check(#queue() == 0, "queue stays empty after cancel", #queue())
	check(#salads() == 0, "no salad after cancel during first add", #salads())
	-- a new run after a cancelled one works
	M().start(p(), bowls)
	waitRunEnd(6000, "after cancel")
	check(#salads() == 2, "new run after cancel makes two", #salads())
end

-- a spice in the record (garlic after lettuce): vanilla does not list spices for an empty bowl, so
-- the check on the empty bowl must still find it (0.1.1 showed "missing: garlic")
local function spice()
	clearAll()
	p():getModData().RepeatLastDish = nil
	local bowl = inv():AddItem("Base.Bowl")
	add(inv(), LETTUCE); add(inv(), "Base.Garlic")
	local recipe = saladRecipe(bowl)
	if not check(recipe ~= nil, "salad recipe for bowl") then return end
	local base = bowl
	for _, ft in ipairs({ LETTUCE, "Base.Garlic" }) do
		local item = inv():getFirstTypeRecurse(ft:sub(6))
		ISInventoryPaneContextMenu.onAddItemInEvoRecipe(recipe, base, item, 0)
		waitRunEnd(1200, "spice hand add " .. ft)
		base = salads()[1]
		if not check(base ~= nil, "salad after " .. ft) then return end
	end
	local last = M().getLast(p())
	check(last and table.concat(last.items, ",") == "Base.Lettuce,Base.Garlic", "spice recorded", last and table.concat(last.items, ","))
	clearAll()
	local b2 = add(T.fridge, "Base.Bowl")[1]
	add(T.fridge, LETTUCE); add(T.fridge, "Base.Garlic")
	loot()
	local opt = fakeMenu({ b2 })
	check(opt ~= nil and not opt.notAvailable, "option available with garlic in the fridge",
		opt and opt.toolTip and opt.toolTip.description)
	if opt then M().start(p(), opt.param1) end
	waitRunEnd(3000, "spice repeat")
	local s = salads()
	check(#s == 1, "salad made", #s)
	if s[1] then
		local sp = s[1]:getSpices()
		local has = false
		if sp then for i = 0, sp:size() - 1 do if tostring(sp:get(i)):find("Garlic") then has = true end end end
		check(has, "garlic added as spice", sp and tostring(sp))
	end
end

-- the option is the first entry of vanilla's "Make Salad" submenu (real inventory context menu)
local function submenu()
	clearAll()
	local bowl = inv():AddItem("Base.Bowl")
	add(inv(), LETTUCE); add(inv(), "Base.Garlic")
	local ctx = ISInventoryPaneContextMenu.createMenu(0, true, { bowl }, 100, 100)
	if not check(ctx ~= nil, "context menu made") then return end
	local recipe = M().findRecipe(p(), bowl, M().getLast(p()).recipe, ISInventoryPaneContextMenu.getContainers(p()))
	local name = getText("ContextMenu_Create_From_Ingredient", getText("ContextMenu_EvolvedRecipe_" .. recipe:getUntranslatedName()))
	local parent = ctx:getOptionFromName(name)
	check(parent ~= nil and parent.subOption ~= nil, "vanilla make-salad submenu", name)
	local sub = parent and parent.subOption and ctx:getSubMenu(parent.subOption)
	local first = sub and sub.options[1]
	check(first ~= nil and first.onSelect == M().start, "our option first in submenu", first and first.name)
	local inMain = false
	for _, o in ipairs(ctx.options) do if o.onSelect == M().start then inMain = true end end
	check(not inMain, "not also in the main menu")
	ctx:hideAndChildren()
end

-- multiplayer order: the server's change (bowl -> salad, stats) reaches the client before perform.
-- Simulated by running complete() ahead of every perform (outside our wrapper) and making the later
-- complete() a no-op. 0.1.0 took its snapshot in perform and never recorded anything this way.
local function mpOrder()
	clearAll()
	p():getModData().RepeatLastDish = nil
	local ours = ISAddItemInRecipe.perform
	T.mpOurs = ours -- finish() puts it back if this scenario dies halfway
	ISAddItemInRecipe.perform = function(self, ...)
		self:complete()
		self.complete = function() return true end
		return ours(self, ...)
	end
	local ok, err = pcall(function()
		local bowl = inv():AddItem("Base.Bowl")
		add(inv(), LETTUCE); add(inv(), TOMATO); add(inv(), CUCUMBER)
		local recipe = saladRecipe(bowl)
		if not check(recipe ~= nil, "salad recipe for bowl") then return end
		T.mpRecipe, T.mpBase = recipe, bowl
	end)
	if not ok then check(false, "mp setup error", err) end
	local base = T.mpBase
	for _, ft in ipairs({ LETTUCE, TOMATO, CUCUMBER }) do
		if not base then break end
		local item = inv():getFirstTypeRecurse(ft:sub(6))
		ISInventoryPaneContextMenu.onAddItemInEvoRecipe(T.mpRecipe, base, item, 0)
		waitRunEnd(1200, "mp hand add " .. ft)
		base = salads()[1]
		check(base ~= nil, "mp salad after " .. ft)
	end
	local last = M().getLast(p())
	check(last ~= nil and table.concat(last.items, ",") == "Base.Lettuce,Base.Tomato,Base.Cucumber",
		"mp: hand-made salad recorded", last and table.concat(last.items, ","))
	-- repeat two under the same order
	clearAll()
	local bowls = add(inv(), "Base.Bowl", 2)
	add(T.fridge, LETTUCE, 2); add(T.fridge, TOMATO, 2); add(T.fridge, CUCUMBER, 2)
	loot()
	local t0 = getTimestampMs()
	M().start(p(), bowls)
	waitRunEnd(6000, "mp repeat two")
	local s = salads()
	check(#s == 2, "mp: two salads made", #s)
	for i, sal in ipairs(s) do
		check(extraList(sal) == "Base.Lettuce,Base.Tomato,Base.Cucumber", "mp salad " .. i .. " ingredients in order", extraList(sal))
	end
	log("mp repeat two took ms", getTimestampMs() - t0)
	ISAddItemInRecipe.perform = ours
	T.mpOurs = nil
end

------------------------------------------------------------------ cook what spoils first

local function setLeft(item, days) item:setAge(item:getOffAgeMax() - days) end

local function setCooking(lvl)
	pcall(function() p():setPerkLevelDebug(Perks.Cooking, lvl) end)
	return check(p():getPerkLevel(Perks.Cooking) == lvl, "cooking level " .. lvl, p():getPerkLevel(Perks.Cooking))
end

local function short(fullTypes)
	local t = {}
	for i, ft in ipairs(fullTypes) do t[i] = ft:gsub("^Base%.", "") end
	return table.concat(t, ",")
end

local function slice(t, n)
	local out = {}
	for i = 1, math.min(n, #t) do out[i] = t[i] end
	return out
end

local function typeCounts(food)
	local c = {}
	local ex = food:getExtraItems()
	if ex then for i = 0, ex:size() - 1 do local ft = tostring(ex:get(i)); c[ft] = (c[ft] or 0) + 1 end end
	return c
end

local function hasSpice(food, name)
	local sp = food:getSpices()
	if sp then for i = 0, sp:size() - 1 do if tostring(sp:get(i)) == name then return true end end end
	return false
end

-- the vanilla unhappiness step (EvolvedRecipe.addItem 42.22.2) as the mod computes it
local function autoMath()
	local f = M().unhappyStep
	check(f({}, 0, "A", 0) == -5, "new type -5")
	check(f({ A = 1 }, 1, "A", 0) == 0, "2nd copy 0")
	check(f({ A = 2 }, 2, "A", 3) == 5, "3rd copy +5")
	check(f({}, 3, "D", 0) == 0, "cooking 0: 4th ingredient 0")
	check(f({}, 4, "E", 0) == 5, "cooking 0: 5th ingredient +5")
	check(f({ A = 2 }, 4, "A", 1) == 0, "cooking 1: 5th ingredient as 3rd copy 0 (n-2-3*lvl = -1)")
	-- n-2 = 3 > 2: changer += 5-2-6 = -3, so -5 + 5*(-3): vanilla rewards it more, not less
	check(f({}, 5, "F", 2) == -20, "cooking 2: 6th ingredient -20")
end

-- the test fridge for the plan scenarios; returns named items
local function stockFridge()
	local f = T.fridge
	local s = {}
	s.lettuceA = add(f, LETTUCE)[1]; setLeft(s.lettuceA, 0.5)
	s.lettuceB = add(f, LETTUCE)[1]; setLeft(s.lettuceB, 0.6)
	s.tomato = add(f, TOMATO)[1]; setStale(s.tomato); setLeft(s.tomato, 1.0)
	s.cucumber = add(f, CUCUMBER)[1]; setLeft(s.cucumber, 3)
	s.carrots = add(f, "Base.Carrots")[1]; setLeft(s.carrots, 4)
	s.lettuceC = add(f, LETTUCE)[1]
	s.cabbage = add(f, "Base.Cabbage")[1]; setRotten(s.cabbage)
	s.onion = add(f, "Base.Onion")[1]; setLeft(s.onion, 0.2); s.onion:setFavorite(true)
	s.mushroom = add(f, "Base.MushroomGeneric1")[1]; setLeft(s.mushroom, 0.1)
	s.basil = add(f, "Base.Basil")[1]; setLeft(s.basil, 2)
	s.salt = add(f, "Base.Salt")[1]
	s.pepper = add(f, "Base.Pepper")[1]
	s.oil = add(f, "Base.OilOlive")[1]
	s.peanuts = add(f, "Base.Peanuts")[1]
	return s
end

-- what goes in, at cooking 0 and 3, and the real run at cooking 0
local function autoPlan()
	clearAll()
	local bowl = inv():AddItem("Base.Bowl")
	local s = stockFridge()
	loot()
	check(not s.tomato:isFresh() and not s.tomato:isRotten(), "tomato stale")
	check(M().mayBePoisoned(s.mushroom), "wild mushroom counts as may be poisoned")
	check(not M().mayBePoisoned(s.lettuceA), "lettuce does not")
	local recipe = saladRecipe(bowl)
	if not check(recipe ~= nil, "salad recipe") then return end
	local containers = ISInventoryPaneContextMenu.getContainers(p())
	local ex = { [bowl] = true }

	setCooking(3)
	local plan3 = M().planDish(p(), recipe, bowl, containers, ex)
	log("plan cooking 3:", short(plan3))
	-- new types first in spoil order, then a 2nd lettuce (step 0); a 3rd lettuce would be +5
	check(short(slice(plan3, 5)) == "Lettuce,Tomato,Cucumber,Carrots,Lettuce", "cooking 3 mains", short(plan3))

	if not setCooking(0) then return end
	local plan = M().planDish(p(), recipe, bowl, containers, ex)
	log("plan cooking 0:", short(plan))
	check(short(slice(plan, 4)) == "Lettuce,Tomato,Cucumber,Carrots", "cooking 0 mains: 4, no 2nd copy", short(plan))
	check(plan[5] == "Base.Basil", "perishable spice next", plan[5])
	local keep = { ["Base.Salt"] = true, ["Base.Pepper"] = true, ["Base.OilOlive"] = true }
	check(#plan == 7 and keep[plan[6]] and keep[plan[7]], "two lasting spices", short(plan))
	local joined = "," .. table.concat(plan, ",") .. ","
	check(not joined:find(",Base.Peanuts,"), "peanuts (never go off) left out")
	check(not joined:find("Mushroom"), "mushroom left out")
	check(not joined:find("Onion"), "favourite onion left out")
	check(not joined:find("Cabbage"), "rotten cabbage left out")

	-- the option in the real menu, then the run
	local ctx = ISInventoryPaneContextMenu.createMenu(0, true, { bowl }, 100, 100)
	local opt
	local name = getText("ContextMenu_Create_From_Ingredient", getText("ContextMenu_EvolvedRecipe_" .. recipe:getUntranslatedName()))
	local parent = ctx and ctx:getOptionFromName(name)
	local sub = parent and parent.subOption and ctx:getSubMenu(parent.subOption)
	if sub then for _, o in ipairs(sub.options) do if o.onSelect == M().startAuto then opt = o end end end
	check(opt ~= nil and not opt.notAvailable, "auto option in make-salad submenu", opt and opt.name)
	if sub and opt then check(sub.options[1].onSelect == M().start or sub.options[1] == opt, "repeat option stays first") end
	if opt then log("auto tooltip:", opt.toolTip and opt.toolTip.description) end
	if ctx then ctx:hideAndChildren() end
	if not opt then return end
	check(opt.param2 == recipe:getUntranslatedName(), "recipe passed", opt.param2)
	M().startAuto(p(), opt.param1, opt.param2)
	waitRunEnd(6000, "auto run")
	local sl = salads()
	if not check(#sl == 1, "one salad", #sl) then return end
	local dish = sl[1]
	check(extraList(dish) == "Base.Lettuce,Base.Tomato,Base.Cucumber,Base.Carrots", "salad mains", extraList(dish))
	check(hasSpice(dish, "Base.Basil"), "basil in", tostring(dish:getSpices()))
	local nSp = dish:getSpices() and dish:getSpices():size() or 0
	check(nSp == 3, "three spices", nSp)
	log("salad unhappy", dish:getUnhappyChange(), "boredom", dish:getBoredomChange(), "hunger", dish:getHungChange())
	-- 3 x -5 + 0 for the mains, spices lower it further
	check(dish:getUnhappyChange() <= -15, "salad unhappiness at most -15", dish:getUnhappyChange())
	check(not T.fridge:contains(s.lettuceA) or s.lettuceA:getHungChange() ~= s.lettuceB:getHungChange(), "lettuce that goes off first used")
	check(T.fridge:contains(s.mushroom), "mushroom untouched")
	check(T.fridge:contains(s.onion), "onion untouched")
	check(T.fridge:contains(s.cabbage), "cabbage untouched")
	check(T.fridge:contains(s.peanuts), "peanuts untouched")
	local last = M().getLast(p())
	check(last and table.concat(last.items, ",") == table.concat(plan, ","), "auto dish becomes the last dish",
		last and short(last.items))
	check(M().task == nil, "task ended")
	setCooking(3)
end

-- two bowls, cooking 3: each salad planned on what is left, no type a 3rd time in any salad
local function autoTwo()
	clearAll()
	if not setCooking(3) then return end
	local bowls = add(inv(), "Base.Bowl", 2)
	for _, ft in ipairs({ LETTUCE, TOMATO, CUCUMBER }) do
		for _, it in ipairs(add(T.fridge, ft, 3)) do setLeft(it, 1 + ZombRand(3)) end
	end
	loot()
	M().startAuto(p(), bowls, T.recipeName or "Salad")
	waitRunEnd(12000, "auto two")
	local sl = salads()
	check(#sl == 2, "two salads", #sl)
	for i, sal in ipairs(sl) do
		local worst = 0
		for _, n in pairs(typeCounts(sal)) do worst = math.max(worst, n) end
		check(worst <= 2, "salad " .. i .. ": no 3rd copy", extraList(sal))
	end
	check(countType(inv(), "Base.Bowl") == 0, "both bowls used")
	check(M().task == nil, "task ended")
end

-- only lasting food and rotten food: option greyed out, a run makes nothing
local function autoNone()
	clearAll()
	local bowl = inv():AddItem("Base.Bowl")
	add(T.fridge, "Base.Peanuts"); add(T.fridge, "Base.Salt")
	setRotten(add(T.fridge, LETTUCE)[1])
	loot()
	local recipe = saladRecipe(bowl)
	if not check(recipe ~= nil, "salad recipe") then return end
	local plan = M().planDish(p(), recipe, bowl, ISInventoryPaneContextMenu.getContainers(p()), { [bowl] = true })
	check(#plan == 0, "empty plan", short(plan))
	local ctx = ISInventoryPaneContextMenu.createMenu(0, true, { bowl }, 100, 100)
	local name = getText("ContextMenu_Create_From_Ingredient", getText("ContextMenu_EvolvedRecipe_" .. recipe:getUntranslatedName()))
	local parent = ctx and ctx:getOptionFromName(name)
	local sub = parent and parent.subOption and ctx:getSubMenu(parent.subOption)
	local opt
	if sub then for _, o in ipairs(sub.options) do if o.onSelect == M().startAuto then opt = o end end end
	check(opt ~= nil and opt.notAvailable == true, "option greyed out", sub and "submenu" or "no submenu")
	if ctx then ctx:hideAndChildren() end
	M().startAuto(p(), { bowl }, recipe:getUntranslatedName())
	waitRunEnd(600, "auto none")
	check(#salads() == 0, "no salad")
	check(inv():contains(bowl), "bowl kept")
end

local function finish()
	if T.mpOurs then ISAddItemInRecipe.perform = T.mpOurs; T.mpOurs = nil end
	clearAll()
	if T.cookLvl then pcall(function() p():setPerkLevelDebug(Perks.Cooking, T.cookLvl) end) end
	if T.fridgeObj then pcall(function() T.fridgeObj:getSquare():RemoveTileObject(T.fridgeObj) end) end
	p():setGodMod(false)
	p():setInvisible(false)
	p():setZombiesDontAttack(false)
end

------------------------------------------------------------------ driver
local SCENARIOS = {
	{ "setup", setup }, { "record", record }, { "repeatTwo", repeatTwo }, { "missing", missing },
	{ "partial", partial }, { "otherBase", otherBase }, { "cancel", cancel }, { "spice", spice }, { "submenu", submenu }, { "mpOrder", mpOrder },
	{ "autoMath", autoMath }, { "autoPlan", autoPlan }, { "autoTwo", autoTwo }, { "autoNone", autoNone }, { "end", finish },
}

-- The driver is one top-level OnTick handler (a Lua reload replaces top-level handlers; one added
-- inside start() would survive a reload and keep running the old scenarios). State lives in
-- T.run; T.done stays true so a handler left by an older version of this file does nothing.
T.done = true

local function onTick()
	local r = T.run
	if not r or r.finished then return end
	if not r.co then
		r.idx = r.idx + 1
		local sc = SCENARIOS[r.idx]
		if not sc then
			T.scenario = "summary"
			log("SUMMARY pass=" .. T.pass .. " fail=" .. T.fail)
			r.finished = true
			return
		end
		T.scenario = sc[1]
		log("scenario", sc[1])
		r.co = coroutine.create(sc[2])
	end
	local ok, err = coroutine.resume(r.co)
	if not ok then check(false, "scenario error", err) end
	if not ok or coroutine.status(r.co) == "dead" then r.co = nil end
end
Events.OnTick.Add(onTick)

function T.start()
	T.pass, T.fail = 0, 0
	T.run = { idx = 0, startedAt = getTimestamp() }
	log("started")
end

function T.poll()
	local r = T.run
	if not r then return end
	if r.finished then
		log("done pass=" .. T.pass .. " fail=" .. T.fail)
		return
	end
	if getTimestamp() - r.startedAt > 1500 then
		check(false, "overall timeout")
		r.finished = true
		return
	end
	log("running", T.scenario, "pass=" .. T.pass, "fail=" .. T.fail)
	PZTest.step("wait 60")
	PZTest.step("lua RLDTest.poll()")
end
