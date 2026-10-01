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

local lookup = {'Shaman-Elemental','Paladin-Retribution','Priest-Shadow','Druid-Restoration','Paladin-Holy','Druid-Balance','Mage-Arcane','Hunter-BeastMastery','Shaman-Enhancement','Monk-Mistweaver','Unknown-Unknown','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination','Hunter-Survival','DemonHunter-Havoc','Priest-Discipline','Monk-Windwalker','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Shaman-Restoration','Warrior-Fury','Hunter-Marksmanship','Warrior-Protection','Druid-Feral','DeathKnight-Blood',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Aberforthd:BAAANQAECgIIAwAAAA==.',
Ac='Acorn:BAABNQAECoEgAAIBAAgK9R+zHgDgAgABAAgK9R+zHgDgAgAAAA==.',
Ad='Aditu:BAAANQAECgUIDAAAAA==.',
Ae='Aetheris:BAAANQAECgUIDwAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQAECgMIBQAAAA==.',
Ai='Airent:BAAANQAECgEIAQAAAA==.',
Al='Alaestel:BAABNQAECoEYAAICAAgKbQlgkgCVAQACAAgKbQlgkgCVAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Angina:BAAANQADCgQIBgAAAA==.Annarcis:BAAANQADCggIFwAAAA==.Antiman:BAAANQAECgEJAQAAAA==.Anäster:BAABNQAECoEhAAIDAAgKmBbHGgAqAgADAAgKmBbHGgAqAgAAAA==.',
Ap='Aplcyder:BAABNQAECoEXAAIEAAgKKgh0KAB1AQAEAAgKKgh0KAB1AQAAAA==.Apocryphea:BAAANQAECgQIBAAAAA==.',
Ar='Arachnid:BAAANQAECgQIDQAAAA==.Aradalon:BAABNQAECoEoAAIFAAkKmyFZCQBhAwAFAAkKmyFZCQBhAwAAAA==.Aratyn:BAAANQAECgYICwAAAA==.',
As='Astranacht:BAABNQAECoEZAAIGAAcKIgs+SQByAQAGAAcKIgs+SQByAQAAAA==.',
Au='Auntjemimma:BAAANQAECgUICgAAAA==.',
Ba='Backhawk:BAAANQAECgEJAQAAAA==.Backsurgery:BAAANQAECgQICAABNQAECgkJHQABAOgiAA==.Baerrn:BAAANQAECgQICgAAAA==.Baricia:BAABNQAECoEeAAIHAAgKAwyhuwC9AQAHAAgKAwyhuwC9AQAAAA==.Barrin:BAAANQAECgUIDgAAAA==.Bawnchu:BAAANQADCgMIBwAAAA==.',
Be='Beardad:BAAANQADCgcIBwAAAA==.Beastmaster:BAABNQAECoEYAAIIAAgKCR4bJQDJAgAIAAgKCR4bJQDJAgAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQADCgUICQAAAA==.Bentlymage:BAABNQAECoEbAAIHAAkKFxs5PADvAgAHAAkKFxs5PADvAgAAAA==.',
Bi='Bissafiyah:BAACNQAFFIEVAAIJAAYKECJSAABxAgAJAAYKECJSAABxAgA1AAQKgScAAgkACQouJUMCAHsDAAkACQouJUMCAHsDAAAA.Bittertea:BAAANQAECgMIBQAAAA==.',
Bl='Blakdeath:BAAANQAECgYIDQAAAA==.Blargghh:BAAANQADCggICQAAAA==.Bloodgon:BAAANQAECgUICQAAAA==.Bloodpriests:BAAANQADCgEIAQAAAA==.',
Bo='Bobthedemon:BAAANQAECgIIAwAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Boyakasha:BAAANQAECgEIAQAAAA==.',
Br='Brayne:BAAANQAECgIIAQAAAA==.Brewsome:BAABNQAECoEaAAIKAAgKuR+5CADVAgAKAAgKuR+5CADVAgAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAAANQAECgYIEgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgYIEgALAAAAAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggIDgAAAA==.',
Ca='Calbee:BAAANQADCgQIBQAAAA==.Candorite:BAAANQAECgUJBwABNQAECgYIBgALAAAAAA==.Capcoms:BAAANQAECgQIBAABNQAECgcIGwAHAAkeAA==.Capita:BAAANQAECgUIDAAAAA==.Carsinegan:BAAANQAECgMIAwAAAA==.Cassica:BAABNQAECoEXAAMDAAcKbwz7KgB8AQADAAcKbwz7KgB8AQAMAAUK6RUWeQA/AQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAAANQAECgQIBgAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECoEXAAQNAAcKPBy1YQDjAQANAAYKLhy1YQDjAQAOAAIKKBX7SQCLAAAPAAEK4B3PHgBSAAAAAA==.',
Ci='Ciandoril:BAAANQADCgQIBAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwALAAAAAA==.',
Cr='Crazyeyes:BAAANQADCgcIBwABNQAECgYIEwALAAAAAA==.Crimsondeath:BAAANQAECgEIAQAAAA==.Crylecks:BAAANQADCgUJCAAAAA==.',
Cy='Cylu:BAAANQADCggICwAAAA==.Cyprus:BAAANQAECgEIAQAAAA==.',
Da='Daelric:BAAANQADCgIIAgAAAA==.Daender:BAABNQAECoEcAAIIAAgK/yFsHQDtAgAIAAgK/yFsHQDtAgAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Daevie:BAAANQAECgUIDgAAAA==.Dairydemon:BAABNQAECoEdAAIQAAgKtAFcPAATAQAQAAgKtAFcPAATAQAAAA==.Damageus:BAABNQAECoEdAAMHAAcK7yNicwBiAgAHAAYK7yNicwBiAgARAAEK7yP2KABpAAAAAA==.Damworg:BAAANQAECgMIBQAAAA==.Dar:BAABNQAECoEdAAIIAAgKyxUmTQA5AgAIAAgKyxUmTQA5AgAAAA==.Darcside:BAAANQAECgEIAQAAAA==.Daritar:BAEANQAECggIDwAAAA==.Darkburtus:BAAANQAECgUIEgAAAA==.Darkfeatherr:BAAANQAECgIIAgAAAA==.Darkxwraith:BAAANQAECgUIEwAAAA==.Datsombeech:BAAANQAECgYIEQAAAA==.',
De='Defhammer:BAAANQABCggIEAAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECoEfAAMSAAgKIho9CAAaAgASAAYKah89CAAaAgAQAAgKlQ6MJADnAQAAAA==.',
Di='Dianoia:BAAANQAECgIIAgABNQAFFAUICQAOAL8SAA==.',
Dk='Dkanabiss:BAAANQADCgYICgAAAA==.Dkinabox:BAAANQADCgEIAQAAAA==.',
Do='Docoo:BAAANQAECgcIEgAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECgQIBAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAFFAMIBwAQAIgSAA==.Drewserk:BAAANQAECgYIEQAAAA==.Driten:BAABNQAECoEbAAIHAAcKCR4cfwBGAgAHAAcKCR4cfwBGAgAAAA==.Drpiscisphd:BAAANQAECgEIAQABNQAECgkJKQATANEgAA==.Drsaltyballz:BAAANQAECgIJAgAAAA==.Drspoon:BAAANQAECgcIDwAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgQIBgAAAA==.',
Du='Ducat:BAAANQABCgQIBAAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAAANQAECgYICwABNQAECggIGQAUACcjAA==.Duffunha:BAABNQAECoEZAAIUAAgKJyMhAQBXAwAUAAgKJyMhAQBXAwAAAA==.',
Dy='Dyre:BAAANQAECgEJAQAAAA==.Dyslexic:BAAANQAECgQIBQABNQAECgkJGAACAKwUAA==.Dyspepsia:BAABNQAECoEYAAICAAkKrBRaVgBAAgACAAkKrBRaVgBAAgAAAA==.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECgcIBwALAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCgYIEwAAAA==.',
El='Eleaornu:BAAANQAECgYIEAAAAA==.Elimee:BAABNQAECoEuAAIHAAkK8yPCEwB1AwAHAAkK8yPCEwB1AwAAAA==.Elvenbane:BAAANQAECgMIBQAAAA==.',
Em='Emart:BAAANQAECgEIAQAAAA==.',
Er='Erayna:BAAANQAECgcIDQAAAA==.',
Es='Essence:BAAANQAECgMIAwAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwALAAAAAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgEJAQAAAA==.Fayedra:BAAANQAECgYIDQAAAA==.',
Fe='Feenii:BAABNQAECoEZAAIJAAgKWwdIFADNAQAJAAgKWwdIFADNAQAAAA==.',
Fi='Fizzlelich:BAAANQADCggIFQAAAA==.',
Fo='Foxdeer:BAAANQAECgUICgAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgcIEgALAAAAAA==.',
Fu='Fungies:BAABNQAECoEbAAINAAgKgBJaVQAKAgANAAgKgBJaVQAKAgAAAA==.Furybest:BAAANQADCgUIBQAAAA==.Furyrage:BAAANQADCgMIAwAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgMIBAAAAA==.',
Gi='Gimiltockel:BAAANQADCgMIAwAAAA==.Giramar:BAAANQAECgUIBQAAAA==.',
Go='Gojo:BAAANQAECgEIAwAAAA==.Goldeelock:BAAANQABCgUIBgAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCgYIEAAAAA==.Grimrox:BAAANQAECgQJCAAAAA==.Grombo:BAAANQAECgIIAgAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECggIIwAFAOAcAA==.',
He='Healingwave:BAAANQADCgYJBgAAAA==.Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUIBwAAAA==.Hexbox:BAAANQAECgUIEgAAAA==.',
Hi='Himawari:BAAANQAECgYIDQAAAA==.',
Ho='Hoffmin:BAABNQAECoEdAAMQAAkKpBxxDwDUAgAQAAgKtR5xDwDUAgAVAAEKGgxzcAA7AAAAAA==.Holemeister:BAABNQAECoEdAAICAAcKKSWRKwDeAgACAAcKKSWRKwDeAgAAAA==.Holyamin:BAAANQAECgEJAQAAAA==.Holymann:BAAANQADCggIIgAAAA==.Holyschnikey:BAAANQAECgUIDwAAAA==.Holyz:BAAANQAECgUIDQAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQADCgYIBgABNQAECggIHAAIAP8hAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCgQIBAAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAAANQAECgUIDgAAAA==.',
['Hí']='Hílthaen:BAAANQAECgYIEQAAAA==.',
Ic='Icehead:BAAANQADCgQIBAAAAA==.Ichigokisu:BAAANQADCgQIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECoEZAAIQAAgK+w4WJADrAQAQAAgK+w4WJADrAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAAANQAECgYIBgAAAA==.',
Ja='Jahan:BAABNQAECoEfAAMWAAgKwx+LAwCCAgAWAAcKXR6LAwCCAgAMAAcKbR5YLAB4AgABNQAECgQIBAALAAAAAA==.Jamie:BAAANQAECgYICgABNQAFFAUIDAANAEsiAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECoEdAAIXAAcKaSCpEQCPAgAXAAcKaSCpEQCPAgAAAA==.Jerith:BAABNQAECoEXAAIYAAYKWgWELAAnAQAYAAYKWgWELAAnAQAAAA==.Jerryy:BAAANQADCgEIAQABNQAECgEIAwALAAAAAA==.Jessilyn:BAAANQADCgMIBwAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQADCgEIAQAAAA==.',
Jo='Jord:BAAANQADCgUIBQAAAA==.',
Ju='Jubellina:BAABNQAECoEeAAIKAAgKPA2nGACbAQAKAAgKPA2nGACbAQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.Jud:BAAANQAECgcIEAAAAA==.',
['Jà']='Jàzz:BAAANQADCgYIHAAAAA==.',
Ka='Kaelora:BAAANQADCgYJCQAAAA==.Kaerei:BAAANQADCgQJBAAAAA==.Kaleb:BAEBNQAECoEkAAIVAAkKZiLTBgBqAwAVAAkKZiLTBgBqAwAAAA==.Kalferno:BAAANQAECgEIAQAAAA==.Kayotica:BAAANQADCgcIEgAAAA==.',
Kh='Khallock:BAAANQAECgQIBgAAAA==.',
Ki='Kiemen:BAAANQAECgYJCwAAAA==.Killko:BAABNQAECoEbAAMZAAgKgQ+TLgDHAQAZAAgKgQ+TLgDHAQAaAAIKpQrnnABaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAAANQAECgcIEQAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAAANQAECgYIDQAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAABNQAECoEcAAIbAAgKYSE6CADnAgAbAAgKYSE6CADnAgAAAA==.Lasalghoul:BAAANQAECgUICgAAAA==.Lassyn:BAAANQADCgMIAwABNQAECgUICgALAAAAAA==.',
Le='Legend:BAAANQAFFAEIAgAAAA==.Len:BAABNQAECoEeAAMcAAgKyg9yXgCdAQAcAAgKyg9yXgCdAQABAAQKiwtCsQDZAAAAAA==.Leoñidas:BAAANQAECgQIBgAAAA==.',
Li='Lian:BAAANQADCggJFAAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAAANQAECgYIEQAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAAANQAECgEIAQAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQADCgcIBwAAAA==.Lilmoo:BAAANQAECgIIAwAAAA==.Lilpump:BAAANQAECgQICQABNQAECgcIDwALAAAAAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQADCgEIAQABNQAECgcIEwALAAAAAA==.Linkmônk:BAAANQADCgcICgABNQAECgcIEwALAAAAAA==.',
Lo='Lodise:BAAANQAECgUIDQAAAA==.Lorzz:BAABNQAECoEiAAIMAAgK8h0BJACjAgAMAAgK8h0BJACjAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAAANQAECgUIEgAAAA==.Ludlow:BAAANQADCgMIAwABNQAECggIGwATAFAOAA==.Lurim:BAAANQAECgcIEgAAAA==.Lushy:BAAANQAECgUIDgAAAA==.',
Ly='Lylindara:BAAANQAECgYIDQAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAAANQAECgUIEwABNQADCgMIAwALAAAAAA==.Mageskin:BAAANQAECgEJAgAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCgYIFwAAAA==.Maximumhonk:BAAANQAECgUIDQAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQADCgYICAAAAA==.',
Me='Mekkadaddy:BAAANQAECgUICQAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAAANQAECgUIDAAAAA==.Mercus:BAAANQAECgYIDgAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAAANQAECgMIBwAAAA==.',
Mi='Mindplague:BAAANQAECgUIDwAAAA==.Minipincin:BAAANQADCgYIEQAAAA==.Minmzey:BAAANQAECgIJAgAAAA==.Miroslava:BAAANQADCgEIAQAAAA==.Missfire:BAAANQADCggICgABNQAECgEIAQALAAAAAA==.',
Mo='Moggle:BAAANQAECgMIBQAAAA==.Mondazi:BAABNQAECoEbAAMBAAgKSh10JQC1AgABAAgKSh10JQC1AgAcAAQKkxAysAC2AAAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQADCgQIBQAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.',
My='Mycen:BAAANQAECggIEAAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQADCggIFQAAAA==.',
Na='Nardena:BAAANQADCgYIHAAAAA==.Narz:BAABNQAECoEcAAIIAAcKqAlbhgCcAQAIAAcKqAlbhgCcAQAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Ne='Necronomikon:BAAANQAECgIIAgAAAA==.Neromoo:BAAANQAECgUIDQABNQAECgYIBgALAAAAAA==.Neruphuyt:BAAANQAECgYIEwAAAA==.',
Ni='Niath:BAAANQAECgMIAwAAAA==.Nightheal:BAAANQABCgQIBQABNQAECgcIEgALAAAAAA==.Nightsniper:BAAANQAECgEIAQABNQAECgcIEgALAAAAAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAAANQAECgYIDAAAAA==.Notpillows:BAAANQADCggIDgAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nò']='Nòvà:BAAANQADCgcIBwABNQAECgIIAQALAAAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgUIDgALAAAAAA==.',
Ok='Okioni:BAAANQAECgQIBAAAAA==.',
Ol='Olgon:BAABNQAECoEhAAIIAAgKCxLlTAA6AgAIAAgKCxLlTAA6AgAAAA==.',
Op='Oprhawinfury:BAAANQAECgYIDQAAAA==.',
Or='Orgodemir:BAAANQAECgYIDQAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQADCgQIAgAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Pallystorm:BAAANQABCgYICAABNQAECgUIBgALAAAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECoEfAAINAAgKEhGfVQAJAgANAAgKEhGfVQAJAgAAAA==.Parsie:BAAANQADCgcIBwAAAA==.Pathibas:BAAANQADCggIDQABNQAECggIGQAdACcbAA==.Pattycakes:BAAANQAECgYIDwAAAA==.',
Ph='Pherocious:BAAANQAECgIIAwAAAA==.',
Pi='Pinktuesday:BAAANQADCgYJBgAAAA==.Pixeleen:BAABNQAECoEnAAMIAAkKXCMeEwAqAwAIAAkKXCMeEwAqAwAeAAUK5guVOwANAQAAAA==.',
Pl='Plexy:BAABNQAECoEgAAMMAAkKYSDSEgAJAwAMAAkKuh/SEgAJAwAWAAcK8hlJBgDyAQAAAA==.',
Po='Pokitz:BAAANQAECgMIBQAAAA==.',
Pr='Primordinor:BAAANQAECgUIDwAAAA==.Probnotalive:BAAANQAECgUIDgAAAA==.Probnoturmom:BAABNQAECoEYAAIMAAgKFhzQHQDEAgAMAAgKFhzQHQDEAgAAAA==.',
Qu='Quacko:BAAANQABCgIIAgABNQAECgcIEgALAAAAAA==.',
Ra='Rakan:BAABNQAECoEXAAIfAAgKnRxACACDAgAfAAgKnRxACACDAgAAAA==.Rallick:BAABNQAECoEWAAIFAAcK9w0tYQCnAQAFAAcK9w0tYQCnAQAAAA==.Ranì:BAABNQAECoEcAAIfAAgKzxNEDwDYAQAfAAgKzxNEDwDYAQAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendwee:BAABNQAECoEbAAIgAAcK6h59BwCEAgAgAAcK6h59BwCEAgAAAA==.Retiredaggro:BAAANQAECgUICgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQAECgMIBAAAAA==.',
Rh='Rhaella:BAAANQABCgIIAgAAAA==.',
Ri='Ricflairion:BAAANQAECgUIDgAAAA==.Rill:BAAANQADCggICAAAAA==.',
Ro='Rodcet:BAABNQAECoEcAAICAAgKISRvGQA3AwACAAgKISRvGQA3AwAAAA==.Roflbubble:BAAANQAECgYIEQAAAA==.Rognan:BAAANQADCgMIAwAAAA==.Roku:BAAANQADCgcIGQAAAA==.Ronkin:BAAANQADCgYIFwAAAA==.Rookgue:BAABNQAECoEaAAITAAcKWg7MLgC0AQATAAcKWg7MLgC0AQAAAA==.Rookoker:BAAANQAECgUICQAAAA==.Rorygazer:BAAANQAECgMIBQAAAA==.Rosmerta:BAAANQADCgEIAQAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQAECgMIBAABNQAECgQIBQALAAAAAA==.Rossperot:BAABNQAECoEbAAIaAAcKdx7uLQAhAgAaAAcKdx7uLQAhAgAAAA==.',
Ry='Ryk:BAAANQADCggICAAAAA==.',
Sa='Saarin:BAAANQADCggIDAAAAA==.Saelara:BAAANQAECgQIBQAAAA==.Sairal:BAAANQAECgYJDgAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAABNQAECoErAAICAAkKuh8pHwAYAwACAAkKuh8pHwAYAwAAAA==.Sawlty:BAAANQAECgYIEAAAAA==.Saynar:BAABNQAECoEZAAMQAAgKGB0zEgCyAgAQAAgKDx0zEgCyAgASAAIKmhjpGwCPAAAAAA==.',
Sc='Scattered:BAAANQAECgcIEQAAAA==.Schecter:BAABNQAECoEYAAMcAAcKJyPxIACvAgAcAAcKJyPxIACvAgABAAEKCxhN7wBAAAAAAA==.Scintila:BAAANQADCgQIBAABNQAECggIHwANABIRAA==.Scooti:BAAANQADCggIEAABNQAECgQICAALAAAAAA==.',
Se='Seba:BAABNQAECoEkAAIHAAkK4Bn5TADCAgAHAAkK4Bn5TADCAgAAAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAAANQAECgYIDQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAAANQAECgUIDAAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shaggmz:BAAANQAECgEIAQAAAA==.Shinma:BAAANQAECgEIAQAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAAANQAECgEIAQAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAAANQAECgUIDAAAAA==.Sindiz:BAAANQAECgEIAQAAAA==.Siouxiesioux:BAAANQAECgQIBAAAAA==.',
Sk='Skoot:BAAANQAECgQICAAAAA==.',
Sl='Slugondeez:BAABNQAECoEjAAMFAAgK4Bz6JACkAgAFAAgK4Bz6JACkAgAbAAIKwx+cOwC6AAAAAA==.',
Sm='Smitefist:BAAANQADCgIIAgABNQAECgcIBwALAAAAAA==.',
Sn='Snkyturtle:BAABNQAECoEiAAIIAAgKbA9zWQAVAgAIAAgKbA9zWQAVAgAAAA==.Snowkim:BAEANQAECgQIBAAAAA==.Snuzzle:BAAANQAECgYIDwAAAA==.',
So='Sourmash:BAAANQABCgIIAgAAAA==.',
Sp='Spaghet:BAAANQAECgQICQAAAA==.Spillthetea:BAAANQADCggICQABNQAECgMIBQALAAAAAA==.Spittoon:BAAANQADCgEJAQABNQADCgUICgALAAAAAA==.Sploot:BAAANQAECgcIDgAAAA==.',
Sr='Srasjet:BAAANQAECgEIAQAAAA==.',
Ss='Ssarmandok:BAAANQAECgQIBAAAAA==.',
St='Stabytha:BAAANQAECgQIBAAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQAECgYICgAAAA==.Stealthed:BAAANQAECgIIAQAAAA==.Stonegoddess:BAAANQADCgMJAwAAAA==.Stormcall:BAAANQAECgIIAgAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQADCgcIBwAAAA==.',
Sw='Swiss:BAAANQAECgYIDQAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQADCgUICgAAAA==.',
Ta='Taliden:BAAANQAECgIIAgAAAA==.Tankinstine:BAAANQADCgEIAQAAAA==.Taraylda:BAAANQAECgMIBQAAAA==.Tazzwolfsong:BAAANQADCgEJAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAAANQAECgUICwAAAA==.',
Tf='Tfirs:BAAANQAECgQJBwABNQAFFAEIAQALAAAAAA==.',
Th='Thehealczar:BAAANQAECgcICwABNQAECgcIEgALAAAAAA==.Theokoles:BAAANQAECgcIBwAAAA==.Thesenate:BAAANQADCggIDwABNQAECggIGQAJAFsHAA==.Thickblòód:BAAANQADCgEIAQAAAA==.Thorly:BAAANQADCgYIDQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.Tinn:BAAANQADCgYIBgAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAAANQAECgQICAAAAA==.Treecloud:BAAANQAECgUIEAAAAA==.Treferimore:BAAANQAECgEIAQAAAA==.Trevian:BAAANQAECgYIDQAAAA==.',
Tu='Tuluxxi:BAABNQAECoEZAAMcAAgKgx/ASgDoAQAcAAYKsh7ASgDoAQABAAgKOQzuWADHAQAAAA==.Tutter:BAAANQADCgcIFAAAAA==.',
Tw='Twopumpchump:BAAANQAECgUIBgAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECgUIDwALAAAAAA==.',
Ug='Uglymancer:BAAANQAECgYIDQAAAA==.',
Uj='Ujimas:BAAANQAECgUIDAAAAA==.',
Ut='Uthodne:BAAANQADCgYIBgABNQAECggIGwATAFAOAA==.',
Va='Vampireshade:BAAANQAECgYIEQAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAAANQAECgYIDwAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgEIAQAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgEIAQAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAAANQAECgYIEAAAAA==.',
Vi='Vindict:BAAANQAECgEJAQAAAA==.Violette:BAAANQAECgMIBgAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAAANQAECgcIEwAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQAECgUIBwAAAA==.Wakancer:BAAANQAECgQIEAAAAA==.Wakataclysm:BAAANQAECgQICgAAAA==.Walnut:BAAANQADCgEIAQABNQAECggIIAABAPUfAA==.Warchylde:BAAANQADCgIIAgAAAA==.Warolderoy:BAABNQAECoEZAAMdAAgKJxuLCgDTAQAfAAYKJBp9DwDUAQAdAAYKxxmLCgDTAQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.',
Wo='Woker:BAAANQADCggIEQABNQAECggIGQAJAFsHAA==.Woogie:BAAANQAECgQIBwAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgcIFwANADwcAA==.',
Xa='Xader:BAAANQADCggJCAAAAA==.',
Xe='Xenna:BAAANQAECgUICgABNQAECgUICgALAAAAAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQADCggICAAAAA==.',
Ye='Yeoman:BAAANQAECgUICgAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECgUIDAAAAQ==.',
Yu='Yunohealme:BAAANQAECgUICgAAAA==.Yunosmall:BAAANQADCgMJAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAABNQAECoEjAAMNAAgKrBybKgCjAgANAAgKrBybKgCjAgAOAAMKLxKTOADKAAAAAA==.Zandre:BAAANQAECgcIEgAAAA==.Zarkir:BAABNQAECoEiAAIhAAgKoSGHEgDvAgAhAAgKoSGHEgDvAgAAAA==.',
Ze='Zelily:BAAANQAECgYIEQAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAAANQAECgYIEAABNQAECgYIDAALAAAAAA==.Zhiana:BAAANQAECgcIDwAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECgcIEgALAAAAAA==.',
Zu='Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirax:BAAANQADCgYIHAAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQADCgMIAwABNQAECgIJAwALAAAAAA==.',
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
