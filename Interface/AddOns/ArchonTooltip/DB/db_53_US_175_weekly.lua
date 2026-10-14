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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Balance','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Rogue-Assassination','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Shaman-Elemental','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DemonHunter-Vengeance','Priest-Holy','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Shaman-Restoration','Druid-Restoration','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Monk-Mistweaver','Warrior-Protection','Priest-Shadow','Paladin-Protection',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgYIDwAAAA==.Aduhgall:BAAANQADCgcIDQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECn8tAAMBAAgKViNXEwDvAgABAAgK8CJXEwDvAgACAAgKDiFoGwDmAgAAAA==.Airbubble:BAAANQAECgEIAQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECn8zAAIDAAgKMRuEKgCBAgADAAgKMRuEKgCBAgAAAA==.Alex:BAABNQAECn8pAAIEAAkKRRbRGACSAgAEAAkKRRbRGACSAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECggIGQAFAE8VAA==.Allypally:BAABNQAECn8bAAIGAAgKywsQvwCYAQAGAAgKywsQvwCYAQAAAA==.Althorian:BAAANQAECgQIBQAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.Amway:BAAANQAECgQIDwAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Ardur:BAAANQAECgEIAQAAAA==.Aremis:BAAANQAECgQICQAAAA==.Arkhitype:BAABNQAECn8cAAIHAAgKsBdjJABhAgAHAAgKsBdjJABhAgAAAA==.Arteras:BAAANQAECgEIAwAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAABNQAECn8WAAMGAAkKkhRJewAwAgAGAAgKmRVJewAwAgAIAAUKSw4BtgANAQAAAA==.Asur:BAABNQAECn8dAAIGAAcKrwzgxgCIAQAGAAcKrwzgxgCIAQAAAA==.',
Au='Auracorusca:BAABNQAECn8XAAMIAAgKpx5RKQDAAgAIAAgKpx5RKQDAAgAGAAEK2gUcqAEwAAAAAA==.Aurafarmer:BAAANQAECgQIBAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgYIDwAAAA==.Aystarael:BAAANQAECggICAAAAA==.',
Ba='Bajr:BAABNQAECn8XAAIJAAgKiwqgkgDgAQAJAAgKiwqgkgDgAQAAAA==.Bakura:BAABNQAECn8jAAIKAAgKbxrjBACCAgAKAAgKbxrjBACCAgAAAA==.Banker:BAABNQAECn8jAAIEAAgKOw9ALQDUAQAEAAgKOw9ALQDUAQAAAA==.Baroo:BAAANQADCgcIKgAAAA==.Barudd:BAAANQAECgEIAQAAAA==.',
Be='Berko:BAABNQAECn86AAILAAgKlSDcdwCOAgALAAgKlSDcdwCOAgAAAA==.Beyorne:BAAANQAECgIIAgAAAA==.',
Bh='Bhaang:BAAANQAECgcIDwAAAA==.',
Bi='Bigbear:BAAANQADCgYIBgABNQAECgkJLQAFAAUlAA==.Bigbill:BAAANQAECgQIBAAAAA==.Bigdeath:BAABNQAECn8aAAIMAAYKlhZahgCQAQAMAAYKlhZahgCQAQAAAA==.Biletooth:BAAANQADCgcICgABNQAECgQIEAANAAAAAA==.Bizco:BAABNQAECn8dAAIJAAgKmR0RUwB1AgAJAAgKmR0RUwB1AgAAAA==.',
Bj='Bjebo:BAABNQAECn8qAAIDAAkKJQ2rQwDiAQADAAkKJQ2rQwDiAQAAAA==.',
Bl='Bluffshot:BAABNQAECn8lAAIHAAgKHh5NFADVAgAHAAgKHh5NFADVAgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQAECgEIAgAAAA==.',
Bu='Bulltan:BAAANQAECgEIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIBAAAAA==.',
['Bï']='Bïcho:BAABNQAECn8YAAMOAAkKnhvvLQDLAgAOAAkKchvvLQDLAgAPAAIKtQtcZQBXAAAAAA==.',
Ca='Calambar:BAAANQAECgEIAgAAAA==.Cascadio:BAAANQAECgEIAgAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQAECgQIDgAAAA==.',
Ch='Chapjong:BAAANQADCgEIAQAAAA==.Charjer:BAABNQAECn8cAAIQAAgKkBtwTAChAgAQAAgKkBtwTAChAgAAAA==.Chillwolf:BAAANQABCgIIAgAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgYICAAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIEQANAAAAAA==.Coffeeshot:BAAANQADCgcIBwAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgQIBQAAAA==.Costcolshirt:BAAANQAECgEIAgAAAA==.',
Cr='Cranks:BAAANQAECgUIBgAAAA==.Crashcake:BAABNQAECn8bAAIBAAkKyhwiHAClAgABAAkKyhwiHAClAgAAAA==.Creakybones:BAAANQAECgEIAgAAAA==.Croager:BAABNQAECn8VAAIJAAkKFhq1MADZAgAJAAkKFhq1MADZAgAAAA==.',
Cu='Cup:BAABNQAECn8hAAIIAAcKHRSXcQDAAQAIAAcKHRSXcQDAAQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwANAAAAAA==.',
Cy='Cyberlinde:BAAANQAECgQICQAAAA==.Cywen:BAAANQADCggJCAABNQAFFAUIEwAHAJwdAA==.',
Da='Daelaris:BAABNQAECn8dAAILAAkKDx9JPgAJAwALAAkKDx9JPgAJAwAAAA==.Damonoris:BAABNQAECn8YAAIJAAgKtww+jQDrAQAJAAgKtww+jQDrAQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQAECgYICwAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgQIEAANAAAAAA==.',
De='Deadair:BAAANQAECgEIAgAAAA==.Deadlyalba:BAAANQAECgEIAQAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCggICgAAAA==.Demonblades:BAABNQAECn8lAAIEAAgKKhlVHABwAgAEAAgKKhlVHABwAgAAAA==.Demonbreaker:BAABNQAECn8cAAIRAAgKMBTbDADyAQARAAgKMBTbDADyAQAAAA==.Denarten:BAABNQAECn8hAAIGAAkKvSGZJQAtAwAGAAkKvSGZJQAtAwAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcIEgAAAA==.Disrupt:BAAANQAECgQIBgAAAA==.',
Do='Dockevorkian:BAABNQAECn8wAAISAAkKMSH8FgAbAwASAAkKMSH8FgAbAwAAAA==.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAABNQAECn8lAAMOAAkKjRZgYwArAgAOAAgKKxZgYwArAgAPAAIKlhUbVACBAAAAAA==.Doublebonus:BAAANQADCggICAABNQAFFAMIBgABAJsgAA==.Dougdk:BAABNQAECn8tAAIFAAkKBSVkAwC6AwAFAAkKBSVkAwC6AwAAAA==.',
Dr='Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgIIAgANAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJIQAGAL0hAA==.Drinntellect:BAAANQAECgMIBgABNQAECgkJIQAGAL0hAA==.Drinnundead:BAAANQAECgEIAQABNQAECgkJIQAGAL0hAA==.Druelf:BAAANQAECgEIAwAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAwAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgkJHgARAOYjAA==.',
El='Elilla:BAABNQAECn8cAAIFAAgKdgqnYQBoAQAFAAgKdgqnYQBoAQAAAA==.Elkminster:BAAANQAECgMIBAAAAA==.Ellenaya:BAAANQAECggIDwAAAA==.Elorela:BAAANQADCgQIBAABNQAECgkJGAAPAE8XAA==.',
En='Enjoy:BAACNQAFFH8GAAIBAAMKmyDsDQD0AAABAAMKmyDsDQD0AAA1AAQKfyYAAwEACQoYJacHAGgDAAEACQqSJKcHAGgDAAIACQqPIhInAJ0CAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Feardotcom:BAAANQAECgEIAQAAAA==.Felnollid:BAABNQAECn8mAAMTAAkKWhsvHAC1AgATAAkKWhsvHAC1AgAEAAUKewdTTADxAAAAAA==.Fenanigans:BAABNQAECn8iAAIHAAkKeiChCwApAwAHAAkKeiChCwApAwAAAA==.Fenquisition:BAAANQAECgEIAQABNQAECgkJIgAHAHogAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAABNQAECn8gAAMUAAcK1ASLFgDHAAAVAAcKMASRJgD+AAAUAAUKhAeLFgDHAAABNQAECgkJFAAJAHgNAA==.',
Fo='Fontss:BAAANQAECgYIBwAAAA==.Fonyfish:BAAANQAFFAQIBAAAAA==.Forba:BAAANQAECgYIBgAAAA==.',
Fu='Fubina:BAEBNQAECn8vAAMWAAkKgxxtDgD2AgAWAAkKgxxtDgD2AgAXAAIK5R3XJQCcAAAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
['Fâ']='Fâllênknîght:BAABNQAECn8ZAAIFAAgKTxUlPwAAAgAFAAgKTxUlPwAAAgAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.Garazeb:BAAANQAECgEIAQABNQAECgUICAANAAAAAA==.',
Gi='Gilead:BAAANQAECgEIAQAAAA==.Gilgaglaive:BAABNQAECn8YAAIEAAkKIxakHABtAgAEAAkKIxakHABtAgAAAA==.Gilgämesh:BAACNQAFFH8QAAIQAAYKcBd0DADlAQAQAAYKcBd0DADlAQA1AAQKfykAAxAACQpbIdozAO8CABAACQpbIdozAO8CABgAAQr9HOErAFIAAAAA.',
Gl='Glomah:BAABNQAECn8lAAIFAAgK+SHzEgATAwAFAAgK+SHzEgATAwAAAA==.Glorm:BAABNQAECn8mAAIZAAkKxg/TYgDiAQAZAAkKxg/TYgDiAQAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQAECgEIAgAAAA==.',
Gr='Grabbyhands:BAAANQAECgQIEAAAAA==.Grantul:BAABNQAECn8mAAIYAAgK3hTFCQA0AgAYAAgK3hTFCQA0AgAAAA==.Grimthore:BAAANQAECgEIAQABNQAECgcIEwANAAAAAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAAANQAECggIEQAAAA==.',
Gu='Gulbhang:BAABNQAECn8oAAMOAAgK4R9BMgC8AgAOAAgK4R9BMgC8AgAPAAEKXA8DdgA3AAAAAA==.',
Ha='Hakiranatha:BAAANQADCggICAAAAA==.',
Hb='Hbkdx:BAAANQAECgUICgAAAA==.',
He='Health:BAAANQAECgMIAwAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECggIIQAGANsPAA==.Holyhammer:BAAANQAECggICgAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.Homunculus:BAAANQAECgQIBQAAAA==.',
Hu='Hujo:BAABNQAECn8bAAIQAAgKGRKviQAAAgAQAAgKGRKviQAAAgAAAA==.Hushpupi:BAABNQAECn8YAAMPAAkKTxcJCAB+AgAPAAgKGRoJCAB+AgAOAAQKKAo6+ADVAAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQAECgEIAgAAAA==.Icesloth:BAABNQAECn8XAAIMAAgKyxbZUQAuAgAMAAgKyxbZUQAuAgAAAA==.',
Id='Idamarie:BAABNQAECn8UAAIMAAYKXAJ78gCpAAAMAAYKXAJ78gCpAAAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAABNQAECn8YAAIEAAcKAxQALQDWAQAEAAcKAxQALQDWAQAAAA==.',
In='Indecisa:BAAANQAECgEIAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQAECgEIAQAAAA==.',
Ix='Ixiya:BAAANQADCgUICAAAAA==.',
Ja='Jafud:BAAANQAFFAIIAQABNQAFFAUIFQAFAC0bAA==.Jafuds:BAAANQAECgcIDAABNQAFFAUIFQAFAC0bAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgABAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgYIEQAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAAANQAECgQIDwAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgQICQANAAAAAA==.',
Jo='Jordis:BAAANQAECgEIAQAAAA==.',
Ju='Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQAECgEIAQAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kasgotojim:BAAANQAECgQIBAAAAA==.Kaypop:BAAANQADCggICAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAAANQAECgcIEgAAAA==.',
Ki='Kicklocks:BAAANQAECgEIAgAAAA==.Kikuri:BAAANQAECgYIDQAAAA==.Killahertz:BAAANQAECgEIAQAAAA==.Killt:BAABNQAECn8ZAAIZAAgKFhh4UAAgAgAZAAgKFhh4UAAgAgAAAA==.',
Ko='Koojoé:BAAANQAECgQIBgAAAA==.',
Ku='Kurzulan:BAABNQAECn8bAAQaAAgKdgfvOQBLAQAaAAgKdgfvOQBLAQAbAAMK5wN7UwBQAAADAAEKAABeswAtAAAAAA==.',
La='Laghles:BAABNQAECn81AAIJAAkKhR6cHwAXAwAJAAkKhR6cHwAXAwAAAA==.Laroes:BAAANQAECgEIAQABNQAECggIJQAFAPkhAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAAANQAECgUIEAAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAAANQAECggIEwAAAA==.Limbless:BAAANQAECgYIDgAAAA==.',
Lo='Loahealth:BAAANQAECgcIEQAAAA==.Lockrocks:BAABNQAECn8lAAQKAAkKhRFODQCDAQAOAAkKdQ6KcwACAgAKAAYK3g9ODQCDAQAPAAUKCAfHLwAJAQABNQAECgcIEwANAAAAAA==.Lockstar:BAAANQADCgYIDAAAAA==.Loko:BAAANQAECgcIEAAAAA==.Lontra:BAAANQAECgEIAwAAAA==.Loozer:BAAANQAECgcIEwAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAAANQAECggIEwAAAA==.Mahlaan:BAABNQAECn8mAAIFAAgK+xqENQAzAgAFAAgK+xqENQAzAgAAAA==.Malakai:BAAANQADCgIIAgABNQAECgYICAANAAAAAA==.Malekai:BAAANQAECgUJCQABNQAECgYICAANAAAAAA==.Malyce:BAAANQAECgYICAAAAA==.Malzen:BAAANQADCgMIAwABNQAECgYICAANAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Marshusians:BAAANQAECgEIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIICAAAAA==.Maydie:BAAANQAECgYIBwAAAA==.',
Me='Meatcurtin:BAAANQADCgQICAAAAA==.Meatlover:BAAANQAECgYICQAAAA==.Mediocre:BAABNQAECn8XAAIcAAgK+R7IBwDdAgAcAAgK+R7IBwDdAgAAAA==.Meeshka:BAABNQAECn8VAAILAAYKCgtJHQFXAQALAAYKCgtJHQFXAQAAAA==.Meraleona:BAAANQAECggIEQAAAA==.Methslinger:BAAANQAECgQICQAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgkJQgAGAN8iAA==.Miltonroe:BAAANQADCggICAABNQAECggIJQAdAK8LAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgkJIQAaAGcTAA==.Moris:BAAANQAECgUIEwAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAAANQAECggIDAAAAA==.',
Ms='Mswizzlë:BAAANQAECgcIEwAAAA==.',
Mu='Muldah:BAABNQAECn8vAAMLAAkKtRgndACVAgALAAkKeRcndACVAgAeAAcK8QkFHAANAQAAAA==.',
Na='Nas:BAABNQAECn8gAAMOAAgKBx//PACZAgAOAAcKbx//PACZAgAPAAEKAB0mZgBVAAAAAA==.Nausicaa:BAAANQAECgEIAwAAAA==.Nausicaä:BAAANQAECgEIAQAAAA==.Navie:BAAANQAECgYIEwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECggIHAAQAJAbAA==.Neø:BAABNQAECn8jAAMBAAgKlBiBOQDnAQABAAcKzReBOQDnAQACAAYK5R0/XgCSAQAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgYICgAAAA==.Nightshala:BAAANQAECgQIBAAAAA==.',
No='Nollid:BAAANQADCgYIBgABNQAECgkJJgATAFobAA==.Nordburg:BAAANQAECgEIAQAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.Notforgiven:BAAANQADCgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIEQAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgQIBgAAAA==.',
['Ná']='Nácht:BAAANQAECgYICgAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Om='Omaticaya:BAABNQAECn8oAAIDAAgKvQg5VgB6AQADAAgKvQg5VgB6AQAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgUIDQAAAA==.',
Or='Oriax:BAAANQAECgUICAABNQAECggIMwADADEbAA==.',
Ow='Owlbearcat:BAAANQAECgYIDwABNQAECgcIEQANAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgYIHwAAAA==.Paj:BAACNQAFFH8KAAILAAYK+wcoHACYAQALAAYK+wcoHACYAQA1AAQKfycAAgsACQorIjwUAIIDAAsACQorIjwUAIIDAAAA.',
Pe='Peata:BAAANQADCgMIAwAAAA==.Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIBgABNQAECgMICQANAAAAAA==.',
Pi='Pinga:BAAANQAECgMIAwABNQAECggIHQAJAJkdAA==.',
Pk='Pkalygos:BAABNQAECn8YAAIfAAcKlBAKJgCIAQAfAAcKlBAKJgCIAQAAAA==.',
Pl='Pleione:BAAANQAECgYIEAAAAA==.',
Po='Portadave:BAAANQAECgMIAwAAAA==.Powerstrokee:BAAANQAECgQIBgAAAA==.',
Pr='Preyforme:BAABNQAECn8kAAIJAAgKsAjUlgDWAQAJAAgKsAjUlgDWAQAAAA==.Prusik:BAAANQADCgcIBwABNQAECgMIAwANAAAAAA==.Práystation:BAAANQADCgMIAwAAAA==.',
Ps='Psychelone:BAAANQAECgQICAAAAA==.',
Pu='Puffshot:BAAANQAECgEIAwABNQAECggIJQAHAB4eAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIEQANAAAAAA==.',
Qy='Qyxh:BAABNQAECn8WAAMTAAgKZgyUQQCuAQATAAgKZgyUQQCuAQARAAIKggNuMAA4AAAAAA==.',
Ra='Raine:BAAANQADCggIEAAAAA==.Rannath:BAAANQAECggIAwABNQAECggIDAANAAAAAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Redeye:BAAANQAECgEIAgAAAA==.Rehne:BAAANQAECgEJAQAAAA==.Rexhavoc:BAABNQAECn8eAAIEAAkKixYRHAByAgAEAAkKixYRHAByAgAAAA==.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQAECgQIBAAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAABNQAECn8eAAIbAAcKQQUWMQAPAQAbAAcKQQUWMQAPAQAAAA==.Rosewoodren:BAAANQAECgIIAQAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAABNQAECn8UAAICAAgKDxhIRAAFAgACAAgKDxhIRAAFAgAAAA==.',
Ry='Ryla:BAAANQADCgIIAgABNQAECggIIwAHAAgaAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBgANAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEIAQABNQAECgMIAwANAAAAAA==.Salitheion:BAAANQAECgMIBQAAAA==.Sammaa:BAAANQAECgEIAQAAAA==.Sapper:BAABNQAECn8zAAIgAAkKYiIZAwCCAwAgAAkKYiIZAwCCAwAAAA==.Sarn:BAAANQADCggICAAAAA==.Sathi:BAAANQAECgIIAQAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shikí:BAAANQAECgEIAgAAAA==.Shladoran:BAABNQAECn8bAAIQAAgKrwyzrwCgAQAQAAgKrwyzrwCgAQAAAA==.Shos:BAABNQAECn8mAAIhAAkKCh7GCADCAgAhAAkKCh7GCADCAgAAAA==.',
Si='Siberianwolf:BAAANQAECgcIBwAAAA==.Sinnister:BAAANQADCgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAECgkJLQAFAAUlAA==.',
Sl='Sledge:BAAANQADCgMIAwAAAA==.',
Sn='Snapdragyn:BAAANQAECgIIAQAAAA==.Snorina:BAABNQAECn8nAAIiAAkKYh52DQATAwAiAAkKYh52DQATAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwAAAA==.Sosozen:BAABNQAECn8cAAIWAAcKNwrWNwBQAQAWAAcKNwrWNwBQAQAAAA==.Soul:BAAANQAECgYIDwAAAA==.',
Sp='Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAABNQAECn8nAAIQAAgKahpQUgCQAgAQAAgKahpQUgCQAgAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Supremacy:BAABNQAECn8cAAMOAAgKMSamCwBuAwAOAAgKMSamCwBuAwAPAAEKzSGTYgBeAAAAAA==.',
Sw='Sweetspot:BAAANQAECgcIDgABNQAECgcIEwANAAAAAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAABNQAECn8jAAIHAAgKCBrpIgBrAgAHAAgKCBrpIgBrAgAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgkJJwAiAGIeAA==.Sylvii:BAABNQAECn8mAAIaAAgKqBI8KQDRAQAaAAgKqBI8KQDRAQAAAA==.',
Ta='Tabor:BAAANQAECgQICAAAAA==.Taggz:BAAANQAECgEIAwAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAABNQAECn8bAAIIAAgKNiBCIQDnAgAIAAgKNiBCIQDnAgAAAA==.Tauryel:BAAANQAECgQIBwABNQAECgYIDgANAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECggIEAANAAAAAA==.',
Th='Thasarias:BAAANQAECgUICAAAAA==.Themoosifer:BAACNQAFFH8XAAIEAAcKPRf4AQBiAgAEAAcKPRf4AQBiAgA1AAQKfycAAgQACQoMI9wNAAcDAAQACQoMI9wNAAcDAAAA.Thunderdumps:BAABNQAECn8dAAIZAAgKqxfySwAwAgAZAAgKqxfySwAwAgAAAA==.Thyck:BAABNQAECn8bAAIJAAgK/xF5cAAuAgAJAAgK/xF5cAAuAgAAAA==.Thydis:BAABNQAECn8sAAIGAAkKyQqFrADBAQAGAAkKyQqFrADBAQAAAA==.',
Ti='Tiancit:BAAANQAECgEIAwAAAA==.Tibbs:BAABNQAECn8lAAMVAAgKhRBSFQD1AQAVAAgKsw9SFQD1AQAUAAYKThBsEAAuAQAAAA==.Ticklepickle:BAAANQAECgQICgAAAA==.',
To='Tooch:BAAANQAECgEIAQAAAA==.Torluis:BAAANQADCgMIAwAAAA==.',
Tr='Trumalice:BAAANQADCgYIEAAAAA==.',
Tu='Tulpa:BAAANQAECgEIBQAAAA==.',
Un='Uncorrupted:BAABNQAECn8dAAMjAAkKTxOzKACTAQAjAAgKIBazKACTAQAGAAIKigRUqwEvAAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICgANAAAAAA==.',
Va='Vaelm:BAAANQADCgIIAwAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAABNQAECn8cAAMLAAgKehbkzwDkAQALAAcKqxHkzwDkAQAeAAIKRyBFJgC8AAAAAA==.Valjin:BAAANQADCgQIBAABNQAECggIHAALAHoWAA==.Valsan:BAAANQAECgEIAQAAAA==.Valuryan:BAAANQADCggIEAABNQAECggIHAALAHoWAA==.Variana:BAAANQAECgEIAQAAAA==.',
Ve='Velathila:BAAANQAECgIIBAAAAA==.',
Vi='Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAABNQAECn8XAAIKAAcKbBAwCgDVAQAKAAcKbBAwCgDVAQAAAA==.',
Vo='Voidchris:BAABNQAECn8qAAMEAAkKUh29DwDyAgAEAAkKUh29DwDyAgATAAQKpQ4yZwDXAAAAAA==.Voidormu:BAAANQAECgIIAwAAAA==.',
Wa='Warelf:BAABNQAECn8UAAMOAAkKICH/JQDpAgAOAAkKICH/JQDpAgAPAAEKUxGqcwA6AAAAAA==.Warleck:BAAANQAECgQIBQAAAA==.',
Wh='Whillen:BAAANQADCgEIAQAAAA==.Whodey:BAAANQAECgUICQABNQAECgYICAANAAAAAA==.',
Wi='Wisp:BAAANQADCgYIDwAAAA==.',
Wy='Wylia:BAAANQAECgcICgAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yu='Yuffshot:BAAANQAECgEIAwABNQAECggIJQAHAB4eAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECn8wAAIJAAkKHBWHSACRAgAJAAkKHBWHSACRAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwANAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zy='Zylera:BAAANQAECgMIBQAAAA==.Zyphor:BAAANQAECgEIAQAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAABNQAECn8UAAMfAAcK4Q4pLwAiAQAfAAYKAAspLwAiAQAVAAIKJw1aMwBvAAAAAA==.',
['Ød']='Ødinson:BAAANQAECgEJAQAAAA==.',
['ßæ']='ßær:BAAANQAECgIJAwAAAA==.',
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
