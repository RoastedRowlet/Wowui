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

local lookup = {'Shaman-Elemental','Priest-Shadow','Paladin-Holy','Unknown-Unknown','Mage-Arcane','Shaman-Enhancement','Hunter-BeastMastery','DemonHunter-Devourer','Mage-Frost','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Assassination','Paladin-Retribution','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Warlock-Demonology','Monk-Windwalker','Paladin-Protection','Shaman-Restoration','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Blood',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Aberforthd:BAAANQAECgEJAQAAAA==.',
Ac='Acorn:BAABNQAECoEZAAIBAAcKPh2ELABeAgABAAcKPh2ELABeAgAAAA==.',
Ad='Aditu:BAAANQAECgQJBwAAAA==.',
Ae='Aetheris:BAAANQAECgUJDwAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQAECgMJAwAAAA==.',
Ai='Airent:BAAANQAECgEIAQAAAA==.',
Al='Alaestel:BAAANQAECgYJDgAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIAgAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Angina:BAAANQADCgQIBgAAAA==.Annarcis:BAAANQADCggIFAAAAA==.Antiman:BAAANQAECgEJAQAAAA==.Anäster:BAABNQAECoEhAAICAAgKmBZPFABcAgACAAgKmBZPFABcAgAAAA==.',
Ap='Aplcyder:BAAANQAECgYJDgAAAA==.Apocryphea:BAAANQAECgQIBAAAAA==.',
Ar='Arachnid:BAAANQAECgQICgAAAA==.Aradalon:BAABNQAECoEgAAIDAAkKyiBOBwBmAwADAAkKyiBOBwBmAwAAAA==.Aratyn:BAAANQAECgUIBQAAAA==.',
As='Astranacht:BAAANQAECgYJDwAAAA==.',
Au='Auntjemimma:BAAANQAECgUIBgABNQAECgUICgAEAAAAAA==.',
Ba='Backhawk:BAAANQAECgEJAQAAAA==.Baerrn:BAAANQAECgQJBgAAAA==.Baricia:BAABNQAECoEYAAIFAAgKtQr4oQDEAQAFAAgKtQr4oQDEAQAAAA==.Barrin:BAAANQAECgUICQAAAA==.Bawnchu:BAAANQADCgMIBQAAAA==.',
Be='Beardad:BAAANQADCgcIBwAAAA==.Beastmaster:BAAANQAECgcIEAAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQADCgUICQAAAA==.Bentlymage:BAAANQAECgcJEQAAAA==.',
Bi='Bissafiyah:BAACNQAFFIEPAAIGAAYK9R01AABjAgAGAAYK9R01AABjAgA1AAQKgSUAAgYACQojJX8BAJEDAAYACQojJX8BAJEDAAAA.Bittertea:BAAANQAECgMJAwAAAA==.',
Bl='Blakdeath:BAAANQAECgUIBwAAAA==.Blargghh:BAAANQADCgIIAgAAAA==.Bloodgon:BAAANQAECgQJBAAAAA==.',
Bo='Bobthedemon:BAAANQAECgIJAwAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Boyakasha:BAAANQAECgEIAQAAAA==.',
Br='Brayne:BAAANQAECgEJAQAAAA==.Brewsome:BAAANQAECgcIEAAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAAANQAECgUJDAAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgUJDAAEAAAAAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggJCAAAAA==.',
Ca='Calbee:BAAANQADCgEIAQAAAA==.Candorite:BAAANQAECgUJBwAAAA==.Capita:BAAANQAECgQIBwAAAA==.Carsinegan:BAAANQADCggJHQAAAA==.Cassica:BAAANQAECgYIEAAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAAANQAECgMJAwAAAA==.Chillylilly:BAAANQAECggICgAAAA==.Chummie:BAAANQAECgcJDAAAAA==.',
Ci='Ciandoril:BAAANQADCgQIBAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIDQABNQADCgMIAwAEAAAAAA==.',
Cr='Crimsondeath:BAAANQAECgEIAQAAAA==.Crylecks:BAAANQADCgUJCAAAAA==.',
Cy='Cylu:BAAANQADCggICwAAAA==.Cyprus:BAAANQADCggICwAAAA==.',
Da='Daelric:BAAANQADCgIIAgAAAA==.Daender:BAABNQAECoEVAAIHAAgK/yFtEwAJAwAHAAgK/yFtEwAJAwAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Daevie:BAAANQAECgQICQAAAA==.Dairydemon:BAABNQAECoEXAAIIAAgKYQGHOgABAQAIAAgKYQGHOgABAQAAAA==.Damageus:BAABNQAECoEWAAMFAAcKiSMmXgBzAgAFAAYK7yMmXgBzAgAJAAEKJSG4IwBiAAAAAA==.Damworg:BAAANQAECgMJAwAAAA==.Dar:BAABNQAECoEWAAIHAAgKuBWrOgBLAgAHAAgKuBWrOgBLAgAAAA==.Darcside:BAAANQAECgEIAQAAAA==.Daritar:BAEANQAECgcIBwAAAA==.Darkburtus:BAAANQAECgUJDgAAAA==.Darkfeatherr:BAAANQADCggIHAAAAA==.Darkxwraith:BAAANQAECgUJDgAAAA==.Datsombeech:BAAANQAECgUJCwAAAA==.',
De='Defhammer:BAAANQABCggJCgAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECoEZAAMKAAgKDRiTBwDuAQAIAAgKlQ4ZHwACAgAKAAYKoxyTBwDuAQAAAA==.',
Di='Dianoia:BAAANQAECgIJAgABNQAFFAMIBAALAFwPAA==.',
Dk='Dkanabiss:BAAANQADCgYIBgAAAA==.',
Do='Docoo:BAAANQAECgYJCwAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECgQIBAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAECgkJHAAIAD8iAA==.Drewserk:BAAANQAECgUJCwAAAA==.Driten:BAAANQAECgYJEQAAAA==.Drpiscisphd:BAAANQADCgEIAQABNQAECgkJJgAMAAogAA==.Drsaltyballz:BAAANQAECgIJAgAAAA==.Drspoon:BAAANQAECgUJCQAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgQIBgAAAA==.',
Du='Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAAANQAECgUIBQABNQAECgUIDQAEAAAAAA==.Duffunha:BAAANQAECgUIDQAAAA==.',
Dy='Dyre:BAAANQAECgEJAQAAAA==.Dyslexic:BAAANQAECgQIBQABNQAECgkJFgANAKsUAA==.Dyspepsia:BAABNQAECoEWAAINAAkKqxQ/PwBVAgANAAkKqxQ/PwBVAgAAAA==.',
['Dõ']='Dõngus:BAAANQADCgYIBgAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCgYJDgAAAA==.',
El='Eleaornu:BAAANQAECgUJCgAAAA==.Elimee:BAABNQAECoEoAAIFAAkKrSNDDgCGAwAFAAkKrSNDDgCGAwAAAA==.Elvenbane:BAAANQAECgMJAwAAAA==.',
Em='Emart:BAAANQAECgEJAQAAAA==.',
Er='Erayna:BAAANQAECgUIBgAAAA==.',
Es='Essence:BAAANQAECgEJAQAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwAEAAAAAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgEJAQAAAA==.Fayedra:BAAANQAECgUIBwAAAA==.',
Fe='Feenii:BAAANQAECgUIDQAAAA==.',
Fi='Fizzlelich:BAAANQADCgcJEAAAAA==.',
Fo='Foxdeer:BAAANQAECgUJBQAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgYJCgAEAAAAAA==.',
Fu='Fungies:BAAANQAECgYJEQAAAA==.Furybest:BAAANQADCgUIBQAAAA==.Furyrage:BAAANQADCgMIAwAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgMIBAAAAA==.',
Gi='Gimiltockel:BAAANQADCgMIAwAAAA==.Giramar:BAAANQADCggIDQAAAA==.',
Go='Gojo:BAAANQAECgEIAwAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCgYIEAAAAA==.Grimrox:BAAANQAECgQJCAAAAA==.Grombo:BAAANQADCgYIAwAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECggIHgADAPgbAA==.',
He='Healingwave:BAAANQADCgYJBgAAAA==.Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUIBwAAAA==.Hexbox:BAAANQAECgUJDQAAAA==.',
Hi='Himawarí:BAAANQAECgUIBwAAAA==.',
Ho='Hoffmin:BAABNQAECoEYAAMIAAkK6BhwEgCWAgAIAAgKgRpwEgCWAgAOAAEKGgwiXgA/AAAAAA==.Holemeister:BAAANQAECgYJEgAAAA==.Holyamin:BAAANQAECgEJAQAAAA==.Holymann:BAAANQADCgcIFwAAAA==.Holyschnikey:BAAANQAECgUICgAAAA==.Holyz:BAAANQAECgQJCAAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQADCgYIBgABNQAECggJFQAHAP8hAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.',
Hy='Hypnototem:BAAANQAECgEJAQAAAA==.',
['Hè']='Hèimdall:BAAANQAECgUJCgAAAA==.',
['Hí']='Hílthaen:BAAANQAECgUJCwAAAA==.',
Ic='Icehead:BAAANQADCgQIBAAAAA==.Ichigokisu:BAAANQADCgQIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAAANQAECgYIDwAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAAANQADCggICAABNQAECgUJBwAEAAAAAA==.',
Ja='Jahan:BAABNQAECoEYAAMPAAgKLh/0AgCIAgAPAAcKXR70AgCIAgAQAAUKHhvDSgCzAQABNQAECgQIBAAEAAAAAA==.Jamie:BAAANQAECgYICgABNQAFFAQICAARAN0fAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECoEWAAISAAcKxh7mEABpAgASAAcKxh7mEABpAgAAAA==.Jerith:BAAANQAECgUIDAAAAA==.Jessilyn:BAAANQADCgMIBQAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.',
Jo='Jord:BAAANQADCgUIBQAAAA==.',
Ju='Jubellina:BAAANQAECgYIEgAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.Jud:BAAANQAECgUJCgAAAA==.',
['Jà']='Jàzz:BAAANQADCgYJFgAAAA==.',
Ka='Kaelora:BAAANQADCgYJCQAAAA==.Kaerei:BAAANQADCgQJBAAAAA==.Kaleb:BAEBNQAECoEcAAIOAAkK9SEvBQB1AwAOAAkK9SEvBQB1AwAAAA==.Kalferno:BAAANQAECgEIAQAAAA==.Kayotica:BAAANQADCgcIEgAAAA==.',
Kh='Khallock:BAAANQAECgQIBQAAAA==.',
Ki='Kiemen:BAAANQAECgYJCwAAAA==.Killko:BAAANQAECgcJEwAAAA==.Kirisen:BAAANQAECgEIAQAAAA==.',
Kn='Knardan:BAAANQAECgUJCwAAAA==.',
Ko='Kotanx:BAAANQADCggIDwAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAAANQAECgUIBwAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAABNQAECoEVAAITAAgKeB9lCAC7AgATAAgKeB9lCAC7AgAAAA==.Lasalghoul:BAAANQAECgQJBQAAAA==.Lassyn:BAAANQABCgMIBQAAAA==.',
Le='Legend:BAAANQAFFAEJAQAAAA==.Len:BAABNQAECoEWAAMUAAgK8A4ZSwC8AQAUAAgK8A4ZSwC8AQABAAMKUQqxrACeAAAAAA==.Leoñidas:BAAANQAECgEIAQAAAA==.',
Li='Lian:BAAANQADCggJFAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAAANQAECgYJEQAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAAANQADCgcIEQAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQADCgQJBAAAAA==.Lilmoo:BAAANQAECgEJAQAAAA==.Lilpump:BAAANQAECgQJBwABNQAECgUJCQAEAAAAAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQADCgEIAQABNQAECgUIDQAEAAAAAA==.Linkmônk:BAAANQADCgcICgABNQAECgUIDQAEAAAAAA==.',
Lo='Lodise:BAAANQAECgQICAAAAA==.Lorzz:BAABNQAECoEcAAIQAAgKjhyuHwCPAgAQAAgKjhyuHwCPAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAAANQAECgUIDQAAAA==.Ludlow:BAAANQADCgMIAwABNQAECgYIDwAEAAAAAA==.Lunatick:BAAANQADCggICAAAAA==.Lurim:BAAANQAECgUJDAAAAA==.Lushy:BAAANQAECgUICQAAAA==.',
Ly='Lylindara:BAAANQAECgUJBwAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAAANQAECgUJDgABNQADCgMIAwAEAAAAAA==.Mageskin:BAAANQAECgEJAgAAAA==.Maladaptive:BAAANQADCgYJCgAAAA==.Manerva:BAAANQADCgYJEQAAAA==.Maximumhonk:BAAANQAECgQICAAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQADCgYICAAAAA==.',
Me='Mekkadaddy:BAAANQAECgQJBAAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAAANQAECgQJBwAAAA==.Mercus:BAAANQAECgUJCAAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAAANQAECgIIAgAAAA==.',
Mi='Mindplague:BAAANQAECgQICgAAAA==.Minipincin:BAAANQADCgUJDQAAAA==.Minmzey:BAAANQAECgIJAgAAAA==.Miroslava:BAAANQADCgEIAQAAAA==.Missfire:BAAANQADCggICgABNQADCggICwAEAAAAAA==.',
Mo='Moggle:BAAANQAECgMJAwAAAA==.Mondazi:BAAANQAECgcIEQAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Mozarta:BAAANQABCggJDQAAAA==.',
Ms='Msmanalow:BAAANQADCgEIAQABNQADCggICwAEAAAAAA==.',
My='Mycen:BAAANQAECgcJCgAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQADCgcIDgAAAA==.',
Na='Nardena:BAAANQADCgYJFgAAAA==.Narz:BAAANQAECgYJEQAAAA==.',
Ne='Necronomikon:BAAANQADCgYICgAAAA==.Neromoo:BAAANQAECgUIDQABNQADCgUIBQAEAAAAAA==.Neruphuyt:BAAANQAECgUIDQAAAA==.',
Ni='Niath:BAAANQADCgcJHAAAAA==.Nightheal:BAAANQABCgQIBQABNQAECgYJCwAEAAAAAA==.Nightsniper:BAAANQAECgEIAQABNQAECgYJCwAEAAAAAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAAANQAECgUJCgAAAA==.Notpillows:BAAANQADCggIDQAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAgAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgUICQAEAAAAAA==.',
Ok='Okioni:BAAANQAECgQIBAAAAA==.',
Ol='Olgon:BAABNQAECoEaAAIHAAgK5xD1QgAtAgAHAAgK5xD1QgAtAgAAAA==.',
Op='Oprhawinfury:BAAANQAECgUJCAAAAA==.',
Or='Orgodemir:BAAANQAECgUIBwAAAA==.Orhamin:BAAANQADCgYICwAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQADCgQIAgAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECoEZAAIRAAcK6xB4UgDXAQARAAcK6xB4UgDXAQAAAA==.Parsie:BAAANQADCgcIBwAAAA==.Pathibas:BAAANQADCggIDQABNQAECgUIDQAEAAAAAA==.Pattycakes:BAAANQAECgQICQAAAA==.',
Ph='Pherocious:BAAANQAECgIJAgAAAA==.',
Pi='Pinktuesday:BAAANQADCgYJBgAAAA==.Pixeleen:BAABNQAECoEkAAMHAAkKMyOZDABBAwAHAAkKMyOZDABBAwAVAAUK5gvxMQAhAQAAAA==.',
Pl='Plexy:BAABNQAECoEdAAMQAAkKYSC1DAAcAwAQAAkKuh+1DAAcAwAPAAcK8hlFBQD+AQAAAA==.',
Po='Pokitz:BAAANQAECgEIAgAAAA==.',
Pr='Primordinor:BAAANQAECgUICgAAAA==.Probnotalive:BAAANQAECgQICQAAAA==.Probnoturmom:BAAANQAECggIEgAAAA==.',
Qu='Quacko:BAAANQABCgIIAgABNQAECgUJDAAEAAAAAA==.',
Ra='Rakan:BAAANQAECgcIDgAAAA==.Rallick:BAAANQAECgcJEAAAAA==.Ranì:BAABNQAECoEVAAIWAAgKVREtDQDLAQAWAAgKVREtDQDLAQAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendwee:BAAANQAECgYIEAAAAA==.Retiredaggro:BAAANQAECgQJBQAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQAECgIJAgAAAA==.',
Rh='Rhaella:BAAANQABCgIIAgAAAA==.',
Ri='Ricflairion:BAAANQAECgUICQAAAA==.Rill:BAAANQADCggICAAAAA==.',
Ro='Rodcet:BAABNQAECoEVAAINAAgK0SOsEwA6AwANAAgK0SOsEwA6AwAAAA==.Roflbubble:BAAANQAECgUJCwAAAA==.Rognan:BAAANQADCgMIAwAAAA==.Roku:BAAANQADCgcIEgAAAA==.Ronkin:BAAANQADCgYJEQAAAA==.Rookgue:BAABNQAECoEWAAIMAAcKWg42IgDIAQAMAAcKWg42IgDIAQAAAA==.Rookoker:BAAANQAECgMJBAAAAA==.Rorygazer:BAAANQAECgMJAwAAAA==.Rosmerta:BAAANQADCgEIAQAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQAECgIIAgABNQAECgQIBQAEAAAAAA==.Rossperot:BAABNQAECoEbAAIXAAcKdx5cHwBpAgAXAAcKdx5cHwBpAgAAAA==.',
Ry='Ryk:BAAANQADCggICAAAAA==.',
Sa='Saarin:BAAANQADCgQIBAAAAA==.Saelara:BAAANQAECgEJAQAAAA==.Sairal:BAAANQAECgYJDgAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAABNQAECoEiAAINAAkKKx1jNQCAAgANAAkKKx1jNQCAAgAAAA==.Sawlty:BAAANQAECgYJCgAAAA==.Saynar:BAAANQAECgUIDQAAAA==.',
Sc='Scattered:BAAANQAECgYJCgAAAA==.Schecter:BAABNQAECoEYAAMUAAcKJyO+GQC9AgAUAAcKJyO+GQC9AgABAAEKCxiUzgBDAAAAAA==.Scintila:BAAANQADCgQIBAABNQAECgcIGQARAOsQAA==.Scooti:BAAANQADCggJEAABNQAECgQICAAEAAAAAA==.',
Se='Seba:BAABNQAECoEbAAIFAAgK5BZhbABNAgAFAAgK5BZhbABNAgAAAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAAANQAECgUIBwAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAAANQAECgQJBwAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shaggmz:BAAANQAECgEIAQAAAA==.Shinma:BAAANQAECgEIAQAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAAANQAECgEIAQAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAAANQAECgQJBwAAAA==.Sindiz:BAAANQAECgEIAQAAAA==.Siouxiesioux:BAAANQADCgUJCQAAAA==.',
Sk='Skoot:BAAANQAECgQICAAAAA==.',
Sl='Slugondeez:BAABNQAECoEeAAIDAAgK+BtCIACYAgADAAgK+BtCIACYAgAAAA==.',
Sm='Smitefist:BAAANQADCgIIAgABNQADCgYIBgAEAAAAAA==.',
Sn='Snkyturtle:BAABNQAECoEZAAIHAAgK4A0SUwD3AQAHAAgK4A0SUwD3AQAAAA==.Snuzzle:BAAANQAECgUJCQAAAA==.',
So='Sourmash:BAAANQABCgIIAgAAAA==.',
Sp='Spaghet:BAAANQAECgQICQAAAA==.Spillthetea:BAAANQADCggICQABNQAECgMJAwAEAAAAAA==.Spittoon:BAAANQADCgEJAQABNQADCgQJCAAEAAAAAA==.Sploot:BAAANQAECgUJCAAAAA==.',
Sr='Srasjet:BAAANQAECgEJAQAAAA==.',
Ss='Ssarmandok:BAAANQAECgMJAwAAAA==.',
St='Stabytha:BAAANQAECgIJAgAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQAECgYICgAAAA==.Stealthed:BAAANQAECgIJAQAAAA==.Stonegoddess:BAAANQADCgMJAwAAAA==.Stormcall:BAAANQADCggIIAAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQADCgcIBwAAAA==.',
Sw='Swiss:BAAANQAECgUIBwAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQADCgUICgAAAA==.',
Ta='Taliden:BAAANQADCggJDQAAAA==.Taraylda:BAAANQAECgMJAwAAAA==.Tazzwolfsong:BAAANQADCgEJAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAAANQAECgQJBgAAAA==.',
Tf='Tfirs:BAAANQAECgQJBwAAAA==.',
Th='Thehealczar:BAAANQAECgQJBAABNQAECgYJCwAEAAAAAA==.Theokoles:BAAANQADCgIIAgABNQADCgYIBgAEAAAAAA==.Thesenate:BAAANQADCggICAABNQAECgUIDQAEAAAAAA==.Thickblòód:BAAANQADCgEIAQAAAA==.Thorly:BAAANQADCgYIDQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.Tinn:BAAANQADCgYJBgAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAAANQAECgQIBQAAAA==.Treecloud:BAAANQAECgQICwAAAA==.Treferimore:BAAANQAECgEIAQAAAA==.Trevian:BAAANQAECgUIBwAAAA==.',
Tu='Tuluxxi:BAAANQAECgUIDQAAAA==.Tutter:BAAANQADCgcJFAAAAA==.',
Tw='Twopumpchump:BAAANQAECgUIBgAAAA==.',
Ug='Uglymancer:BAAANQAECgUIBwAAAA==.',
Uj='Ujimas:BAAANQAECgMJBgAAAA==.',
Ut='Uthodne:BAAANQADCgYIBgABNQAECgYIDwAEAAAAAA==.',
Va='Vampireshade:BAAANQAECgUJCwAAAA==.Vampirevoid:BAAANQADCgUJBQAAAA==.Vanililly:BAAANQAECgUJCQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgEIAQAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgEJAQAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAAANQAECgUJCgAAAA==.',
Vi='Vindict:BAAANQAECgEJAQAAAA==.Violette:BAAANQAECgMIBQAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAAANQAECgUIDQAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQAECgMJAwAAAA==.Wakancer:BAAANQAECgQJDQAAAA==.Wakataclysm:BAAANQAECgMJBgAAAA==.Walnut:BAAANQADCgEIAQABNQAECgcIGQABAD4dAA==.Warchylde:BAAANQABCggJFwAAAA==.Warolderoy:BAAANQAECgUIDQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.',
Wo='Woker:BAAANQADCggJDQABNQAECgUIDQAEAAAAAA==.Woogie:BAAANQAECgQIBwAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgcJDAAEAAAAAA==.',
Xa='Xader:BAAANQADCggJCAAAAA==.',
Xe='Xenna:BAAANQAECgUICgAAAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQADCggICAAAAA==.',
Ye='Yeoman:BAAANQAECgQIBgAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECgUIDAAAAQ==.',
Yu='Yunohealme:BAAANQAECgUICQAAAA==.Yunosmall:BAAANQADCgMJAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAABNQAECoEcAAMRAAgK/BhPSAD9AQARAAcKDRhPSAD9AQALAAMKLxIQNADOAAAAAA==.Zandre:BAAANQAECgYJCwAAAA==.Zarkir:BAABNQAECoEbAAIYAAgKmiB6EgDRAgAYAAgKmiB6EgDRAgAAAA==.',
Ze='Zelily:BAAANQAECgUJCwAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAAANQAECgUJCgABNQAECgYICwAEAAAAAA==.Zhiana:BAAANQAECgYJCAAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgUJDAAEAAAAAA==.',
Zu='Zulrich:BAAANQAECgUJBgAAAA==.',
Zv='Zvirax:BAAANQADCgYIFgAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQADCgMIAwABNQAECgIJAwAEAAAAAA==.',
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
