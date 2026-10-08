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

local lookup = {'Shaman-Elemental','Paladin-Retribution','Priest-Shadow','Druid-Restoration','Paladin-Holy','Druid-Balance','Mage-Arcane','Hunter-BeastMastery','Shaman-Enhancement','Monk-Mistweaver','DeathKnight-Blood','Unknown-Unknown','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Mage-Frost','Paladin-Protection','Warrior-Arms','DemonHunter-Vengeance','Rogue-Assassination','Hunter-Survival','DemonHunter-Havoc','Priest-Discipline','Monk-Windwalker','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Druid-Guardian','Warrior-Fury','Hunter-Marksmanship','Warrior-Protection','Druid-Feral','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Aberforthd:BAAANQAECgIIBQAAAA==.',
Ac='Acorn:BAABNQAECoEiAAIBAAgK9R8sJgDMAgABAAgK9R8sJgDMAgAAAA==.',
Ad='Aditu:BAAANQAECgUIEQAAAA==.',
Ae='Aetheris:BAAANQAECgcIEgAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQAECgQICQAAAA==.',
Ai='Airent:BAAANQAECgQIBQAAAA==.',
Al='Alaestel:BAABNQAECoEgAAICAAgKbAvpoACoAQACAAgKbAvpoACoAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Angina:BAAANQADCgUIBwAAAA==.Annarcis:BAAANQAECgQIBAAAAA==.Antiman:BAAANQAECgIIAwAAAA==.Anäster:BAABNQAECoEhAAIDAAgKmBa5HwAXAgADAAgKmBa5HwAXAgAAAA==.',
Ap='Aplcyder:BAABNQAECoEZAAIEAAgKmghMLwBrAQAEAAgKmghMLwBrAQAAAA==.Apocryphea:BAAANQAECgQIBAAAAA==.',
Ar='Arachnid:BAAANQAECgQIDQAAAA==.Aradalon:BAABNQAECoEoAAIFAAkKmyElDABZAwAFAAkKmyElDABZAwAAAA==.Aratyn:BAAANQAECgYIEQAAAA==.',
As='Astranacht:BAABNQAECoEgAAIGAAcKGBDrRwCgAQAGAAcKGBDrRwCgAQAAAA==.',
Au='Auntjemimma:BAAANQAECgYIDwAAAA==.',
Ax='Axa:BAAANQADCgUIBAAAAA==.',
Ba='Backhawk:BAAANQAECgEJAQAAAA==.Backsurgery:BAAANQAECgYIDwABNQAFFAIIBQABADIbAA==.Baerrn:BAAANQAECgUIDwAAAA==.Baricia:BAABNQAECoEhAAIHAAgKjAzZxADXAQAHAAgKjAzZxADXAQAAAA==.Barrin:BAAANQAECgYIEAAAAA==.Bawnchu:BAAANQADCgYIDQAAAA==.',
Be='Beardad:BAAANQADCgcIBwAAAA==.Beastmaster:BAABNQAECoEaAAIIAAkKwxwMIwDtAgAIAAkKwxwMIwDtAgAAAA==.Beefcakell:BAAANQADCgMIBAAAAA==.Belthar:BAAANQADCgUICQAAAA==.Bentlymage:BAABNQAECoEdAAIHAAkKFxs3SwDcAgAHAAkKFxs3SwDcAgAAAA==.',
Bi='Bissafiyah:BAACNQAFFIEbAAIJAAcKgyAWAADyAgAJAAcKgyAWAADyAgA1AAQKgSkAAgkACQpIJSQDAGgDAAkACQpIJSQDAGgDAAAA.Bittertea:BAAANQAECgQICQAAAA==.',
Bl='Blakdeath:BAAANQAECgYIEwAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAAANQAECgUIDgAAAA==.Bloodpriests:BAAANQADCggICQAAAA==.',
Bo='Bobthedemon:BAAANQAECgIIAwAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Boyakasha:BAAANQAECgQIBQAAAA==.',
Br='Brayne:BAAANQAECgMIAwAAAA==.Brewsome:BAABNQAECoEiAAIKAAgKSiCDCQDXAgAKAAgKSiCDCQDXAgAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECoEdAAILAAcKJR76LABGAgALAAcKJR76LABGAgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgcIHQALACUeAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQABCgYIBgAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBQAAAA==.Candorite:BAAANQAECgUJBwABNQAECgYIDAAMAAAAAA==.Capcoms:BAAANQAECgQIBwABNQAECgcIIQAHAH4eAA==.Capita:BAAANQAECgYIEwAAAA==.Carsinegan:BAAANQAECgMIBgAAAA==.Cassica:BAABNQAECoEcAAMDAAgKKRHlKgCnAQADAAcK6hDlKgCnAQANAAYKeBNGewBvAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQABCgYIBwAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAAANQAECgQICgAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECoEXAAQOAAcKPBwCdwDTAQAOAAYKLhwCdwDTAQAPAAIKKBUDTwCGAAAQAAEK4B38IgBPAAAAAA==.',
Ci='Ciandoril:BAAANQAECgQIBAAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwAMAAAAAA==.',
Cr='Crazyeyes:BAAANQAECgQIBAABNQAECgcIFwAGAMcKAA==.Crimsondeath:BAAANQAECgQIBQAAAA==.Crylecks:BAAANQADCgYIDgAAAA==.',
Cy='Cylu:BAAANQADCggICwAAAA==.Cyprus:BAAANQAECgUIBgAAAA==.',
Da='Daelric:BAAANQADCgIIAgAAAA==.Daender:BAABNQAECoEjAAIIAAgKAyKCJgDfAgAIAAgKAyKCJgDfAgAAAA==.Daenor:BAAANQADCgQIBAAAAA==.Daevie:BAABNQAECoEbAAIHAAgKAQWU9AB8AQAHAAgKAQWU9AB8AQAAAA==.Dairydemon:BAABNQAECoEfAAIRAAgK9gE9QQASAQARAAgK9gE9QQASAQAAAA==.Damageus:BAABNQAECoElAAMHAAgKqyGLaACYAgAHAAcKOSGLaACYAgASAAEKyySMLQBsAAAAAA==.Damworg:BAAANQAECgQICQAAAA==.Daniryl:BAEANQAECgEIAQABNQAECggIFwABABsSAA==.Dar:BAABNQAECoEkAAIIAAgKyxVrXwAuAgAIAAgKyxVrXwAuAgAAAA==.Darcside:BAAANQAECgMIBAAAAA==.Daritar:BAEBNQAECoEXAAIBAAgKGxJFVQD3AQABAAgKGxJFVQD3AQAAAA==.Darkburtus:BAABNQAECoEYAAIRAAYKvgS3QQAOAQARAAYKvgS3QQAOAQAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECoEdAAMTAAcKZBcHIQCvAQATAAYKnhkHIQCvAQACAAEKCAo0bwE3AAAAAA==.Datsombeech:BAABNQAECoEbAAIUAAcKzwcNugBbAQAUAAcKzwcNugBbAQAAAA==.',
De='Defhammer:BAAANQABCggIFAAAAA==.Deàdly:BAAANQADCgUJCgAAAA==.',
Dh='Dhaynk:BAABNQAECoEhAAMVAAgKrhycBwBdAgAVAAcKyh6cBwBdAgARAAgKlQ7AKADeAQAAAA==.',
Di='Dianoia:BAAANQAECgIIAgABNQAFFAUIDgAPAFIXAA==.Didamus:BAAANQABCgMIAwAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgIIAQAAAA==.',
Do='Docoo:BAABNQAECoEeAAILAAgKHiMUEgAIAwALAAgKHiMUEgAIAwAAAA==.Dogmeat:BAAANQABCgQICAAAAA==.Dominates:BAAANQAECgQIBAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAFFAMICgARACoYAA==.Drewserk:BAABNQAECoEbAAIUAAgKsw9yngCmAQAUAAgKsw9yngCmAQAAAA==.Driten:BAABNQAECoEhAAIHAAcKfh7TgwBeAgAHAAcKfh7TgwBeAgAAAA==.Drocsid:BAAANQAECgUIBQABNQAECggIIwACAHokAA==.Drpiscisphd:BAAANQAECgEIAQABNQAECgkJLAAWAFghAA==.Drsaltyballz:BAAANQAECgIJAgAAAA==.Drspoon:BAABNQAECoEZAAILAAgKdhFwRQDFAQALAAgKdhFwRQDFAQAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgQIBgAAAA==.',
Du='Ducat:BAAANQADCgMIAwAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAAANQAECgYIEQABNQAECggIIQAXACklAA==.Duffunha:BAABNQAECoEhAAIXAAgKKSUHAQByAwAXAAgKKSUHAQByAwAAAA==.',
Dy='Dyre:BAAANQAECgIIAwAAAA==.Dyslexic:BAAANQAECgQIBwABNQAFFAIIBgACADsJAA==.Dyspepsia:BAACNQAFFIEGAAICAAIKOwlXIQCEAAACAAIKOwlXIQCEAAA1AAQKgRkAAgIACQqsFBdtACkCAAIACQqsFBdtACkCAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDQAMAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQADCgYIGQAAAA==.',
Ei='Eirenn:BAAANQAECggICAAAAA==.',
El='Eleaornu:BAABNQAECoEaAAIFAAcKZRYTWQDsAQAFAAcKZRYTWQDsAQAAAA==.Elimee:BAABNQAECoEzAAIHAAkKIST2FQB1AwAHAAkKIST2FQB1AwAAAA==.Ellasia:BAAANQABCgMIAwAAAA==.Elvenbane:BAAANQAECgQICQAAAA==.',
Em='Emart:BAAANQAECgIIAwAAAA==.',
Er='Erayna:BAABNQAECoEYAAIEAAgKlAhGLwBrAQAEAAgKlAhGLwBrAQAAAA==.',
Es='Essence:BAAANQAECgcICgAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggICwAMAAAAAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgIIAwAAAA==.Fayedra:BAAANQAECgYIEwAAAA==.',
Fe='Feenii:BAABNQAECoEZAAIJAAgKWweOFwDBAQAJAAgKWweOFwDBAQAAAA==.',
Fi='Fizzlelich:BAAANQADCggIHwAAAA==.',
Fo='Foxdeer:BAAANQAECgUIDwAAAA==.Foxxmccloud:BAAANQADCgIJAgABNQAECgkJIQAGAB4eAA==.',
Fu='Fungies:BAABNQAECoEjAAIOAAgKdhR9XAAgAgAOAAgKdhR9XAAgAgAAAA==.Furybest:BAAANQADCgUIBQAAAA==.Furyrage:BAAANQADCgMIAwAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgMIAwAAAA==.Giramar:BAAANQAECgUICQAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAECggIIgABAPUfAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCgYIBwAAAA==.Gotchya:BAAANQABCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandest:BAAANQADCgQIBAAAAA==.Grantaire:BAAANQADCgYIEAAAAA==.Grimrox:BAAANQAECgYIDQAAAA==.Grombo:BAAANQAECgIIAgAAAA==.',
Ha='Haanit:BAAANQADCgIIAgAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECggIKAAFAAceAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgEIAQAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUIBwAAAA==.Hexbox:BAAANQAECgYIEwAAAA==.',
Hi='Himawari:BAAANQAECgYIEwAAAA==.',
Ho='Hoffmin:BAABNQAECoEjAAMRAAkKeh5cDgDzAgARAAgKxiBcDgDzAgAYAAEKGgytfwA7AAAAAA==.Holemeister:BAABNQAECoEjAAICAAgKcyM9JgASAwACAAgKcyM9JgASAwAAAA==.Holyamin:BAAANQAECgIIAwAAAA==.Holymann:BAAANQAECgQIBAAAAA==.Holyschnikey:BAABNQAECoEaAAIFAAcKGBGVcwCVAQAFAAcKGBGVcwCVAQAAAA==.Holyz:BAAANQAECgYIEwAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQADCgYIBgABNQAECggIIwAIAAMiAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCgQIBAAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAAANQAECgUIDgAAAA==.',
['Hí']='Hílthaen:BAABNQAECoEbAAINAAcKuxsJSwAcAgANAAcKuxsJSwAcAgAAAA==.',
Ic='Icehead:BAAANQADCgQIBAAAAA==.Ichigokisu:BAAANQADCgQIBAAAAA==.',
Ih='Ihavenobrain:BAAANQABCgIIAgAAAA==.',
Il='Illy:BAABNQAECoEZAAIRAAgK+w5JKADiAQARAAgK+w5JKADiAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAAANQAECgYIDAAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAABNQAECoEhAAMZAAgKwx8mBAB7AgAZAAcKXR4mBAB7AgANAAcKbR6cNwBnAgABNQAECgQIBAAMAAAAAA==.Jamie:BAAANQAECgYIEAABNQAFFAcIDgAOABwhAA==.Jarek:BAAANQABCgQIBAAAAA==.',
Je='Jegra:BAABNQAECoEfAAIaAAcKriA5FQCDAgAaAAcKriA5FQCDAgAAAA==.Jerith:BAABNQAECoEbAAMbAAcKOgjbLwAhAQAbAAYKWgXbLwAhAQAWAAQK2gnYYADhAAAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwAMAAAAAA==.Jessilyn:BAAANQADCgYIDQAAAA==.',
Ji='Jigari:BAAANQADCgcIDgAAAA==.Jinxed:BAAANQADCgEIAQAAAA==.',
Jo='Jord:BAAANQADCgUIBQAAAA==.',
Ju='Jubellina:BAABNQAECoElAAIKAAgK2Q3aGwCYAQAKAAgK2Q3aGwCYAQAAAA==.Jubîlee:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàzz:BAAANQADCgYIHAAAAA==.',
Ka='Kaelora:BAAANQADCgYJCQAAAA==.Kaerei:BAAANQADCgQJBAAAAA==.Kaleb:BAECNQAFFIEGAAIYAAMKNhz0DAADAQAYAAMKNhz0DAADAQA1AAQKgSwAAhgACQpCI7kFAIwDABgACQpCI7kFAIwDAAAA.Kalferno:BAAANQAECgIIAgAAAA==.Kayotica:BAAANQADCgcIEgAAAA==.',
Kh='Khallock:BAAANQAECgQICAAAAA==.',
Ki='Kiemen:BAAANQAECgYICwAAAA==.Killko:BAABNQAECoEbAAMcAAgKgQ/kNgC9AQAcAAgKgQ/kNgC9AQAdAAIKpQp7twBaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECoEYAAIIAAcKaB4nRwBxAgAIAAcKaB4nRwBxAgAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAAANQAECgYIEwAAAA==.',
Ky='Kyriea:BAAANQADCgYIBgAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAABNQAECoEjAAITAAgKZSIcCAAEAwATAAgKZSIcCAAEAwAAAA==.Lasalghoul:BAAANQAECgUICwAAAA==.Lassyn:BAAANQADCgMIAwABNQAECgUICwAMAAAAAA==.',
Le='Legend:BAAANQAFFAEIAgAAAA==.Len:BAABNQAECoEmAAMeAAgK4xMSWwDQAQAeAAgK4xMSWwDQAQABAAQK7AvuxwDUAAAAAA==.Leoñidas:BAAANQAECgQIBwAAAA==.',
Li='Lian:BAAANQAECgMIAwAAAA==.Lianse:BAAANQADCgYICwAAAA==.Liliara:BAABNQAECoEbAAIIAAgKYBT8VgBEAgAIAAgKYBT8VgBEAgAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAAANQAECgYIBwAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQADCgcIBwAAAA==.Lilmoo:BAAANQAECgMIBgAAAA==.Lilpump:BAAANQAECgQICQABNQAECggIGQALAHYRAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQADCgEIAQABNQAECggIHwAZAA8iAA==.Linkmônk:BAAANQADCgcICgABNQAECggIHwAZAA8iAA==.',
Lo='Lodise:BAABNQAECoEYAAIQAAcK8g7XCQC2AQAQAAcK8g7XCQC2AQAAAA==.Lorzz:BAABNQAECoElAAINAAkK0hy7HQDgAgANAAkK0hy7HQDgAgAAAA==.Loveydovey:BAAANQADCgIIAgAAAA==.',
Lu='Lucrio:BAABNQAECoEfAAIdAAgK5BFvSQDKAQAdAAgK5BFvSQDKAQAAAA==.Ludlow:BAAANQADCgMIAwABNQAECggIIQAWAO4PAA==.Lurim:BAABNQAECoEbAAIfAAgKah6yCAC6AgAfAAgKah6yCAC6AgAAAA==.Lushy:BAABNQAECoEZAAIbAAcKJRP8GgDsAQAbAAcKJRP8GgDsAQAAAA==.',
Ly='Lylindara:BAAANQAECgYIEwAAAA==.Lylinette:BAAANQADCggIDwAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECoEbAAIHAAYKTwg0GAE9AQAHAAYKTwg0GAE9AQABNQADCgMIAwAMAAAAAA==.Mageskin:BAAANQAECgIIBAAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCgYIFwAAAA==.Maximumhonk:BAABNQAECoEXAAIeAAcKdhudRQAgAgAeAAcKdhudRQAgAgAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQADCgYICAAAAA==.',
Me='Mekkadaddy:BAAANQAECgUIDgAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAAANQAECgUIEQAAAA==.Mercus:BAABNQAECoEZAAMWAAcKxA+kOACzAQAWAAcKBQ+kOACzAQAbAAYKtAxeJwByAQAAAA==.Merllinna:BAAANQABCgIIAQAAAA==.Mervenious:BAAANQAECgMICwAAAA==.',
Mi='Mindplague:BAABNQAECoEaAAIDAAYK8R1cIgD7AQADAAYK8R1cIgD7AQAAAA==.Minipincin:BAAANQAECgEIAQAAAA==.Minmzey:BAAANQAECgIJAgAAAA==.Miroslava:BAAANQADCgEIAQAAAA==.Missfire:BAAANQAECgUIBQABNQAECgUIBgAMAAAAAA==.',
Mo='Moggle:BAAANQAECgQICQAAAA==.Mondazi:BAABNQAECoEjAAMBAAgKSh0gLgCgAgABAAgKSh0gLgCgAgAeAAcKSg9thABSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQABCggIBgAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQADCgQICQAAAA==.Mozarta:BAAANQABCggIDQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgUIBgAMAAAAAA==.',
My='Mycen:BAABNQAECoEXAAIOAAgK4wubeADOAQAOAAgK4wubeADOAQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.',
['Má']='Málaketh:BAAANQAECgMIAgAAAA==.',
Na='Nardena:BAAANQAECgEIAQAAAA==.Narz:BAABNQAECoEkAAIIAAgKlAqDewDoAQAIAAgKlAqDewDoAQAAAA==.Naughtypine:BAAANQADCgYIBgAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Ne='Necronomikon:BAAANQAECgYICAAAAA==.Neromoo:BAAANQAECgUIDQABNQAECggIDAAMAAAAAA==.Neruphuyt:BAABNQAECoEXAAIGAAcKxwpOUwBhAQAGAAcKxwpOUwBhAQAAAA==.',
Ni='Niath:BAAANQAECgMIAwAAAA==.Nightheal:BAAANQABCgQIBQABNQAECggIHgALAB4jAA==.Nightsniper:BAAANQAECgEIAQABNQAECggIHgALAB4jAA==.',
No='Notdinor:BAAANQADCgIIAgAAAA==.Notlilly:BAAANQAECgYIEgAAAA==.Notpillows:BAAANQADCggIDgAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nò']='Nòvà:BAAANQAECgIIAgAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECgcIGQAbACUTAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAABNQAECoEjAAIIAAgKCxJEXgAxAgAIAAgKCxJEXgAxAgAAAA==.',
Op='Oprhawinfury:BAABNQAECoEUAAIdAAcKkgkWaABMAQAdAAcKkgkWaABMAQAAAA==.',
Or='Orgodemir:BAAANQAECgYIEwAAAA==.Orhamin:BAAANQADCgYIDwAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgEIAQAAAA==.Paigor:BAAANQABCgIIAgAAAA==.Palathene:BAAANQAECgcICQAAAA==.Pallystorm:BAAANQAECgUIBQAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECoElAAIOAAgKEhHNaQD5AQAOAAgKEhHNaQD5AQAAAA==.Parsie:BAAANQAECgIIAgAAAA==.Pathibas:BAAANQADCggIDQABNQAECggIIQAgAC4fAA==.Pattycakes:BAABNQAECoEXAAIdAAcKVwzgYgBfAQAdAAcKVwzgYgBfAQAAAA==.',
Ph='Pherocious:BAAANQAECgMIBAAAAA==.',
Pi='Pinktuesday:BAAANQADCgYJBgAAAA==.Pixeleen:BAABNQAECoEqAAMIAAkKXCMnGwATAwAIAAkKXCMnGwATAwAhAAUK5gv8QwAFAQAAAA==.',
Pl='Plexy:BAABNQAECoEgAAMNAAkKYSBmGQD4AgANAAkKuh9mGQD4AgAZAAcK8hlQBwDsAQAAAA==.',
Po='Pokitz:BAAANQAECgUICgAAAA==.',
Pr='Primordinor:BAABNQAECoEaAAIBAAcKwxoTUQAGAgABAAcKwxoTUQAGAgAAAA==.Probnotalive:BAABNQAECoEaAAIIAAgKaxtfPQCOAgAIAAgKaxtfPQCOAgAAAA==.Probnoturmom:BAABNQAECoEeAAINAAgKXxxbJAC9AgANAAgKXxxbJAC9AgAAAA==.',
Qu='Quacko:BAAANQABCgIIAgABNQAECggIGwAfAGoeAA==.',
Ra='Rakan:BAABNQAECoEfAAIiAAgK+xx6CQCHAgAiAAgK+xx6CQCHAgAAAA==.Rallick:BAABNQAECoEZAAIFAAgKcw2sXgDZAQAFAAgKcw2sXgDZAQAAAA==.Ranì:BAABNQAECoEjAAIiAAgKWxSKEgDPAQAiAAgKWxSKEgDPAQAAAA==.Rathger:BAAANQADCgUICAAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDQAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCggIDQAAAA==.Rendwee:BAABNQAECoEhAAIjAAcKbiEuCACjAgAjAAcKbiEuCACjAgAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQAECgQICAAAAA==.',
Rh='Rhaella:BAAANQABCgMIAwAAAA==.Rhynar:BAAANQAECggICAAAAA==.',
Ri='Ricflairion:BAABNQAECoEZAAIkAAcKxgiWDgAuAQAkAAcKxgiWDgAuAQAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECoEjAAICAAgKeiSGHwAuAwACAAgKeiSGHwAuAwAAAA==.Roflbubble:BAABNQAECoEbAAMNAAcKERWzZAC+AQANAAcKERWzZAC+AQADAAUK1gQCTAC9AAAAAA==.Rognan:BAAANQADCgMIAwAAAA==.Roku:BAAANQADCgcIGQAAAA==.Ronkin:BAAANQADCgYIFwAAAA==.Rookgue:BAABNQAECoEgAAIWAAcKsg+CNwC6AQAWAAcKsg+CNwC6AQAAAA==.Rookoker:BAAANQAECgUIDAAAAA==.Rorygazer:BAAANQAECgQICQAAAA==.Rosmerta:BAAANQADCgEIAQAAAA==.Rossa:BAAANQABCgIIAgAAAA==.Rossdair:BAAANQAECgQIBwAAAA==.Rossperot:BAABNQAECoEbAAIdAAcKdx5FQAD2AQAdAAcKdx5FQAD2AQAAAA==.',
Ry='Ryk:BAAANQADCggICAAAAA==.',
Sa='Saarin:BAAANQADCggIDAAAAA==.Saelara:BAAANQAECgQIBQAAAA==.Sairal:BAAANQAECgcIDwAAAA==.Saltytuesday:BAAANQADCgYICQAAAA==.Samgee:BAACNQAFFIEIAAICAAQKhgzqDgAgAQACAAQKhgzqDgAgAQA1AAQKgS8AAgIACQrDH60rAPwCAAIACQrDH60rAPwCAAAA.Sawlty:BAABNQAECoEYAAIhAAcKsw8iMgCTAQAhAAcKsw8iMgCTAQAAAA==.Saynar:BAABNQAECoEfAAMRAAgKXCARDwDrAgARAAgKUyARDwDrAgAVAAIKmhjbIACKAAAAAA==.',
Sc='Scattered:BAABNQAECoEcAAMPAAgKjAuHJABEAQAPAAYKSAqHJABEAQAOAAUKegnXygAHAQAAAA==.Schecter:BAABNQAECoEYAAMeAAcKJyOQKACgAgAeAAcKJyOQKACgAgABAAEKCxjwCQFAAAAAAA==.Scintila:BAAANQADCgQIBAABNQAECggIJQAOABIRAA==.Scooti:BAAANQADCggIEAABNQAECgQICAAMAAAAAA==.',
Se='Seba:BAABNQAECoEsAAIHAAkKNhqQWQC7AgAHAAkKNhqQWQC7AgAAAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAAANQAECgYIEwAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAAANQAECgUIEQAAAA==.',
Sh='Shadowlune:BAAANQABCgIIAgAAAA==.Shaggmz:BAAANQAECgQIBQAAAA==.Shinma:BAAANQAECgQIBQAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAAANQAECgQIBQAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAAANQAECgUIDQAAAA==.Sindiz:BAAANQAECgQIBQAAAA==.Siouxiesioux:BAAANQAECgQIBAAAAA==.',
Sk='Skadie:BAAANQADCgYICgAAAA==.Skoot:BAAANQAECgQICAAAAA==.',
Sl='Slimjimz:BAAANQADCgQIBAAAAA==.Slugondeez:BAABNQAECoEoAAMFAAgKBx5hJADBAgAFAAgKBx5hJADBAgATAAIKwx8bRQCzAAAAAA==.',
Sm='Smitefist:BAAANQAECgEIAQABNQAECggIDQAMAAAAAA==.',
Sn='Snkyturtle:BAABNQAECoEmAAIIAAgK0g/HawAPAgAIAAgK0g/HawAPAgAAAA==.Snoopdogydog:BAAANQABCgIIAQAAAA==.Snuzzle:BAABNQAECoEYAAIfAAcKbBhZEwDqAQAfAAcKbBhZEwDqAQAAAA==.',
So='Sourmash:BAAANQABCgIIAgAAAA==.',
Sp='Spaghet:BAAANQAECgcIEAAAAA==.Spillthetea:BAAANQADCggICQABNQAECgQICQAMAAAAAA==.Spittoon:BAAANQADCgEJAQABNQADCgcICwAMAAAAAA==.Sploot:BAABNQAECoEWAAIOAAgKKRxmQAB1AgAOAAgKKRxmQAB1AgAAAA==.',
Sr='Srasjet:BAAANQAECgIIAwAAAA==.',
Ss='Ssarmandok:BAAANQAECgYICQAAAA==.',
St='Stabytha:BAAANQAECgQIBAAAAA==.Stark:BAAANQABCgQIBAAAAA==.Starlight:BAAANQAECgcIDQAAAA==.Stealthed:BAAANQAECgIIAwAAAA==.Stonegoddess:BAAANQADCgMJAwAAAA==.Stormcall:BAAANQAECgIIBAAAAA==.Stratusfied:BAAANQADCgIIAgAAAA==.Strongsad:BAAANQADCgcIBwAAAA==.',
Sw='Swiss:BAAANQAECgYIEwAAAA==.',
Sy='Syldra:BAAANQABCgIIAgAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgEIAQAAAA==.',
Ta='Taliden:BAAANQAECgIIAgAAAA==.Tankinstine:BAAANQADCgEIAQAAAA==.Taraylda:BAAANQAECgQICQAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAAANQAECgUICwAAAA==.',
Tf='Tfirs:BAAANQAECgQJBwABNQAFFAEIAQAMAAAAAA==.',
Th='Thehealczar:BAAANQAECgcIDwABNQAECggIHgALAB4jAA==.Theokoles:BAAANQAECggIDQAAAA==.Thesenate:BAAANQADCggIDwABNQAECggIGQAJAFsHAA==.Thickblòód:BAAANQADCgEIAQAAAA==.Thorly:BAAANQADCgYIDQAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.Tinn:BAAANQADCgYIBgAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAAANQAECgQIDAAAAA==.Treecloud:BAABNQAECoEcAAIfAAgKuCCQBgD3AgAfAAgKuCCQBgD3AgAAAA==.Treferimore:BAAANQAECgQIBQAAAA==.Trevian:BAAANQAECgYIEwAAAA==.',
Tu='Tuluxxi:BAABNQAECoEhAAMeAAgKnh7rRAAiAgAeAAcKrh3rRAAiAgABAAgKFw5sYgDKAQAAAA==.Tutter:BAAANQAECgMIAwAAAA==.',
Tw='Twopumpchump:BAAANQAECgYIDQAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECgcIEgAMAAAAAA==.',
Ug='Uglymancer:BAAANQAECgYIEwAAAA==.',
Uj='Ujimas:BAAANQAECgUIEQAAAA==.',
Ut='Uthodne:BAAANQADCgYIBgABNQAECggIIQAWAO4PAA==.',
Va='Vampireshade:BAABNQAECoEbAAMWAAcKFAqPQACGAQAWAAcKFAqPQACGAQAlAAYK0AP1EADsAAAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAABNQAECoEZAAILAAcK6g2DWABvAQALAAcK6g2DWABvAQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgEIAQAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgMIBAAAAA==.Venatra:BAAANQADCgYICAAAAA==.Veritus:BAABNQAECoEZAAIYAAcKFR7TJABOAgAYAAcKFR7TJABOAgAAAA==.',
Vi='Vindict:BAAANQAECgIIAwAAAA==.Violette:BAAANQAECgQICgAAAA==.Vion:BAAANQABCgQIBAAAAA==.',
Vo='Voidlink:BAABNQAECoEfAAIZAAgKDyKEAQAiAwAZAAgKDyKEAQAiAwAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Wa='Wackyrellek:BAAANQAECgYICwAAAA==.Wakancer:BAAANQAECgQIEQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgQICwAAAA==.Walnut:BAAANQADCgEIAQABNQAECggIIgABAPUfAA==.Warchylde:BAAANQADCgIIAgAAAA==.Warolderoy:BAABNQAECoEhAAMgAAgKLh/xAwDkAgAgAAgK1B7xAwDkAgAiAAYKJBpAEwDEAQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.',
Wo='Woker:BAAANQADCggIEQABNQAECggIGQAJAFsHAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQADCgQIBAAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgcIFwAOADwcAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.',
Xe='Xenna:BAAANQAECgUICgABNQAECgYIDwAMAAAAAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQADCggICAAAAA==.',
Ye='Yeoman:BAAANQAECgUIDAAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECgcIEwAAAQ==.',
Yu='Yunohealme:BAAANQAECgYIEQAAAA==.Yunosmall:BAAANQADCgMJAwAAAA==.Yunosmart:BAAANQADCgMIBAAAAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAABNQAECoEmAAMOAAkKMhuZKQDFAgAOAAkKMhuZKQDFAgAPAAMKLxIsPADGAAAAAA==.Zandre:BAABNQAECoEeAAIiAAgKpBbXDwD+AQAiAAgKpBbXDwD+AQAAAA==.Zarkir:BAABNQAECoElAAILAAkK9yHOCwBFAwALAAkK9yHOCwBFAwAAAA==.',
Ze='Zelily:BAABNQAECoEbAAIIAAcKsApslACtAQAIAAcKsApslACtAQAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAABNQAECoEZAAMeAAcKMxYiYgC4AQAeAAcKMxYiYgC4AQABAAEKwAowIQEsAAABNQAECggIFwAeAJIeAA==.Zhiana:BAABNQAECoEaAAMSAAgKZRKoCwDPAQAHAAgKcQzswwDZAQASAAgKcA+oCwDPAQAAAA==.',
Zo='Zornov:BAAANQADCgcIBwABNQAECggIGwAfAGoeAA==.',
Zu='Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQADCggICAAAAA==.Zvirax:BAAANQADCgYIHAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBAAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgEIAQABNQAECgIJAwAMAAAAAA==.',
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
