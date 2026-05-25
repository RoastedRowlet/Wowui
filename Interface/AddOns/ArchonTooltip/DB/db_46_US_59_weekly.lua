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

local lookup = {'Warlock-Demonology','Druid-Restoration','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','Monk-Mistweaver','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Shaman-Enhancement','Warlock-Destruction','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Arcane','Warlock-Affliction','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aanx:BAABLgAECn8TAAIBAAYJth2uegBmAQABAAYJth2uegBmAQAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAECgkJHAACAAIcAA==.Abdorei:BAABLgAECn8pAAIDAAgJkxWIVgC8AQADAAgJkxWIVgC8AQAAAA==.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8aAAIEAAcJQh4nHgBRAgAEAAcJQh4nHgBRAgABLgAECgkJIgADAHIZAA==.Accilatim:BAABLgAECn8iAAIDAAkJchmhJQBpAgADAAkJchmhJQBpAgAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAFAAAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIGAAkJahhVNgBJAgAGAAkJahhVNgBJAgAAAA==.',
Ai='Aiba:BAABLgAECn8ZAAIHAAgJ1hfpGADXAQAHAAgJ1hfpGADXAQAAAA==.',
Ak='Akcloud:BAABLgAFFH8KAAMIAAMJ7BvbEgDnAAAIAAMJPBfbEgDnAAAJAAEJ2yPTHQBoAAAAAA==.',
Al='Alab:BAAALgAECgEJAQAAAA==.Alaeris:BAACLgAFFH8IAAIKAAMJxhXDJADNAAAKAAMJxhXDJADNAAAuAAQKfyAAAgoACAlPH+UMAJcCAAoACAlPH+UMAJcCAAAA.Albetabeef:BAACLgAFFH8JAAMLAAQJGxT1DQAtAQALAAQJGxT1DQAtAQAJAAIJJgZQHACUAAAuAAQKfxgAAwsACAn/IAkIAEwCAAkABwk2ICAWAJwCAAsABwmjIgkIAEwCAAAA.Alexei:BAAALgAECgkJBAAAAA==.Aleyeah:BAAALgAECgIJBAABLgAECggJMQAMADgfAA==.Allhopeisded:BAAALgAECgYJEgAAAA==.Alurelor:BAAALgAECggJCwAAAA==.Alyreu:BAAALgAECgQJBAABLgAECgYJDQAFAAAAAA==.',
Am='Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn8tAAINAAgJEQxLSgBSAQANAAgJEQxLSgBSAQAAAA==.',
An='Anddi:BAAALgAECgEJAwAAAA==.Andii:BAACLgAFFH8HAAIOAAMJMBsXIADyAAAOAAMJMBsXIADyAAAuAAQKfxgABA4ACAnIF38/AHoBAA4ABwnQFn8/AHoBAAYAAgm2B/hJAS8AAA8AAQkAAD9RAAAAAAAA.Andy:BAACLgAFFH8FAAIQAAMJHgoxJgDOAAAQAAMJHgoxJgDOAAAuAAQKfxQAAxAACAkoH8YIAMACABAACAkoH8YIAMACABEAAQkXB9V0AC0AAAAA.Angusbeef:BAAALgADCgQJBAAAAA==.Antipus:BAAALgAECgQJBQAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAECgkJMgASAIoiAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwATANsWAA==.Ardeno:BAABLgAECn8XAAMTAAYJ2xarIwA7AQATAAYJbwyrIwA7AQABAAUJ2xb+igAPAQAAAA==.Ardon:BAABLgAECn8sAAMNAAkJ8hqkDgC1AgANAAkJ8hqkDgC1AgAMAAUJvhsbMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8kAAIEAAkJDh77HgBDAgAEAAkJDh77HgBDAgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ay='Ayroon:BAAALgAECgEJAQAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH8wAAIOAAgJeg9DBAA2AgAOAAgJeg9DBAA2AgAuAAQKfzwAAw4ACQlmILMIAOMCAA4ACQlmILMIAOMCAAYAAQm4AedYASYAAAAA.Barkendremix:BAABLgAECn80AAMUAAkJYRuHCQB+AgAUAAkJYRuHCQB+AgAVAAEJFBX7dgA+AAAAAA==.Bathsheber:BAAALgAFFAEJAQABLgAFFAYJFgADANciAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8dAAIWAAYJKBO6JQBNAQAWAAYJKBO6JQBNAQAAAA==.',
Bj='Bjorum:BAACLgAFFH8GAAISAAMJsR26BwD+AAASAAMJsR26BwD+AAAuAAQKfyEAAxIACAkpIrkEAMkCABIACAkpIrkEAMkCAAwAAQnhCLaQACcAAAAA.',
Bo='Bodytwodafa:BAACLgAFFH8MAAMXAAMJtRRmBQDoAAAXAAMJqxBmBQDoAAAYAAMJDA8uMwDGAAAuAAQKfyAABBcACAntIBgGAJUCABcACAkhHhgGAJUCABkABgn4GBYPALcBABgABwlwGEMmAIwBAAAA.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJCQAAAA==.',
Bu='Bubbleyou:BAABLgAECn8XAAMPAAYJ4Q6wJAC/AAAPAAYJlw6wJAC/AAAGAAIJuwoqcgErAAAAAA==.Burnek:BAAALgAECgIJAwABLgAECgUJDgAFAAAAAA==.',
Ca='Cantarella:BAABLgAECn8pAAMaAAgJvgWrIwBJAQAaAAgJvgWrIwBJAQAbAAcJ2QKMEwDJAAAAAA==.Carlyle:BAABLgAECn8iAAMGAAkJWRibTwC6AQAGAAkJWRibTwC6AQAOAAEJPR2fcgBHAAAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheekyteetah:BAAALgAECgEJAQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBgAAAA==.',
Co='Collossuss:BAAALgAECgYJEgAAAA==.Convik:BAAALgAECgcJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIJAAcJAhQdMgBdAQAJAAcJAhQdMgBdAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8hAAIGAAgJJBPacgCWAQAGAAgJJBPacgCWAQAAAA==.Darkstarr:BAAALgAECgEJAQAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAIAHYVAA==.Dekaar:BAABLgAECn8aAAIcAAYJuwmAHgDYAAAcAAYJuwmAHgDYAAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgcJCgAAAA==.Derek:BAAALgAECgYJBgAAAA==.Desdemonica:BAABLgAECn8VAAIEAAgJYgd6ZwBGAQAEAAgJYgd6ZwBGAQAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCggJCAAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8yAAIdAAkJ9xPmFwDnAQAdAAkJ9xPmFwDnAQAAAA==.Domain:BAABLgAECn8eAAIeAAgJUBjwMgDaAQAeAAgJUBjwMgDaAQAAAA==.Donfalprun:BAABLgAECn8gAAIGAAkJICP/BwATAwAGAAkJICP/BwATAwAAAA==.Doomstout:BAABLgAECn8WAAIDAAgJSBJlZwCRAQADAAgJSBJlZwCRAQAAAA==.',
Dr='Draconus:BAABLgAECn8zAAMfAAkJfhXVDQD8AQAfAAkJUBPVDQD8AQAgAAQJcRtfyADGAAAAAA==.Dralas:BAAALgAECgYJCgAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAFAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJCAAFAAAAAA==.Duskshade:BAAALgADCggJEgAAAA==.',
['Dü']='Düsk:BAAALgAECgkJDAAAAA==.',
Ea='Eachan:BAAALgAECgMJAwAAAA==.',
El='Elij:BAACLgAFFH8FAAIBAAIJAwxDjwB9AAABAAIJAwxDjwB9AAAuAAQKfx8AAgEACAmJHloaAGwCAAEACAmJHloaAGwCAAAA.Elunaire:BAABLgAECn8cAAICAAkJAhySHQBRAgACAAkJAhySHQBRAgAAAA==.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAACLgAFFH8MAAICAAMJHCNgHwApAQACAAMJHCNgHwApAQAuAAQKfxwAAgIACAmlI2sGACUDAAIACAmlI2sGACUDAAAA.',
Er='Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAABLgAECn8XAAITAAgJhxB1JAA3AQATAAgJhxB1JAA3AQAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8XAAMLAAYJShd7BgCOAQALAAYJShd7BgCOAQAJAAMJGQzSEgDvAAAuAAQKfyYAAwsACQngG3gGAGQCAAsACQnLGngGAGQCAAkABglLHFw1ANQBAAAA.',
Fa='Falin:BAAALgAECgEJAQAAAA==.',
Fe='Fey:BAABLgAECn8iAAIBAAkJ5BM7PQDOAQABAAkJ5BM7PQDOAQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECgUJDgAFAAAAAA==.Fistvendor:BAABLgAECn8UAAIUAAkJxAg3JQBkAQAUAAkJxAg3JQBkAQAAAA==.',
Fl='Flasheals:BAABLgAECn8oAAIOAAgJBxJtKgCVAQAOAAgJBxJtKgCVAQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAABLgAECn8ZAAIEAAgJGxYmNwDWAQAEAAgJGxYmNwDWAQAAAA==.',
Fr='Frenzaoibh:BAAALgADCgcJBwABLgAECgkJMgASAIoiAA==.Frostine:BAABLgAECn8VAAIDAAcJ7gZC1QBEAQADAAcJ7gZC1QBEAQAAAA==.Frostwave:BAABLgAECn82AAMhAAgJah98BQAcAgAhAAgJ1R58BQAcAgAfAAgJwRZ7EQDFAQAAAA==.Frostythot:BAAALgADCgIJAgAAAA==.',
Fu='Fujiyama:BAABLgAECn8xAAIMAAgJOB/0DgBaAgAMAAgJOB/0DgBaAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQAEAMUWAA==.Garréosh:BAAALgAECgUJCgABLgAFFAMJCgAGACMSAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgIJAwAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Golteb:BAAALgAECgQJBAAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.Groggi:BAAALgAECgYJBAAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECggJEwAFAAAAAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8uAAQYAAkJ6AteJwCGAQAYAAkJXQteJwCGAQAZAAgJegNaGwADAQAXAAcJwQcqEgDEAAAAAA==.',
Ha='Hadouken:BAAALgAECgkJCwAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8gAAICAAkJpg6DQQBoAQACAAkJpg6DQQBoAQAAAA==.Hexed:BAAALgAECgQJBwAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgYJDgAAAA==.Holymama:BAABLgAECn8gAAMRAAgJeh1mFAAGAgARAAcJdCBmFAAGAgAQAAIJIRMGUAB1AAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Ickma:BAABLgAECn84AAIgAAgJgB47NQAGAgAgAAgJgB47NQAGAgAAAA==.',
Id='Iddou:BAAALgAECgMJBAAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgADCggJDQAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgAECgQJBAAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCwAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgYJBQAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgAECgMJAwAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJAwAAAA==.',
Ka='Kaollanna:BAABLgAECn8jAAIDAAkJDhYWWQAuAgADAAkJDhYWWQAuAgAAAA==.Karik:BAAALgAECgQJCQAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Kelisa:BAABLgAECn8uAAIGAAkJPx0CHAB/AgAGAAkJPx0CHAB/AgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCwABLgAECgYJDQAFAAAAAA==.Kinza:BAAALgADCgkJCQABLgAECggJGQAHANYXAA==.Kiwidin:BAABLgAECn8fAAIOAAgJSRfmJgDzAQAOAAgJSRfmJgDzAQAAAA==.',
Ko='Koketsu:BAAALgAECgYJCwAAAA==.',
Kr='Krinxy:BAABLgAECn8VAAICAAUJFhqSWwA/AQACAAUJFhqSWwA/AQAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJCgABLgAECgUJDgAFAAAAAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgUJCwABLgAECgUJDgAFAAAAAA==.',
La='Lazyde:BAAALgAECgIJAwABLgAECggJOAAiANEiAA==.',
Le='Ledgerfeign:BAABLgAECn8qAAIBAAkJDg13QwC5AQABAAkJDg13QwC5AQAAAA==.',
Li='Liadan:BAAALgAECggJEwAAAA==.Lighteye:BAABLgAECn84AAICAAgJvBdpHwAnAgACAAgJvBdpHwAnAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJEgAFAAAAAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAABLgAECn8UAAIZAAYJDhNuFwA0AQAZAAYJDhNuFwA0AQAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAACLgAFFH8FAAIDAAIJxBTofAClAAADAAIJxBTofAClAAAuAAQKfygAAgMACAnwICYpAFkCAAMACAnwICYpAFkCAAAA.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgQJBAAAAA==.Massivebicep:BAAALgAECgIJAgAAAA==.Mavras:BAAALgADCgEJAQAAAA==.',
Mc='Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAACLgAFFH8KAAIeAAMJrAU+VgC0AAAeAAMJrAU+VgC0AAAuAAQKfx8AAyMACAkqEmseAMwBACMACAnIC2seAMwBAB4ACAk1EatRAG4BAAAA.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgYJCAAAAA==.Moosedon:BAAALgAECgEJAQABLgAECgkJIAAGACAjAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAABLgAECn8XAAQEAAUJbiC9TQCAAQAEAAUJbiC9TQCAAQAWAAMJMxSxQwB+AAAkAAEJzAMGlgAjAAAAAA==.',
My='Mylianne:BAABLgAECn8aAAIHAAcJYhz5FwDhAQAHAAcJYhz5FwDhAQAAAA==.Mynameiscole:BAACLgAFFH8IAAIjAAQJgh98AQCSAQAjAAQJgh98AQCSAQAuAAQKfyMAAiMACAmZJq4BAIoDACMACAmZJq4BAIoDAAEuAAUUBgkTAB4AiR0A.Myrolan:BAABLgAECn8sAAIjAAkJCCTRAQAzAwAjAAkJCCTRAQAzAwAAAA==.Myrtru:BAAALgAECggJCAAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAHAOciAA==.Nevyn:BAABLgAECn8eAAIlAAgJBxS9AwCyAQAlAAgJBxS9AwCyAQAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgUJCQAAAA==.Niji:BAAALgAECgIJBAABLgAECggJGQAHANYXAA==.Nininhp:BAAALgAECgUJCgABLgAECgYJEgAFAAAAAA==.Nithari:BAABLgAECn82AAIDAAgJgCEOHwCIAgADAAgJgCEOHwCIAgAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8hAAMQAAkJsBaDEQAwAgAQAAkJsBaDEQAwAgARAAEJbhAHawA4AAAAAA==.Now:BAACLgAFFH8MAAIGAAMJGyEDLwAxAQAGAAMJGyEDLwAxAQAuAAQKfx8AAwYACAkQIOAtAGsCAAYACAlPHuAtAGsCAA8ABgmIF24XADUBAAAA.',
Nu='Nukum:BAAALgAECgYJEAABLgAECggJEAAFAAAAAA==.',
Oh='Ohpa:BAABLgAECn8gAAMBAAgJKBRzPQDNAQABAAgJKBRzPQDNAQAmAAIJUQnzMQAwAAAAAA==.Ohrly:BAAALgAECgEJAQAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIcAAgJvSKkAwD2AgAcAAgJvSKkAwD2AgAAAA==.Ojpriest:BAAALgAFFAIJAgAAAA==.',
Pa='Pallykera:BAAALgAECgEJAQAAAA==.Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJEAAAAA==.',
Pe='Pepecry:BAAALgAECgUJDgAAAA==.',
Ph='Phoblade:BAABLgAECn8fAAIgAAgJKBWMSgDAAQAgAAgJKBWMSgDAAQAAAA==.Phokk:BAAALgAECgcJBwAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Ponylion:BAAALgAECgYJCwABLgAECgcJEQAFAAAAAA==.Pooshka:BAABLgAECn8dAAIMAAkJSCJiCgDvAgAMAAkJSCJiCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8TAAIWAAQJwia2AgC/AQAWAAQJwia2AgC/AQAuAAQKfykAAxYACAlqJpcAAIsDABYACAlqJpcAAIsDACQAAQm/JHV7AFUAAAEuAAUUBQkVACAASyEA.Presibro:BAAALgAECgYJEgAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgUJDgAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAACLgAFFH8LAAIEAAMJwRowOgD+AAAEAAMJwRowOgD+AAAuAAQKfxUAAgQACAlNGzMyAOoBAAQACAlNGzMyAOoBAAAA.',
Ra='Ranouu:BAABLgAECn8VAAIDAAYJIBW8nACcAQADAAYJIBW8nACcAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECgkJMgASAIoiAA==.Recision:BAABLgAECn84AAIiAAgJ0SKwAgCmAgAiAAgJ0SKwAgCmAgAAAA==.Reeash:BAABLgAECn8XAAMNAAkJABdLHQA1AgANAAkJABdLHQA1AgAMAAMJyAu2ZQCAAAAAAA==.Reeatar:BAABLgAECn8ZAAIDAAcJ5Rg9oACWAQADAAcJ5Rg9oACWAQABLgAECgkJFwANAAAXAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAgAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn8lAAIIAAYJ0BDfIQD5AAAIAAYJ0BDfIQD5AAAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8eAAIQAAgJtxnnEwARAgAQAAgJtxnnEwARAgABLgAFFAMJCwAEAMEaAA==.',
Ru='Runcat:BAABLgAECn8XAAMeAAgJQh4MHwA9AgAeAAgJQh4MHwA9AgAiAAQJ1QaKHQCCAAAAAA==.',
['Rö']='Röyksopp:BAABLgAECn8aAAIDAAgJwQrydQBwAQADAAgJwQrydQBwAQAAAA==.',
Sa='Sabo:BAAALgADCgQJBQAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Samarah:BAAALgAECgQJAgAAAA==.Sandewor:BAABLgAECn8UAAQPAAYJ4RfhFQBHAQAPAAYJ4RfhFQBHAQAGAAMJ0QoE9ACaAAAOAAEJZgfXhQAoAAABLgAECgYJFQAWAPwMAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAFAAAAAA==.Sarafyn:BAABLgAECn82AAIdAAgJ5hjCFwDpAQAdAAgJ5hjCFwDpAQAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAYJEwAeAIkdAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8gAAMQAAcJsRtpFAALAgAQAAcJsRtpFAALAgARAAYJgxB2MwAjAQAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegrorc:BAABLgAECn8pAAIIAAgJrg4tGwA0AQAIAAgJrg4tGwA0AQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sindrila:BAAALgAECgYJAwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAABLgAECn8VAAQWAAYJ/Aw1KwAlAQAWAAYJ2ws1KwAlAQAEAAQJywvegQDiAAAkAAIJqQwGeABgAAAAAA==.Slayertin:BAAALgAECgYJCwABLgAECgYJFQAWAPwMAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8cAAIMAAYJgw4YSADjAAAMAAYJgw4YSADjAAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgUJCQAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgAECgEJAQAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgADCgQJBAAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgQJBAAAAA==.',
St='Steady:BAABLgAECn8YAAIGAAcJThWzfgBQAQAGAAcJThWzfgBQAQAAAA==.Stonehand:BAABLgAECn8tAAIRAAkJoBR0FAAFAgARAAkJoBR0FAAFAgAAAA==.Stormsurge:BAAALgAECgMJAwAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.Strongbow:BAAALgAECgYJBwAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAABLgAECn8rAAInAAkJBgl5IQD+AAAnAAkJBgl5IQD+AAAAAA==.Sugasuga:BAAALgAECgcJEQAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8fAAIJAAgJxRahJQClAQAJAAgJxRahJQClAQAAAA==.Tagsy:BAABLgAECn8VAAIEAAgJxRZdOQDJAQAEAAgJxRZdOQDJAQAAAA==.Tay:BAAALgAECgYJBQAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn84AAITAAgJdRCTCgBrAQATAAgJdRCTCgBrAQAAAA==.',
Th='Then:BAABLgAECn8oAAIDAAcJSBkbXgCoAQADAAcJSBkbXgCoAQAAAA==.Threetimez:BAAALgAECgcJDwAAAA==.Thumbmage:BAAALgAECgYJCwABLgAECgkJPgAMALslAA==.',
Ti='Timemaster:BAABLgAECn8eAAMjAAYJwhvMFwCPAQAjAAYJwhvMFwCPAQAeAAIJnQMT1wBCAAAAAA==.Timepacifist:BAAALgAECgQJBAAAAA==.',
To='Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAABLgAECn8UAAIKAAMJLg4taQB4AAAKAAMJLg4taQB4AAAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMGAAgJVBeZUQDsAQAGAAgJVBeZUQDsAQAOAAEJ0AqlngAqAAAAAA==.Troiikâ:BAABLgAECn86AAQPAAkJphQEEADFAQAPAAkJphQEEADFAQAGAAcJNgfQqAAIAQAOAAUJ8QKDXgCKAAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn8jAAIIAAgJtw/uGwAtAQAIAAgJtw/uGwAtAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgQJBAAFAAAAAA==.Ttevoker:BAAALgAECgQJBAAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8mAAICAAgJIxy2FACCAgACAAgJIxy2FACCAgAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMWAAkJJw3KGQCxAQAWAAkJkAnKGQCxAQAkAAgJiQ3iMwCcAQAAAA==.',
Uw='Uwantwar:BAAALgAECgUJCAAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAECgYJEAAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Vodka:BAAALgAECgEJAgAAAA==.Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn8YAAMRAAcJug/bLgA7AQARAAcJug/bLgA7AQAQAAEJ7gH4XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJAgAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAINAAYJKxtDPwB/AQANAAYJKxtDPwB/AQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgYJDAAAAA==.',
Xa='Xannada:BAABLgAECn8xAAIGAAgJMAq9hgBBAQAGAAgJMAq9hgBBAQAAAA==.',
Ya='Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8NAAIRAAYJZwypQwDVAAARAAYJZwypQwDVAAAAAA==.Yoh:BAACLgAFFH8MAAIgAAMJCxALewDcAAAgAAMJCxALewDcAAAuAAQKfxwAAiAACAlKHXE1AAYCACAACAlKHXE1AAYCAAAA.Yourenotron:BAAALgAECgEJAQAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJEgABLgAECggJGQAHANYXAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8lAAIUAAkJ7hFbGADFAQAUAAkJ7hFbGADFAQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
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
