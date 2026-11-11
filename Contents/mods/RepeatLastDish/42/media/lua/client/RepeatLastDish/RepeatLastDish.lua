-- Repeat Last Dish: remembers the ingredients you put into your last evolved-recipe dish (salad,
-- stir fry, ...) in order, and adds a right-click option on the same empty base (bowl, pan) that
-- takes those ingredients from your inventory and nearby containers (fridge) and adds them again.
-- Several selected bases are filled one after another. Rotten ingredients are never used.
--
-- Single player and multiplayer use the same path. ISAddItemInRecipe:perform runs on the client in
-- both; complete() (the actual change) runs right after it in single player and on the server in
-- multiplayer, whose result reaches the client around the same time, often before perform. So the
-- state is taken in start (before the server has the action), and after perform we watch the
-- inventory until the change is there (bowl replaced by a salad, ingredient used up or reduced) and
-- only then record it or queue the next ingredient.

RepeatLastDish = RepeatLastDish or {}
local M = RepeatLastDish
local MODDATA_KEY = "RepeatLastDish"
local SETTLE_MS = 3000     -- an add with no visible change: go on after this
local RESULT_MS = 15000    -- the first add must turn the base into the dish within this

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	print("[RepeatLastDish] " .. table.concat(parts, " "))
end

local function now() return getTimestampMs() end

------------------------------------------------------------------ saved record
-- single player: player mod data (travels with the save). Multiplayer: the client's player mod data
-- is not what the server saves, so a small file per server and character in Zomboid/Lua/.

local function recordFile(player)
	local function clean(s) return (tostring(s or ""):gsub("[^%w%-]", "_")) end
	return "RepeatLastDish_" .. clean(getServerIP()) .. "_" .. clean(getServerPort()) .. "_"
		.. clean(getServerName()) .. "_" .. clean(player:getUsername()) .. ".txt"
end

local function copyRecord(r)
	if type(r) ~= "table" or not r.recipe or not r.base or type(r.items) ~= "table" then return nil end
	local items = {}
	for i = 1, #r.items do items[i] = tostring(r.items[i]) end
	if #items == 0 then return nil end
	return { recipe = tostring(r.recipe), base = tostring(r.base), items = items }
end

local function readFile(player)
	local reader = getFileReader(recordFile(player), false)
	if not reader then return nil end
	local lines = {}
	local line = reader:readLine()
	while line do
		lines[#lines + 1] = line
		line = reader:readLine()
	end
	reader:close()
	if #lines < 3 then return nil end
	local r = { recipe = lines[1], base = lines[2], items = {} }
	for i = 3, #lines do if lines[i] ~= "" then r.items[#r.items + 1] = lines[i] end end
	return copyRecord(r)
end

local function writeFile(player, r)
	local writer = getFileWriter(recordFile(player), true, false)
	if not writer then return end
	writer:write(r.recipe .. "\n" .. r.base .. "\n")
	for _, ft in ipairs(r.items) do writer:write(ft .. "\n") end
	writer:close()
end

M.cache = M.cache or {}

function M.getLast(player)
	if not player then return nil end
	if isClient() then
		local key = recordFile(player)
		if M.cache[key] == nil then
			local ok, r = pcall(readFile, player)
			if not ok then log("read error", r) end
			M.cache[key] = ok and r or false
		end
		return copyRecord(M.cache[key] or nil)
	end
	return copyRecord(player:getModData()[MODDATA_KEY])
end

local function saveLast(player, session)
	local r = copyRecord(session)
	if not r then return end
	if isClient() then
		M.cache[recordFile(player)] = r
		local ok, err = pcall(writeFile, player, r)
		if not ok then log("write error", err) end
	else
		player:getModData()[MODDATA_KEY] = r
	end
end

------------------------------------------------------------------ watching an add until it shows

-- dishes being made by hand, keyed by the dish item's ID: { recipe, base, items = {fullType...} }
M.sessions = M.sessions or {}
M.watches = M.watches or {}

local function resultMatches(recipe, item)
	local full = recipe:getFullResultItem()
	if full and item:getFullType() == full then return true end
	local short = recipe:getResultItem()
	return short ~= nil and (item:getType() == short or item:getFullType() == short)
end

local function resultIds(recipe, container)
	local ids = {}
	if not container then return ids end
	local items = container:getItems()
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		if resultMatches(recipe, it) then ids[it:getID()] = true end
	end
	return ids
end

local function newResult(w)
	local items = w.container:getItems()
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		if not w.preIds[it:getID()] and resultMatches(w.recipe, it) then return it end
	end
	return nil
end

local function usedSig(item)
	local parts = { tostring(item:getContainer()) }
	if instanceof(item, "Food") then parts[#parts + 1] = tostring(item:getHungChange()) end
	local ok, v = pcall(function() return item:getCurrentUsesFloat() end)
	if ok then parts[#parts + 1] = tostring(v) end
	return table.concat(parts, "|")
end

-- the dish: its ingredient list shows the add at once in single player, but multiplayer does not
-- send it to the client (ItemStatsPacket carries hunger, uses, cooked and name), so hunger and name too
local function dishSig(base)
	if not instanceof(base, "Food") then return "" end
	local n = 0
	if base:getExtraItems() then n = n + base:getExtraItems():size() end
	if base:getSpices() then n = n + base:getSpices():size() end
	return n .. "|" .. tostring(base:getHungChange()) .. "|" .. tostring(base:getName())
end

-- the add is visible on this client: the dish item now (nil when the first add never showed)
local function settled(w)
	if not w.isResult then
		-- first ingredient: the base is replaced by a new dish item
		local res = newResult(w)
		if res and not w.container:containsID(w.baseId) then return true, res end
		if now() - w.at > RESULT_MS then return true, nil end
		return false
	end
	-- the used item too: a spice barely changes the dish, but its own uses go down
	if dishSig(w.base) ~= w.dishSig or usedSig(w.used) ~= w.usedSig then return true, w.base end
	if now() - w.at > SETTLE_MS then return true, w.base end
	return false
end

------------------------------------------------------------------ record

local function recordDone(w, dish)
	if not dish then return end
	local session
	if not w.isResult then
		session = { recipe = w.recipeName, base = w.baseType, items = {} }
	else
		session = M.sessions[w.baseId]
		M.sessions[w.baseId] = nil
		-- adding to a dish we did not see being started: nothing to repeat from
		if not session or session.recipe ~= w.recipeName then return end
	end
	session.items[#session.items + 1] = w.usedType
	M.sessions[dish:getID()] = session
	saveLast(w.player, session)
end

------------------------------------------------------------------ find recipe and ingredients

local function dishName(recipe)
	return getText("ContextMenu_EvolvedRecipe_" .. recipe:getUntranslatedName())
end

-- the evolved recipe called `name` that can take `baseItem` now
function M.findRecipe(player, baseItem, name, containers)
	local list = RecipeManager.getEvolvedRecipe(baseItem, player, containers, false)
	if not list then return nil end
	for i = 0, list:size() - 1 do
		local r = list:get(i)
		if r:getUntranslatedName() == name then return r end
	end
	return nil
end

local function usable(recipe, item, fullType, exclude)
	if item:getFullType() ~= fullType or exclude[item] then return false end
	if instanceof(item, "Food") then
		if item:isRotten() then return false end
		if item:isFrozen() and not recipe:isAllowFrozenItem() then return false end
		if not recipe:needToBeCooked(item) then return false end
	end
	return true
end

-- best item of `fullType` the recipe accepts for `base`: player inventory first, then the oldest
function M.findIngredient(player, recipe, base, fullType, containers, exclude)
	local list = recipe:getItemsCanBeUse(player, base, containers)
	local inv = player:getInventory()
	local best, bestInInv, bestAge
	for i = 0, list:size() - 1 do
		local item = list:get(i)
		if item ~= base and usable(recipe, item, fullType, exclude) then
			local inInv = inv:contains(item)
			local age = item:getAge() or 0
			if not best or (inInv and not bestInInv) or (inInv == bestInInv and age > bestAge) then
				best, bestInInv, bestAge = item, inInv, age
			end
		end
	end
	return best
end

-- an item of `fullType` in the inventory or those containers, whatever the recipe takes right now.
-- getItemsCanBeUse leaves spices (garlic, salt, ...) out while the base is still empty, though a
-- spice that comes later in the dish is fine: by then the base is the dish
local function present(player, recipe, fullType, containers, exclude)
	local function look(container)
		local list = container:getItemsFromFullType(fullType)
		for i = 0, list:size() - 1 do
			local item = list:get(i)
			if usable(recipe, item, fullType, exclude) and not (instanceof(item, "Food") and item:isBurnt()) then return true end
		end
		return false
	end
	if look(player:getInventory()) then return true end
	for i = 0, containers:size() - 1 do
		if look(containers:get(i)) then return true end
	end
	return false
end
M.present = present

-- all distinct ingredient types missing for a fresh dish on `base`
function M.missingFor(player, recipe, base, items, containers, exclude)
	local missing, seen = {}, {}
	local empty = not recipe:isResultItem(base)
	for _, fullType in ipairs(items) do
		if not seen[fullType] then
			seen[fullType] = true
			local found = M.findIngredient(player, recipe, base, fullType, containers, exclude)
				or (empty and present(player, recipe, fullType, containers, exclude))
			if not found then
				missing[#missing + 1] = fullType
			end
		end
	end
	return missing
end

local function names(fullTypes)
	local t = {}
	for i, ft in ipairs(fullTypes) do t[i] = getItemNameFromFullType(ft) end
	return table.concat(t, ", ")
end
M.names = names

------------------------------------------------------------------ repeat

M.task = nil

local function say(player, text, good)
	if good then HaloTextHelper.addGoodText(player, text) else HaloTextHelper.addBadText(player, text) end
	log(text)
end

local function finish(task, reason)
	if M.task ~= task then return end
	M.task = nil
	local p = task.player
	if reason then say(p, reason, false) end
	if #task.skipped > 0 then say(p, getText("IGUI_RepeatLastDish_Skipped", names(task.skipped)), false) end
	if task.made > 0 then say(p, getText("IGUI_RepeatLastDish_Done", task.made), true) end
	log("finished made=" .. task.made .. " of " .. #task.bases .. (reason and (" reason=" .. reason) or ""))
end

local function containersFor(player)
	return ISInventoryPaneContextMenu.getContainers(player) or ArrayList.new()
end

local queueStep

-- start the next dish: check every ingredient is there, bring the base into the inventory
local function startDish(task)
	local p = task.player
	task.dishIdx = task.dishIdx + 1
	local base = task.bases[task.dishIdx]
	if not base then return finish(task) end
	task.step, task.base = 0, base
	if base:getContainer() == nil then return startDish(task) end
	local containers = containersFor(p)
	task.recipeObj = M.findRecipe(p, base, task.recipe, containers)
	if not task.recipeObj then return finish(task, getText("IGUI_RepeatLastDish_NoRecipe")) end
	local missing = M.missingFor(p, task.recipeObj, base, task.items, containers, task.exclude)
	if #missing > 0 then return finish(task, getText("IGUI_RepeatLastDish_Missing", names(missing))) end
	log("dish " .. task.dishIdx .. " base in " .. tostring(base:getContainer():getType()))
	if not p:getInventory():contains(base) then
		ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, base, base:getContainer(), p:getInventory(), nil))
	end
	return queueStep(task)
end

-- queue the next ingredient of the current dish (transfer in, add, put the rest back)
queueStep = function(task)
	local p = task.player
	task.step = task.step + 1
	local fullType = task.items[task.step]
	if not fullType then
		task.made = task.made + 1
		return startDish(task)
	end
	local item = M.findIngredient(p, task.recipeObj, task.base, fullType, containersFor(p), task.exclude)
	if not item then
		task.skipped[#task.skipped + 1] = fullType
		return queueStep(task)
	end
	log("dish " .. task.dishIdx .. " step " .. task.step .. " " .. fullType .. " from " .. tostring(item:getContainer() and item:getContainer():getType()))
	local returnTo = {}
	if not p:getInventory():contains(item) then
		ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, item, item:getContainer(), p:getInventory(), nil))
		returnTo[1] = item
		if instanceof(item, "Food") then item:setChef(p:getUsername()) end
	end
	local action = ISAddItemInRecipe:new(p, task.recipeObj, task.base, item)
	action.repeatLastDishTask = task
	ISTimedActionQueue.add(action)
	ISCraftingUI.ReturnItemsToOriginalContainer(p, returnTo)
	-- if the queue empties before this add performs, it failed or was cancelled (onTick ends the task)
	task.expectAdd, task.queuedAt = true, now()
end

local function queueEmpty(player)
	local q = ISTimedActionQueue.getTimedActionQueue(player)
	return not q or not q.queue or #q.queue == 0
end

-- our add showed up: continue on the dish item (bowl -> salad after the first add), but only once
-- the queue is empty: the leftover of the last ingredient may still be on its way back to the
-- fridge, and choosing the next ingredient before that picks items that are about to move
local function stepDone(w, dish)
	local task = w.task
	if M.task ~= task then return end
	if not dish then return finish(task, getText("IGUI_RepeatLastDish_Stopped")) end
	task.base = dish
	task.exclude[dish] = true
	task.waitQueue = true
end

-- the task between steps: go on when the queue is empty; stop when our add never ran
local function tickTask(task)
	if task.waitQueue then
		if queueEmpty(task.player) then
			task.waitQueue = false
			return queueStep(task)
		end
	elseif task.expectAdd and queueEmpty(task.player) and now() - task.queuedAt > 1000 then
		log("add never ran (failed or cancelled)")
		return finish(task, getText("IGUI_RepeatLastDish_Stopped"))
	end
end

function M.onTick()
	local task = M.task
	if task then
		local ok, err = pcall(tickTask, task)
		if not ok then log("step error", err); pcall(finish, task, getText("IGUI_RepeatLastDish_Stopped")) end
	end
	if #M.watches == 0 then return end
	local keep = {}
	for _, w in ipairs(M.watches) do
		local ok, done, dish = pcall(settled, w)
		if not ok then
			log("watch error", done)
			if w.task then pcall(finish, w.task, getText("IGUI_RepeatLastDish_Stopped")) end
		elseif not done then
			keep[#keep + 1] = w
		elseif w.task then
			local ok2, err = pcall(stepDone, w, dish)
			if not ok2 then log("step error", err); pcall(finish, w.task, getText("IGUI_RepeatLastDish_Stopped")) end
		else
			local ok2, err = pcall(recordDone, w, dish)
			if not ok2 then log("record error", err) end
		end
	end
	M.watches = keep
end

function M.start(player, bases)
	local last = M.getLast(player)
	if not last or #bases == 0 then return end
	M.task = nil -- an earlier run that was cancelled just ends
	local exclude = {}
	for _, b in ipairs(bases) do exclude[b] = true end
	local task = {
		player = player, recipe = last.recipe, items = last.items, bases = bases,
		dishIdx = 0, made = 0, skipped = {}, exclude = exclude,
	}
	M.task = task
	log("start recipe=" .. last.recipe .. " bases=" .. #bases .. " items=" .. table.concat(last.items, ","))
	local ok, err = pcall(startDish, task)
	if not ok then log("start error", err); finish(task, getText("IGUI_RepeatLastDish_Stopped")) end
end

------------------------------------------------------------------ hook

-- state before the add, taken on the client in start: in multiplayer the server's change (bowl
-- replaced by the salad, new hunger and uses) usually reaches the client before perform, so a
-- snapshot taken in perform would already contain it and the add would never be seen
local function watchFor(action)
	local base, used, recipe = action.baseItem, action.usedItem, action.recipe
	local container = action.character:getInventory()
	local isResult = recipe:isResultItem(base)
	return {
		player = action.character, task = action.repeatLastDishTask,
		recipe = recipe, recipeName = recipe:getUntranslatedName(), -- not getName(): translated, changes with the language
		base = base, baseId = base:getID(), baseType = base:getFullType(), isResult = isResult,
		dishSig = dishSig(base),
		used = used, usedType = used:getFullType(), usedSig = usedSig(used),
		container = container, preIds = isResult and {} or resultIds(recipe, container),
		at = now(),
	}
end

-- the true original is kept in M.originalPerform, so running this file again (Lua reload) replaces
-- our wrapper instead of wrapping it twice
function M.install()
	if not ISAddItemInRecipe or not ISAddItemInRecipe.perform or not ISAddItemInRecipe.start then
		log("ISAddItemInRecipe:perform/start not found, not installed")
		return false
	end
	local originalStart = M.originalStart or ISAddItemInRecipe.start
	M.originalStart = originalStart
	ISAddItemInRecipe.start = function(self, ...)
		local r = originalStart(self, ...) -- in multiplayer this re-reads baseItem from the inventory
		local ok, w = pcall(watchFor, self)
		if not ok then log("watch setup error", w); w = nil end
		self.repeatLastDishWatch = w
		return r
	end
	local original = M.originalPerform or ISAddItemInRecipe.perform
	M.originalPerform = original
	ISAddItemInRecipe.perform = function(self, ...)
		local w = self.repeatLastDishWatch
		self.repeatLastDishWatch = nil
		if w then w.at = now() end
		if self.repeatLastDishTask then self.repeatLastDishTask.expectAdd = false end
		local r = original(self, ...)
		if w then M.watches[#M.watches + 1] = w end
		return r
	end
	M.installed = true
	log("installed")
	return true
end

------------------------------------------------------------------ context menu

local function collectItems(items)
	local out, seen = {}, {}
	for _, v in ipairs(items) do
		if type(v) == "table" and v.items then
			-- a stack lists its first item twice; `seen` drops the copy
			for i = 1, #v.items do
				local it = v.items[i]
				if not seen[it] then seen[it] = true; out[#out + 1] = it end
			end
		elseif instanceof(v, "InventoryItem") and not seen[v] then
			seen[v] = true; out[#out + 1] = v
		end
	end
	return out
end

function M.onFillMenu(playerNum, context, items)
	local player = getSpecificPlayer(playerNum)
	local last = M.getLast(player)
	if not last then return end
	local bases = {}
	for _, it in ipairs(collectItems(items)) do
		if it:getFullType() == last.base then bases[#bases + 1] = it end
	end
	if #bases == 0 then return end
	local containers = containersFor(player)
	local recipe = M.findRecipe(player, bases[1], last.recipe, containers)
	if not recipe then return end
	local text = getText("IGUI_RepeatLastDish_Option", dishName(recipe))
	if #bases > 1 then text = getText("IGUI_RepeatLastDish_OptionCount", dishName(recipe), #bases) end
	-- first entry of the vanilla "Make Salad" submenu when there is one (vanilla leaves it out when
	-- nothing can go in right now), else at the end of the menu
	local option
	local parent = context.getOptionFromName and context:getOptionFromName(getText("ContextMenu_Create_From_Ingredient", dishName(recipe)))
	local sub = parent and parent.subOption and context.getSubMenu and context:getSubMenu(parent.subOption)
	if sub and sub.addOptionOnTop then
		option = sub:addOptionOnTop(text, player, M.start, bases)
	else
		option = context:addOption(text, player, M.start, bases)
	end
	local tooltip = ISInventoryPaneContextMenu.addToolTip()
	tooltip.description = getText("IGUI_RepeatLastDish_Ingredients", names(last.items))
	local missing = M.missingFor(player, recipe, bases[1], last.items, containers, {})
	if #missing > 0 then
		option.notAvailable = true
		tooltip.description = tooltip.description .. " <BR> <RGB:1,0.3,0.3> " .. getText("IGUI_RepeatLastDish_Missing", names(missing))
	end
	option.toolTip = tooltip
end

Events.OnFillInventoryObjectContextMenu.Add(M.onFillMenu)
Events.OnTick.Add(M.onTick)
M.install()
