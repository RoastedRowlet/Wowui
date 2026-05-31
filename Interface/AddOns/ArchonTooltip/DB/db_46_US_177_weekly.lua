local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Druid-Guardian','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abelas:BAAALgADCgYJGAAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgMJAwAAAA==.Adêrna:BAABLgAECn8yAAIBAAkJ+B4hCQAKAwABAAkJ+B4hCQAKAwAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAABLgAFFH8LAAICAAMJJAfnlQDCAAACAAMJJAfnlQDCAAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECggJDAAAAA==.Alanus:BAABLgAECn8pAAIDAAkJMhBVVgDCAQADAAkJMhBVVgDCAQAAAA==.Alarion:BAAALgAECgQJBwAAAA==.Alavia:BAABLgAECn8/AAIEAAkJfxixFgAkAgAEAAkJfxixFgAkAgAAAA==.Alinäs:BAABLgAECn8hAAIDAAkJHQ/FWwCyAQADAAkJHQ/FWwCyAQAAAA==.Aliën:BAAALgADCgEJAQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAABLgAECn8XAAMGAAkJtBElGQB8AQAGAAkJNRAlGQB8AQAHAAIJSA4fKABZAAABLgAFFAMJBQAIAO4UAA==.Alydrus:BAABLgAECn8zAAIDAAgJDBJWZgCXAQADAAgJDBJWZgCXAQAAAA==.Alíen:BAAALgADCgQJBAAAAA==.',
Am='Amnesian:BAAALgAECgkJAQAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIJAAYJ5geytAAbAQAJAAYJ5geytAAbAQAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Angzhixing:BAAALgADCgIJAgAAAA==.Ankles:BAAALgADCgcJBwABLgAFFAQJDgAKAB8RAA==.Annahe:BAABLgAECn8WAAILAAkJ/xrDEAArAgALAAkJ/xrDEAArAgAAAA==.Annale:BAAALgAECgQJBQABLgAECgkJFgALAP8aAA==.Annatara:BAAALgAECgMJAwAAAA==.Anran:BAAALgADCgEJAQAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgAECgMJAwAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Arataeus:BAAALgAECgQJCgAAAA==.Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn80AAICAAgJmiCwLQA1AgACAAgJmiCwLQA1AgAAAA==.Artemistha:BAAALgADCgkJFgAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgEJAQAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgkJMwADAMIeAA==.Balduun:BAAALgAECgEJAgAAAA==.Barelycastin:BAAALgAECgEJAQAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAABLgAECn8gAAINAAgJVSB9FACYAgANAAgJVSB9FACYAgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Bebebluz:BAAALgADCgkJCQAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgUJCwAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bison:BAAALgAECgMJAwABLgADCgEJAQAMAAAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn80AAMOAAkJ+x9bAgDvAgAOAAkJ+x9bAgDvAgAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgAECgEJAgAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgUJBQAAAA==.',
Bo='Bogeyman:BAABLgAECn81AAIPAAkJrSDGAgDlAgAPAAkJrSDGAgDlAgAAAA==.Boondoks:BAABLgAECn8gAAIKAAcJTh3IHAAGAgAKAAcJTh3IHAAGAgABLgAECggJOwABADAgAA==.Borda:BAAALgAECggJCAAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgADCgkJCQAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caidi:BAAALgADCgMJAwAAAA==.Caledur:BAAALgAECgYJDAAAAA==.Caratdeullie:BAAALgADCgEJAQAAAA==.Careblair:BAAALgADCgkJCQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIQAAcJ/gnZNQA9AQAQAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAIRAAMJtAKBZACdAAARAAMJtAKBZACdAAAAAA==.Chloe:BAABLgAECn8XAAISAAkJ9AF6ygAtAAASAAkJ9AF6ygAtAAAAAA==.Chrno:BAABLgAECn8YAAISAAgJ5xFUMQDIAQASAAgJ5xFUMQDIAQAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAQJCQADAKAHAA==.',
Ci='Cirilá:BAAALgAECgMJAQAAAA==.',
Cl='Clutcha:BAABLgAECn8cAAITAAYJKh1QJgBHAQATAAYJKh1QJgBHAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAATACodAA==.Clutchplate:BAABLgAECn8jAAMUAAgJKxTcEwCZAQAUAAgJKxTcEwCZAQAVAAEJWgbScwAlAAAAAA==.Clûtch:BAACLgAFFH8RAAICAAQJph+BRQBGAQACAAQJph+BRQBGAQAuAAQKfyIAAgIACQliH+42AFsCAAIACQliH+42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCgAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn81AAIWAAkJLyFgAwBMAwAWAAkJLyFgAwBMAwAAAA==.',
Cr='Crickie:BAAALgAECgYJDwAAAA==.Crovaxis:BAABLgAECn8oAAMXAAkJNB8YBwAEAgAXAAcJ8SIYBwAEAgANAAIJ/BOlyQCNAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAABLgAECn8fAAIYAAkJGxTIFAD3AQAYAAkJGxTIFAD3AQAAAA==.Dahunt:BAAALgAECgcJAQAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgAECgIJAgAAAA==.Darktalyn:BAABLgAECn8vAAMWAAkJAhTTFwD6AQAWAAgJFhbTFwD6AQAQAAgJZwwrOAARAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn82AAIGAAgJmBh/EADoAQAGAAgJmBh/EADoAQAAAA==.Deathhawkzz:BAACLgAFFH8LAAMZAAMJSgrUDQCsAAAaAAMJSgo6bgDOAAAZAAMJLgPUDQCsAAAuAAQKfxoAAxkACAmcFOYLAAQCABkABwn6FeYLAAQCABoABAntEVidAPkAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn8qAAMCAAgJsApodwBfAQACAAgJsApodwBfAQAHAAIJlQHeNAAnAAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Delimira:BAAALgAECgQJBwAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgYJCwAAAA==.Demonpapi:BAAALgAFFAMJAwAAAA==.Demoryx:BAEALgAECgQJBAABLgAECgkJJAAbAPwbAA==.Denjack:BAAALgAECgYJDwAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dionan:BAABLgAECn8qAAIJAAkJZRINVwCtAQAJAAkJZRINVwCtAQAAAA==.Dirtysouth:BAAALgAECgcJCwABLgAFFAUJFgANAHwgAA==.',
Do='Docs:BAABLgAECn8vAAIKAAgJbhntFABPAgAKAAgJbhntFABPAgAAAA==.Doks:BAABLgAECn87AAIBAAgJMCDfEQCnAgABAAgJMCDfEQCnAgAAAA==.Dontpanic:BAABLgAECn8iAAIcAAcJTRzFGAAsAgAcAAcJTRzFGAAsAgABLgAFFAQJDgAKAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAMAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragana:BAAALgADCgcJBgAAAA==.Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgYJCwAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.Drunkenhealz:BAAALgAECgcJBQAAAA==.',
Du='Dunir:BAAALgAECgQJCAAAAA==.',
Ea='Ealara:BAABLgAECn8eAAINAAgJ7gk2ZwBdAQANAAgJ7gk2ZwBdAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAJABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgAECgMJAwABLgAFFAEJAQAMAAAAAA==.',
Em='Emberaegis:BAAALgAECgYJDgABLgAFFAEJAQAMAAAAAA==.Emeraldz:BAABLgAECn8mAAILAAgJcRygEQAhAgALAAgJcRygEQAhAgAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAKAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwABLgAECggJFQAcAEwTAA==.',
Es='Espe:BAABLgAECn8cAAIYAAkJyhP7GADNAQAYAAkJyhP7GADNAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgQJCwAAAA==.Faynor:BAABLgAECn8zAAIYAAkJdxh6EAAmAgAYAAkJdxh6EAAmAgAAAA==.Faynór:BAAALgADCgMJAwABLgAECgkJMwAYAHcYAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgAECgEJAQAAAA==.Firêfly:BAAALgAECgYJCgAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgYJCQAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn8qAAILAAcJ6AlvOwD6AAALAAcJ6AlvOwD6AAAAAA==.',
Fo='Foxyblue:BAABLgAECn8UAAIWAAYJTBV3NABtAQAWAAYJTBV3NABtAQAAAA==.',
Fr='Fraggle:BAACLgAFFH8OAAMKAAQJHxGeIwDtAAAKAAQJHxGeIwDtAAAJAAMJUwlkYwDHAAAuAAQKfycAAwoACAl+IBsLAMcCAAoACAl+IBsLAMcCAAkABAmtED/EAOUAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgYJDQAAAA==.Frostbité:BAABLgAECn8yAAIPAAkJph6lAwC+AgAPAAkJph6lAwC+AgAAAA==.Fruit:BAAALgAECgYJEgAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAFFAMJBQAIAO4UAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.',
['Fà']='Fàynor:BAAALgAECggJEgABLgAECgkJMwAYAHcYAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgABLgADCgIJAgAMAAAAAA==.',
Ga='Gakkle:BAABLgAECn8YAAIEAAgJ+hZ6HgDnAQAEAAgJ+hZ6HgDnAQAAAA==.Galadralvia:BAABLgAECn8UAAIUAAgJ2Q2lHgAkAQAUAAgJ2Q2lHgAkAQAAAA==.Gali:BAAALgAECgUJDAAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn82AAICAAkJzx9vFgCtAgACAAkJzx9vFgCtAgAAAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJNAACAJogAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgYJDQAAAA==.Gloomstalkin:BAABLgAECn8/AAIdAAkJNhfDDABMAgAdAAkJNhfDDABMAgAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgUJCAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8mAAIeAAcJVA1VDQA/AQAeAAcJVA1VDQA/AQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Grimmli:BAAALgADCgEJAQAAAA==.Grizelda:BAAALgADCgQJBAAAAA==.Grizzledpaw:BAAALgAECgQJCgAAAA==.Gromcresh:BAAALgAECgEJAQAAAA==.Gryffs:BAABLgAECn86AAMUAAkJ3CBpBADNAgAUAAkJ3CBpBADNAgAVAAEJ1ArLbQAsAAAAAA==.',
Gu='Gum:BAAALgAECgcJBwABLgAECgkJNQAPAK0gAA==.Gutts:BAABLgAECn8nAAQUAAkJDSKeBADGAgAUAAkJDSKeBADGAgAVAAcJ3BJVJwAaAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgQJCQAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAcJHQARAFwjAA==.Harald:BAABLgAECn8bAAMCAAgJDw6jlwAkAQACAAcJkAqjlwAkAQAGAAEJDCPQQwBkAAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgIJAQAAAA==.',
He='Heliõs:BAAALgAECgEJAQAAAA==.Hesmydaddy:BAABLgAECn86AAIWAAkJhgvTJACHAQAWAAkJhgvTJACHAQAAAA==.',
Ho='Honestie:BAAALgAECgQJCgAAAA==.Hongling:BAAALgADCgYJBgABLgAFFAMJBQAIAO4UAA==.Honêy:BAEALgAFFAIJAQABLgAECgkJJAAbAPwbAA==.Hotdogstand:BAACLgAFFH8VAAITAAYJZCO1BwDcAQATAAYJZCO1BwDcAQAuAAQKfzEABBMACQlwJVkCACkDABMACQlwJVkCACkDAB4ABAmEIYELAHMBAB8AAQkrIv4aAFkAAAAA.',
Hu='Huzzaah:BAAALgAECgcJEwABLgAFFAQJDgAKAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAINAAgJ9Bg2LAADAgANAAgJ9Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIXAAcJbQOMHAC1AAAXAAcJbQOMHAC1AAAAAA==.Illida:BAAALgAECgMJCQAAAA==.Illidad:BAAALgAECgQJBAAAAA==.',
Im='Imhappy:BAAALgAECgUJCgABLgAFFAcJHQARAFwjAA==.Imherdaddy:BAAALgADCgYJCAABLgAECgkJPwAdADYXAA==.',
In='Indracus:BAAALgAECgQJCQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ja='Jacorict:BAABLgAECn8UAAIJAAYJJwvJwQDoAAAJAAYJJwvJwQDoAAAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn8zAAIDAAkJ1RzEGgCkAgADAAkJ1RzEGgCkAgAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECggJEAAAAA==.Jeuno:BAAALgAECgEJAQABLgAFFAMJBQAIAO4UAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJPgAFABwcAA==.Josephedd:BAABLgAECn8+AAIFAAgJHBz/EAA+AgAFAAgJHBz/EAA+AgAAAA==.',
Ju='Judgment:BAAALgAECgEJAQAAAA==.Jukk:BAABLgAECn8hAAIDAAgJhAdBmgAqAQADAAgJhAdBmgAqAQABLgAECgkJEgAMAAAAAA==.Junazeena:BAABLgAECn8lAAMbAAgJPgdYRQACAQAbAAgJPgdYRQACAQABAAIJCgKhuwA4AAAAAA==.',
Jy='Jygglypuff:BAAALgAECgUJBQAAAA==.',
Ka='Kaji:BAABLgAECn8hAAIcAAYJbBEpPwA9AQAcAAYJbBEpPwA9AQAAAA==.Kalistus:BAAALgAECgEJAQAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8bAAIDAAkJ3QNz+gAGAQADAAkJ3QNz+gAGAQAAAA==.Kayfay:BAAALgAECgMJAwAAAA==.Kazz:BAAALgAECgQJBAAAAA==.',
Ke='Keishilda:BAABLgAECn8WAAMgAAUJXQnzSgCpAAAgAAQJOwvzSgCpAAAQAAUJGwNSZABdAAAAAA==.Keladria:BAAALgAECgQJBwAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn83AAMSAAkJhBe6FwB1AgASAAkJhBe6FwB1AgAFAAUJcRFOSQDKAAAAAA==.Kerea:BAABLgAECn81AAISAAkJLgjTTwA8AQASAAkJLgjTTwA8AQAAAA==.Kerob:BAAALgAECgEJAQAAAA==.',
Ki='Kicken:BAABLgAECn8wAAQaAAgJ9RuqLgARAgAaAAcJlRqqLgARAgAZAAMJihkmPwC4AAAhAAEJBhGiMgA9AAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgQJBAAAAA==.',
Kn='Knome:BAABLgAECn8zAAIDAAkJwh5wGACxAgADAAkJwh5wGACxAgAAAA==.',
Ko='Koana:BAAALgAECgkJCwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn82AAIRAAkJDBIMNQDbAQARAAkJDBIMNQDbAQAAAA==.Kothara:BAABLgAECn8pAAINAAkJZBLFMwD3AQANAAkJZBLFMwD3AQAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8WAAINAAUJfCBmGQBzAQANAAUJfCBmGQBzAQAuAAQKfx4AAw0ACAnfIZQhADwCAA0ACAnfIZQhADwCAB0AAgkaEApVAEEAAAAA.Krystine:BAAALgAECgYJEgAAAA==.',
Ks='Kserasera:BAAALgAFFAEJAQAAAA==.',
Ku='Kuball:BAAALgAECgYJCQABLgAECgkJJwAUAA0iAA==.Kukuruku:BAAALgAECgYJDQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8oAAIBAAkJrhWwJAAYAgABAAkJrhWwJAAYAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwiAygDYAAACAAYJCwiAygDYAAAAAA==.Lanskies:BAABLgAECn8ZAAICAAkJPRU9LAA7AgACAAkJPRU9LAA7AgAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJQgABANEXAA==.Lebronjames:BAAALgAFFAMJAwAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAAALgAECgYJBgAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxevLQCHAQAEAAgJMxevLQCHAQAAAA==.Librarte:BAABLgAECn8wAAIJAAkJOwxlagCAAQAJAAkJOwxlagCAAQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lija:BAAALgAECgYJBgABLgAECgkJEgAMAAAAAA==.Lillytrae:BAAALgAECgMJBQAAAA==.Lilmeds:BAAALgAECggJEgABLgAECgkJQgABANEXAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAMAAAAAA==.Litty:BAABLgAECn8oAAIDAAcJASXUJgBpAgADAAcJASXUJgBpAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQhAAQJiBv3AwA1AQAhAAQJiBv3AwA1AQAaAAIJShYXMwCtAAAZAAIJogaEDgCXAAAuAAQKfyoABCEACAmIH6oCAJACACEACAk+H6oCAJACABoACAktGRZCAAYCABkAAgkLHIJGAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Lox:BAABLgAECn84AAIZAAkJSBdQBAAkAgAZAAkJSBdQBAAkAgAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8gAAQJAAkJ+Rw0NwAMAgAJAAgJ3x00NwAMAgAKAAQJzRVfTwDjAAAPAAIJoBxwLAChAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.Lysaviel:BAAALgAECgEJAgAAAA==.',
['Lí']='Lítterbox:BAAALgAECgMJBQAAAA==.',
Ma='Magedzen:BAAALgAECgMJAwAAAA==.Magicguy:BAABLgAECn8YAAIDAAgJ8wyZeQBqAQADAAgJ8wyZeQBqAQAAAA==.Mahariel:BAABLgAECn8ZAAINAAkJ9QuhRwCyAQANAAkJ9QuhRwCyAQAAAA==.Mahdy:BAABLgAECn9FAAIJAAkJGR04HgB5AgAJAAkJGR04HgB5AgAAAA==.Mahoe:BAAALgAECgIJAgAAAA==.Maivel:BAAALgAECgEJAQAAAA==.Manandaar:BAAALgAECgIJAgAAAA==.Mandret:BAAALgAECgMJBAAAAA==.Manicppanic:BAABLgAECn8gAAITAAgJxxW3GQCyAQATAAgJxxW3GQCyAQABLgAFFAQJDgAKAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn8yAAIFAAkJURAUHQDGAQAFAAkJURAUHQDGAQAAAA==.Martinriggz:BAAALgAECgMJBgAAAA==.',
Mc='Mchammer:BAAALgAECgEJAQAAAA==.',
Me='Meatyloaf:BAABLgAECn8VAAIHAAgJqgP1GwC8AAAHAAgJqgP1GwC8AAAAAA==.Melkedrik:BAABLgAECn8VAAIiAAgJpA5GHwBbAQAiAAgJpA5GHwBbAQAAAA==.Melleren:BAAALgAECgYJCAAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn8wAAIWAAgJcg7cJwBxAQAWAAgJcg7cJwBxAQAAAA==.Mistdancer:BAAALgADCgYJBgABLgAFFAIJBgAHAI0GAA==.Mitsurugi:BAAALgADCgQJAwABLgAFFAIJBgAHAI0GAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAGAKYdAA==.',
Mo='Mochisama:BAAALgAECgYJCAAAAA==.Mojam:BAAALgAECgQJCQAAAA==.Monk:BAAALgAECgEJAQAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAAALgAECgkJEgAAAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgAECgEJAQAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Mystryl:BAAALgADCgkJEAAAAA==.Mythantherox:BAAALgAFFAIJAgABLgAFFAUJEAAjAJIaAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAMAAAAAA==.Negative:BAAALgAECgQJCAAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn8tAAIeAAgJ/BZ5BgDuAQAeAAgJ/BZ5BgDuAQAAAA==.Netherstörm:BAAALgAECgMJAwAAAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAACLgAFFH8FAAIIAAMJ7hTONQDMAAAIAAMJ7hTONQDMAAAuAAQKfysABAgACQltH88JAKICAAgACQlnH88JAKICACQABgleDBY0AM0AACMABAn3G3MXAIkAAAAA.Niënor:BAABLgAECn8VAAIcAAgJTBNfJgDFAQAcAAgJTBNfJgDFAQAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nyxstonia:BAACLgAFFH8QAAIUAAQJtxZwEQAEAQAUAAQJtxZwEQAEAQAuAAQKfzUAAhQACQkrG9IKACwCABQACQkrG9IKACwCAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Orhan:BAAALgAECgQJBAABLgAECgkJMwAYAHcYAA==.Ornac:BAAALgADCgcJDQAAAA==.',
Ot='Otkspring:BAACLgAFFH8HAAMEAAMJHwo0MgC/AAAEAAMJZgg0MgC/AAAVAAEJPweuNQBBAAAuAAQKfxkAAgQABwmAFywoAKYBAAQABwmAFywoAKYBAAAA.Otto:BAABLgAECn8pAAIJAAkJ2hE5UwC3AQAJAAkJ2hE5UwC3AQAAAA==.Ottomagus:BAAALgAECgcJBwAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIbAAYJ7wwFUwDRAAAbAAYJ7wwFUwDRAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgYJDQAMAAAAAA==.Pandapunk:BAAALgAECggJDgAAAA==.Pantoponrose:BAAALgAECgYJCwAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8kAAIQAAkJYxGkHgCxAQAQAAkJYxGkHgCxAQAAAA==.',
Ph='Phukimded:BAABLgAECn8XAAIGAAgJqAygIQAsAQAGAAgJqAygIQAsAQABLgAFFAEJAQAMAAAAAA==.',
Pi='Pitnick:BAAALgAECgIJAgAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMJAAkJlAu6dgBmAQAJAAkJlAu6dgBmAQAKAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAhAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.',
Ra='Raemie:BAAALgAECgQJBwAAAA==.Ragequit:BAABLgAECn8WAAIUAAgJwhccEgCyAQAUAAgJwhccEgCyAQABLgAFFAEJAQAMAAAAAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenrest:BAEBLgAECn8vAAIQAAgJqx5/EAA6AgAQAAgJqx5/EAA6AgAAAA==.',
Re='Reaverhiem:BAABLgAECn8XAAQUAAYJYx5PEwCgAQAUAAYJYx5PEwCgAQAEAAQJfxcqZQAeAQAVAAEJ5RvtWwBOAAAAAA==.Reiko:BAAALgADCgkJIQABLgAECggJMAAWAHIOAA==.Remuz:BAAALgAECgUJCwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.Renriss:BAAALgAECgEJAQABLgAECggJNgAGAJgYAA==.Rey:BAAALgAECgEJAQABLgAECgYJBQAMAAAAAA==.',
Rh='Rhe:BAAALgAECgEJAQABLgAECgYJBQAMAAAAAA==.',
Ri='Rilz:BAABLgAECn8qAAICAAkJ3SALGQCdAgACAAkJ3SALGQCdAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgQJCgAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAaABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAaABcUAA==.Roidlock:BAABLgAECn8rAAIaAAgJFxRCTgCkAQAaAAgJFxRCTgCkAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAaABcUAA==.Rongyi:BAAALgADCgIJAgAAAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rottn:BAAALgAFFAEJAQAAAA==.',
Ru='Runerion:BAAALgAECgEJBAAAAA==.',
Ry='Ry:BAAALgAECgYJBQAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAglfmwAoAQADAAgJAglfmwAoAQAAAA==.',
Sa='Safmen:BAABLgAECn8bAAQUAAYJwQftMACjAAAUAAYJjAftMACjAAAVAAMJMgU4WgBSAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgQJCAAAAA==.Saraid:BAABLgAECn8tAAQSAAkJ9RjQFACPAgASAAkJ9RjQFACPAgAFAAMJZxAUYQCdAAAlAAIJvQUXYQAwAAAAAA==.Saravase:BAAALgAECgYJEgAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowi:BAAALgAECgQJBQAAAA==.Shadownights:BAABLgAECn84AAIQAAkJNReEEAA6AgAQAAkJNReEEAA6AgAAAA==.Shadowpope:BAAALgAECgkJBgAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shazi:BAEBLgAECn8kAAMbAAkJ/BvSDwBhAgAbAAkJ/BvSDwBhAgAmAAEJ8Ao1LAA1AAABLgAECgkJJAAbAPwbAA==.Shiki:BAAALgADCgkJEwABLgAECggJMAAWAHIOAA==.Shimnar:BAAALgAECggJEwABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAAALgAECgYJEwAAAA==.Shiritá:BAAALgAECgMJAgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAgAAAA==.Six:BAAALgAECgUJCwAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgYJCgAAAA==.Snöw:BAABLgAECn8nAAIDAAkJGhUDOQAeAgADAAkJGhUDOQAeAgAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Sojudevourer:BAAALgAECgEJAQAAAA==.Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8nAAQIAAkJ6Ax9GgD2AQAIAAkJ6Ax9GgD2AQAkAAgJDxIYEQClAQAjAAIJYw5/HwBDAAAAAA==.',
Sr='Sron:BAABLgAECn8oAAINAAgJKB9KNAD1AQANAAgJKB9KNAD1AQAAAA==.',
St='Stariah:BAABLgAECn8eAAIDAAgJdgontQB1AQADAAgJdgontQB1AQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Swooze:BAACLgAFFH8GAAIDAAMJzQqudgDVAAADAAMJzQqudgDVAAAuAAQKfzsAAgMACQndHcsXALUCAAMACQndHcsXALUCAAAA.',
Sy='Sylrythriana:BAAALgAECgcJEQAAAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAFFAMJBQAIAO4UAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tahoe:BAAALgADCgYJBgABLgAFFAQJFwARAK8ZAA==.Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgYJDAAAAA==.Tanzri:BAAALgAECgMJAwAAAA==.Tarlyn:BAACLgAFFH8JAAIKAAMJCg1bLACyAAAKAAMJCg1bLACyAAAuAAQKfzMABAoACQkgFtEaABcCAAoACQkgFtEaABcCAAkABglcGrd+AFYBAA8AAQkAANI/AD4AAAAA.Tatslight:BAABLgAECn8pAAIPAAYJbB7iEgCBAQAPAAYJbB7iEgCBAQABLgAECgYJKQAPAGweAA==.Tatsrage:BAAALgAECgEJAQABLgAECgYJKQAPAGweAA==.Tazaral:BAAALgADCgEJAQABLgAECgkJCwAMAAAAAA==.',
Te='Ted:BAAALgAFFAEJAQABLgAFFAQJDgAKAB8RAA==.Temuadêrna:BAAALgAECgQJBAAAAA==.Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thalasso:BAAALgADCgEJAQAAAA==.Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAMAAAAAQ==.Timthepally:BAAALgAECggJDAABLgAECgEJAQAMAAAAAQ==.Tinytex:BAABLgAECn8mAAIYAAkJyw63IACQAQAYAAkJyw63IACQAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Toxicbanana:BAAALgAECgYJEAAAAA==.',
Tr='Tradarynn:BAABLgAECn8fAAIJAAkJ7hu/GgCMAgAJAAkJ7hu/GgCMAgAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAAALgAECgYJEgAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.',
Tu='Tulkar:BAAALgAECgIJAgAAAA==.Turambar:BAAALgADCgEJAQAAAA==.',
Ty='Tyriir:BAAALgADCgMJAwAAAA==.',
Um='Umbrax:BAAALgAECgQJBQAAAA==.',
Un='Unholymochi:BAABLgAECn8jAAICAAkJHiDmUQC7AQACAAkJHiDmUQC7AQAAAA==.',
Va='Valaynia:BAAALgAECgcJCQAAAA==.Valhalia:BAABLgAECn8UAAMaAAgJ6RcsZwBkAQAaAAYJKBgsZwBkAQAZAAMJbg6pQgCqAAAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn8lAAMiAAgJNxpPEQD2AQAiAAgJNxpPEQD2AQAnAAIJoBdvIAB7AAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQaAAkJNhThLwBNAgAaAAkJzRPhLwBNAgAZAAQJaxSaMwDpAAAhAAIJBhXMJgBWAAAAAA==.',
Vo='Vorumbrae:BAAALgAECgUJBwAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8kAAIEAAkJghfQGwD7AQAEAAkJghfQGwD7AQAAAA==.Wali:BAABLgAECn8gAAMaAAgJMRPmUwCUAQAaAAgJMRPmUwCUAQAZAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.',
We='Wenson:BAAALgAECgcJCQAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8OAAMdAAQJBBFGEwAmAQAdAAQJeg9GEwAmAQANAAMJRxB4VADVAAAuAAQKfyQABB0ABwkcIh4HAIgCAB0ABwm5IR4HAIgCAA0AAQkJG/36AEEAABcAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wy='Wyleriya:BAABLgAECn83AAIaAAkJgglFYQByAQAaAAkJgglFYQByAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgUJCAAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Xw='Xweakling:BAAALgADCgYJCAABLgAFFAQJCAAEAJ4aAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAAALgAECgYJDQAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAACLgAFFH8IAAICAAMJzhxecAD+AAACAAMJzhxecAD+AAAuAAQKfzEAAgIACQlwI58FAEIDAAIACQlwI58FAEIDAAAA.Yoovee:BAAALgADCgEJAQAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8OAAIiAAQJex5vBwBgAQAiAAQJex5vBwBgAQAuAAQKfy0AAiIACQnwIgwDABIDACIACQnwIgwDABIDAAAA.Yumii:BAABLgAECn8hAAMWAAkJPSWVAQCUAwAWAAkJECWVAQCUAwAgAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJEwAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgQJDAAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn8dAAIaAAgJtAsqaABiAQAaAAgJtAsqaABiAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zu='Zuggasaurus:BAAALgAECgkJEgAAAA==.Zugglite:BAABLgAECn8oAAQKAAgJMCEyFwBYAgAKAAgJMCEyFwBYAgAPAAQJ2xoAHAAdAQAJAAEJdgnLhwEqAAABLgAECgkJEgAMAAAAAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8QrLngAiAQADAAgJ8QrLngAiAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8oAAICAAkJIQ4EVAC0AQACAAkJIQ4EVAC0AQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æi']='Æix:BAEALgAECgEJAQABLgAFFAYJFAADACIPAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAYJFAADACIPAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
['Øm']='Ømnium:BAABLgAECn8zAAIJAAcJaApbqQANAQAJAAcJaApbqQANAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
