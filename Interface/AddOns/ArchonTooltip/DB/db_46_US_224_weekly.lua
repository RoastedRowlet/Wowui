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

local lookup = {'Paladin-Retribution','Mage-Frost','Warrior-Fury','Monk-Brewmaster','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','DeathKnight-Unholy','Druid-Guardian','Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Mage-Fire','Mage-Arcane','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','Priest-Holy','DemonHunter-Devourer','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement',}
local provider = {region='US',realm='Tortheldrin',name='US',type='weekly',zone=46,date='2026-08-18',data={Ac='Acquinus:BAAALgAECgEJAQAAAA==.',
Ad='Adonis:BAABLgAECn8UAAIBAAgJtgnTvAANAQABAAgJtgnTvAANAQAAAA==.',
Ag='Agatha:BAAALgAECgYJDAAAAA==.',
Ai='Aioli:BAAALgAECgMJAwABLgAFFAUJGwACAGIeAA==.',
Al='Altreyuzz:BAAALgADCgUJBQAAAA==.',
An='Anastarya:BAAALgAECgQJBQAAAA==.Anmor:BAAALgAECgcJDwABLgAFFAUJFAABADEbAA==.Antiserum:BAAALgAECgMJAwAAAA==.',
Ap='Apocalypse:BAABLgAECn8XAAIDAAkJYwayXwAxAQADAAkJYwayXwAxAQAAAA==.',
Ar='Arockoner:BAAALgADCgEJAQAAAA==.Arrowk:BAAALgAECgEJAQAAAA==.',
As='Astrozerg:BAAALgAECggJCAABLgAFFAgJKwAEAGsmAA==.',
Az='Azeroth:BAAALgADCgYJBgAAAA==.Azin:BAABLgAFFH8RAAIFAAUJixd4GgATAQAFAAUJixd4GgATAQAAAA==.',
Ba='Baen:BAAALgAECgYJCgAAAA==.',
Be='Bearju:BAAALgAECgIJBAAAAA==.Bet:BAAALgADCgMJAwABLgAECgUJCgAGAAAAAA==.',
Br='Braxticus:BAAALgADCgYJDQAAAA==.Bruceyuu:BAAALgAECgYJDQAAAA==.',
Bu='Bubble:BAABLgAECn8UAAIBAAcJHRXjfAB1AQABAAcJHRXjfAB1AQAAAA==.',
Ca='Cassidin:BAACLgAFFH8UAAIBAAUJMRsWJAD6AAABAAUJMRsWJAD6AAAuAAQKfxkAAgEACQmCHagvAGQCAAEACQmCHagvAGQCAAAA.Cataclysm:BAAALgAECgkJAgAAAA==.',
Ch='Chammick:BAAALgADCgIJAgAAAA==.Chooch:BAABLgAECn8cAAMHAAYJjBzvHgDHAQAHAAYJjBzvHgDHAQAIAAEJjA9hNgAtAAAAAA==.',
Ci='Cidril:BAABLgAECn8aAAIBAAgJ1BNIcACOAQABAAgJ1BNIcACOAQAAAA==.',
Co='Convoké:BAABLgAFFH8GAAIJAAQJ4RRjFgDRAAAJAAQJ4RRjFgDRAAAAAA==.',
Cr='Creating:BAABLgAECn8fAAIBAAgJ1R25OABAAgABAAgJ1R25OABAAgABLgAFFAMJCAAKAL0FAA==.Creep:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Crk:BAAALgAECgQJBQABLgAFFAMJCAAKAL0FAA==.Crkgetd:BAAALgAECgEJAQABLgAFFAMJCAAKAL0FAA==.Cryptik:BAAALgADCgEJAQAAAA==.Cryptoprocta:BAAALgADCgUJCAAAAA==.',
Cu='Cuckcurll:BAABLgAFFH8IAAILAAMJ+CROBgA+AQALAAMJ+CROBgA+AQABLgAFFAUJCwALACgkAA==.',
De='Deathslip:BAAALgAECgQJCAABLgAECgUJCQAGAAAAAA==.Devilneroo:BAABLgAECn8bAAIHAAgJlRsMFADyAQAHAAgJlRsMFADyAQAAAA==.',
Do='Donut:BAAALgAECgEJAgAAAA==.Doobiesnibs:BAAALgAECgYJDAAAAA==.Doomzilla:BAAALgAECgcJBgAAAA==.Doth:BAABLgAECn8WAAIKAAYJESI2UQD+AQAKAAYJESI2UQD+AQAAAA==.Dovregubben:BAAALgAECgUJCgAAAA==.',
Dr='Drakknar:BAAALgAECgcJBwAAAA==.Drogyn:BAAALgAECgUJBgAAAA==.',
Dv='Dvlock:BAAALgAECgUJCQAAAA==.',
['Dò']='Dòóm:BAAALgAECgYJDgAAAA==.',
['Dó']='Dóóm:BAAALgAECgEJAQAAAA==.',
Ek='Ekrizdis:BAAALgADCgEJAgAAAA==.',
Em='Emryss:BAABLgAECn8VAAIJAAgJ0BeLGwDuAQAJAAgJ0BeLGwDuAQAAAA==.',
Ex='Exile:BAAALgAECgkJEgAAAA==.',
Fa='Failure:BAABLgAFFH8FAAIMAAQJwhWNAgBCAQAMAAQJwhWNAgBCAQABLgAFFAgJHwAJALcaAA==.',
Fe='Feardis:BAAALgAECgMJAwAAAA==.',
Fi='Finalgrace:BAAALgADCgYJBgAAAA==.Finnix:BAAALgADCgEJAQAAAA==.',
Fu='Furfoxsake:BAAALgADCgIJAwAAAA==.',
Gi='Gigilong:BAACLgAFFH8GAAINAAMJdhu7GwAXAQANAAMJdhu7GwAXAQAuAAQKfx0AAg0ABwmcI5EWAM0CAA0ABwmcI5EWAM0CAAAA.Gihon:BAAALgAECgUJCwAAAA==.',
Go='Gorrdain:BAAALgADCgEJAQAAAA==.Gorrgath:BAAALgAECgYJCgAAAA==.',
Gr='Grandeur:BAAALgAECgIJAgAAAA==.Greencrayon:BAAALgAECgMJBAAAAA==.Greenlifebro:BAAALgAECgYJCgAAAA==.Gristlezerg:BAAALgAECgUJBwABLgAFFAgJKwAEAGsmAA==.',
Hi='Hippopotamus:BAAALgAECgYJDQAAAA==.',
Ho='Holyhealz:BAAALgAECgMJAwAAAA==.Honey:BAAALgAECgEJAQAAAA==.',
Hu='Hurtforsqurt:BAAALgADCgEJAQAAAA==.',
Id='Idiotdk:BAABLgAFFH8GAAIKAAIJsQ8m2ACJAAAKAAIJsQ8m2ACJAAAAAA==.',
Il='Illyria:BAAALgADCgUJAQAAAA==.',
Ir='Ironheart:BAABLgAECn8gAAIBAAgJ0BTnYACvAQABAAgJ0BTnYACvAQAAAA==.',
Ja='Jackmerious:BAABLgAECn8eAAICAAgJdBLOdgCMAQACAAgJdBLOdgCMAQAAAA==.Jadefire:BAAALgAECgIJAQAAAA==.Jasnah:BAABLgAECn8yAAIDAAkJNxbTHAAHAgADAAkJNxbTHAAHAgAAAA==.',
Je='Jefry:BAAALgADCgYJBgAAAA==.Jermomu:BAAALgAECgQJBQAAAA==.',
Ji='Jinai:BAABLgAECn8UAAIOAAYJbRNxQQBoAQAOAAYJbRNxQQBoAQABLgAECggJGwAHAJUbAA==.',
Jo='Johnnysalami:BAAALgADCgQJBAAAAA==.',
Ju='Julita:BAAALgAECgQJBQAAAA==.',
Ka='Kaggar:BAAALgAFFAEJAQAAAA==.Karadesh:BAABLgAFFH8NAAIPAAMJaRsmAwDkAAAPAAMJaRsmAwDkAAAAAA==.',
Ke='Keytosuccess:BAAALgAECgUJCQAAAA==.',
Ki='Killwhat:BAACLgAFFH8bAAMCAAUJYh7NJgA9AQACAAUJYh7NJgA9AQAQAAEJCAPvBwA4AAAuAAQKf0EAAgIACQkJJJQLABwDAAIACQkJJJQLABwDAAAA.',
Kl='Klint:BAABLgAFFH8IAAIKAAMJvQVPugC0AAAKAAMJvQVPugC0AAAAAA==.',
Ko='Korthyn:BAABLgAECn8eAAQRAAkJgR3iBQD6AQARAAkJgR3iBQD6AQASAAQJpBKkIADvAAATAAEJhhMlkgA3AAAAAA==.',
Ku='Kurnoth:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.',
Lo='Lothus:BAAALgADCgMJAwAAAA==.',
Ma='Magely:BAAALgAECgEJAQAAAA==.',
Me='Merkules:BAAALgAECgYJDAAAAA==.',
Mo='Moxie:BAACLgAFFH8nAAIUAAkJ+h25BwCyAgAUAAkJ+h25BwCyAgAuAAQKfzAAAxQACQkBJL8CAEkDABQACQkBJL8CAEkDABUABglyFoEIAEYBAAAA.',
Ms='Msdranderson:BAABLgAECn80AAIWAAkJJAn5OwAFAQAWAAkJJAn5OwAFAQAAAA==.',
Na='Natureheart:BAAALgAFFAEJAQAAAA==.',
Ne='Nero:BAAALgAECgUJCwABLgAECggJGwAHAJUbAA==.',
Ni='Nipps:BAAALgADCgQJCgAAAA==.',
No='Nori:BAABLgAFFH8FAAIXAAMJUgeVOQCRAAAXAAMJUgeVOQCRAAABLgAFFAkJQgACAAwlAA==.',
Ob='Obsidial:BAAALgADCgcJBgAAAA==.',
Od='Odóyle:BAAALgAFFAEJAQAAAA==.',
On='Onatoe:BAAALgAECgMJAwAAAA==.',
Oo='Oo:BAAALgAECgUJBQAAAA==.',
Op='Op:BAAALgADCgcJAgAAAA==.',
Or='Orius:BAAALgAECgMJBAAAAA==.',
Pa='Parsimony:BAAALgADCgUJBQAAAA==.',
Pe='Peaches:BAAALgAECgUJBQAAAA==.Pestilent:BAAALgAECgMJAwAAAA==.',
Po='Poj:BAAALgAECgMJBgAAAA==.Pojins:BAAALgAECgIJAgAAAA==.',
Pr='Pratt:BAAALgADCgcJBwAAAA==.',
Pu='Purple:BAABLgAECn8wAAIBAAkJ1x1yIwB4AgABAAkJ1x1yIwB4AgAAAA==.',
Ra='Raviel:BAAALgADCgQJBAAAAA==.',
Re='Regret:BAABLgAECn8XAAIJAAcJsCIXEgBHAgAJAAcJsCIXEgBHAgABLgAFFAgJHwAJALcaAA==.',
Ro='Rogué:BAAALgAECgMJAwAAAA==.',
Ru='Rueal:BAAALgADCgEJAQAAAA==.Rukar:BAAALgAECgQJCgAAAA==.',
Sa='Sabra:BAAALgAECgQJBgABLgAECgUJCgAGAAAAAA==.Saia:BAAALgAECgUJEQAAAA==.Samanosuke:BAAALgAECgEJAQAAAA==.Sawaruna:BAAALgADCgYJBgAAAA==.',
Se='Seleren:BAAALgADCgEJAQAAAA==.Serapphina:BAAALgAECgIJAgAAAA==.',
Si='Silverfangz:BAAALgADCgEJAQAAAA==.Sinless:BAAALgAECgQJDAAAAA==.',
Sm='Small:BAABLgAFFH8FAAIYAAMJ8B+lEAAWAQAYAAMJ8B+lEAAWAQAAAA==.',
Sn='Snipedbaby:BAAALgAECgMJAgAAAA==.',
Su='Superfist:BAACLgAFFH8ZAAQZAAgJqhViBABPAQAZAAUJDxxiBABPAQAOAAEJ7RCpXABIAAAEAAIJPwVUIgA7AAAuAAQKfyYAAxkACAnIIkMGABwDABkACAnIIkMGABwDAA4ABwmUHhEXAGECAAAA.',
['Så']='Såbra:BAAALgADCgEJAQAAAA==.',
Ta='Tavitusk:BAAALgAECgcJDQABLgAECgkJFwABAFAbAA==.Tayonhands:BAABLgAECn8WAAIBAAYJjxTPmwA+AQABAAYJjxTPmwA+AQABLgAECgkJMgADADcWAA==.',
Te='Tehgimp:BAABLgAECn86AAIaAAkJLg1qEQCdAQAaAAkJLg1qEQCdAQAAAA==.',
Ti='Tinder:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgMJAwAAAA==.',
Tr='Trakanon:BAABLgAECn8uAAQRAAgJchyYBgDjAQARAAgJchyYBgDjAQATAAUJQhNMPAD9AAASAAYJEgoTIQDrAAAAAA==.Treezus:BAAALgAECgEJAQAAAA==.Trouthunter:BAAALgAECggJDwAAAA==.',
Ts='Tsuyoikuma:BAAALgADCgkJGQAAAA==.',
Ug='Ugornargol:BAAALgADCgEJAQABLgAECgcJBwAGAAAAAA==.',
Uo='Uobmoblin:BAAALgAECgUJBQABLgAFFAQJEgAFANEUAA==.',
Uu='Uu:BAABLgAECn8ZAAIJAAkJYhzVDwBkAgAJAAkJYhzVDwBkAgAAAA==.',
Uw='Uwu:BAAALgAFFAEJAQAAAA==.',
Va='Valicore:BAABLgAECn8aAAIXAAgJNxOYQgDqAQAXAAgJNxOYQgDqAQAAAA==.Vansftw:BAAALgAECggJDwAAAA==.Varithak:BAAALgADCgYJBgAAAA==.',
Ve='Vent:BAAALgAECgQJBQAAAA==.Vestrevus:BAABLgAECn8UAAIFAAUJHgXSEwBaAAAFAAUJHgXSEwBaAAAAAA==.',
Vg='Vginny:BAAALgADCgUJBQAAAA==.',
Vi='Violetta:BAABLgAECn8lAAIOAAYJiyGHBgDWAQAOAAYJiyGHBgDWAQABLgAECgQJBQAGAAAAAA==.Viroz:BAAALgADCgYJBgAAAA==.',
Vo='Vonix:BAAALgADCgMJAwAAAA==.Vorcthal:BAACLgAFFH8NAAIUAAMJzR2OFADxAAAUAAMJzR2OFADxAAAuAAQKfysAAxQACQmMHY8HAAEDABQACQmMHY8HAAEDABUACAlEDeMzAEkBAAAA.Voren:BAAALgADCgQJBAAAAA==.Vorenormu:BAABLgAECn8eAAQTAAgJixPoLACJAQATAAgJ3BLoLACJAQARAAIJ4hCSNABwAAASAAMJaQvZDABHAAABLgAFFAMJDQAUAM0dAA==.',
Vy='Vyre:BAAALgAECgQJBgABLgAECggJHgACAHQSAA==.',
Wa='Waste:BAAALgAECgIJAgAAAA==.',
Wi='Wingzero:BAAALgAECgIJAgAAAA==.',
Xe='Xero:BAAALgADCgYJCwAAAA==.',
Xo='Xoloteku:BAAALgADCgIJAgAAAA==.',
Xx='Xxz:BAAALgAECgcJBgAAAA==.',
Ya='Yaoi:BAAALgAECgYJCgABLgAECgQJBQAGAAAAAA==.',
Za='Zacharius:BAAALgAECgIJAgAAAA==.Zaelor:BAAALgAECgcJBgABLgAECgkJGgAXADcTAA==.Zandros:BAAALgAECgcJBwAAAA==.Zantt:BAAALgAECgEJAQAAAA==.',
Ze='Zen:BAAALgADCgQJBAABLgAECggJCQAGAAAAAA==.Zergdh:BAAALgADCgcJBwABLgAFFAgJKwAEAGsmAA==.Zergkin:BAAALgAECggJCAABLgAFFAgJKwAEAGsmAA==.',
Zu='Zuggernautt:BAAALgAECgcJDAAAAA==.Zuryea:BAAALgAECgUJCgAAAA==.',
['Zü']='Zülly:BAAALgADCgcJCQAAAA==.',
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
