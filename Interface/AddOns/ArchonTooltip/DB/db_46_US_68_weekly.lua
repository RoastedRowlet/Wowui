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

local lookup = {'Warrior-Fury','Hunter-Survival','Druid-Guardian','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Paladin-Retribution','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Demonology','Mage-Frost','Druid-Balance','Shaman-Restoration','Unknown-Unknown','DeathKnight-Frost','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAgJIwABABsbAA==.',
Ar='Arasis:BAABLgAECn81AAICAAkJeSV1AQA+AwACAAkJeSV1AQA+AwAAAA==.Arìel:BAAALgADCgkJFQAAAA==.',
As='Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAABLgAFFH8FAAIDAAIJUBZDHACJAAADAAIJUBZDHACJAAAAAA==.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwABAAgJgSLxBgA5AwAAAA==.',
Bi='Bigmak:BAAALgAECgYJBgAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCggJGgAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMEAAgJqCQZCACzAgAEAAgJqCQZCACzAgAFAAIJPxvvcAB/AAAAAA==.Ceridemon:BAABLgAECn8iAAIGAAkJ4g8mGQCWAQAGAAkJ4g8mGQCWAQAAAA==.',
Ch='Chingee:BAACLgAFFH8GAAMHAAYJ+QHdFwDcAAAHAAQJQgLdFwDcAAAIAAIJZgE6OgBcAAAuAAQKf0wAAwgACQnHGqIJAKECAAgACQnsGaIJAKECAAcACAmLDkAmALoBAAAA.',
Co='Cobel:BAAALgAECgIJAgAAAA==.Consarios:BAABLgAFFH8HAAIJAAYJHRkNDwCxAQAJAAYJHRkNDwCxAQAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8RAAMEAAQJ3A1WIAC/AAAEAAMJgQ1WIAC/AAAFAAMJbQrCNAC/AAAuAAQKfzUAAwQACQm7GlgPAD0CAAQACQlOGlgPAD0CAAUABAkeFEJJAMgAAAAA.Cyvus:BAABLgAECn8kAAMHAAgJawVZQwArAQAHAAgJawVZQwArAQAKAAYJ+wklRADYAAAAAA==.',
Da='Dab:BAABLgAECn9BAAILAAkJhSVEAwBjAwALAAkJhSVEAwBjAwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMMAAkJER8LEgCnAgAMAAgJtx8LEgCnAgACAAkJ9RhKCgBtAgAAAA==.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgANABQaAA==.Darkhorse:BAABLgAECn8mAAIOAAgJwh6bCgBkAgAOAAgJwh6bCgBkAgAAAA==.Darkmer:BAABLgAECn8xAAILAAcJ3wgtmwAeAQALAAcJ3wgtmwAeAQAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAIPAAkJahBrGgB+AQAPAAkJahBrGgB+AQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8uAAMQAAkJzBRCIADIAQAQAAkJ3RFCIADIAQARAAcJ2BGDEwCBAQAAAA==.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAISAAgJDRa1HgDIAQASAAgJDRa1HgDIAQABLgAFFAgJKAAMAMAaAA==.Gorberfn:BAAALgAECgMJAwABLgAFFAgJKAAMAMAaAA==.',
Gr='Grimorn:BAACLgAFFH8iAAILAAgJfyDxAABGAgALAAgJfyDxAABGAgAuAAQKfykAAgsACQnAIcADAJkDAAsACQnAIcADAJkDAAAA.Grogvald:BAABLgAECn8kAAINAAgJ0CM9BgAZAwANAAgJ0CM9BgAZAwAAAA==.',
['Gø']='Gøober:BAACLgAFFH8oAAQMAAgJwBq6BAAdAgAMAAcJtBq6BAAdAgATAAYJ4RucAwAPAgACAAMJICFKFAAcAQAuAAQKf0IABBMACQlCJoMDAG0DABMACQkUIYMDAG0DAAIACQnlIKoEANYCAAwABwmqJD4ZAHgCAAAA.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8hAAIQAAgJ4xqWGQD9AQAQAAgJ4xqWGQD9AQAAAA==.',
Hi='Hidrógeno:BAACLgAFFH8FAAIJAAMJLgwTYQDMAAAJAAMJLgwTYQDMAAAuAAQKfxcAAgkACAkrHssxAFsCAAkACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBgABLgAECggJKAAUALoWAA==.',
Ho='Hoofartted:BAACLgAFFH8GAAIRAAMJUhjVCQD0AAARAAMJUhjVCQD0AAAuAAQKfzkAAhEACAnOI5QDALQCABEACAnOI5QDALQCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAMJBgAOADkWAA==.',
Is='Istarìa:BAAALgADCgkJIgAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIVAAkJLhZbOAAgAgAVAAkJLhZbOAAgAgAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIWAAcJ4x3lIwCSAQAWAAcJ4x3lIwCSAQAAAA==.',
Ki='Kijana:BAABLgAFFH8IAAIMAAQJ6iSDEQCXAQAMAAQJ6iSDEQCXAQABLgAFFAUJFgAMAMgmAA==.Kindraa:BAAALgADCgkJIQAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn8+AAMCAAkJER5qBQDEAgACAAkJER5qBQDEAgATAAEJFhF1NQA1AAAAAA==.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn85AAIIAAgJkxMhGwDUAQAIAAgJkxMhGwDUAQAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAXALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQABLgAECgIJAgAYAAAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgIJAgAAAA==.',
My='Myrddraal:BAAALgADCgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgIJAwAAAA==.Nastybob:BAABLgAECn8zAAILAAkJtyQTBgA7AwALAAkJtyQTBgA7AwAAAA==.',
Ni='Nicobulus:BAABLgAECn8eAAIQAAgJ4w02NgBFAQAQAAgJ4w02NgBFAQAAAA==.Nightspell:BAAALgAECgUJBgAAAA==.',
No='Nor:BAABLgAECn8XAAMNAAcJ7B3DHAAvAgANAAYJmSDDHAAvAgAJAAYJjhXilAAuAQAAAA==.',
['Nä']='Näota:BAAALgAECgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8nAAIVAAgJ8xc7AwBHAgAVAAgJ8xc7AwBHAgAuAAQKfykAAhUACQkBJDkDAMsDABUACQkBJDkDAMsDAAAA.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMLAAgJ2hVZUAC/AQALAAgJ2hVZUAC/AQAZAAEJAxPTLgA5AAAAAA==.Phiend:BAAALgAECgQJDgAAAA==.Phlak:BAAALgAECgYJDwAAAA==.',
Pl='Pluvl:BAABLgAECn8cAAIOAAgJ7QIIMQD9AAAOAAgJ7QIIMQD9AAAAAA==.',
['Pö']='Pöstal:BAAALgADCggJCAAAAA==.',
Qu='Quimby:BAAALgAECgcJDQAAAA==.',
Ra='Raign:BAAALgADCgkJIAAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQAOAD4ZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAIJAAgJrBz2QQAfAgAJAAgJrBz2QQAfAgAAAA==.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQNAAkJFBpWGQBIAgANAAkJFBpWGQBIAgAaAAUJXgwoLgCXAAAJAAIJegcChgErAAAAAA==.Sapphirre:BAAALgADCgcJGAAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAgAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgUJCAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIGAAgJXyCjBgD8AgAGAAgJXyCjBgD8AgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAIJAAcJsCC4MQBcAgAJAAcJsCC4MQBcAgAAAA==.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBQAAAA==.Sloan:BAABLgAECn8ZAAIIAAYJigOBRwC7AAAIAAYJigOBRwC7AAAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAQABLgAFFAgJJAAbAIIZAA==.',
Sq='Squirrelydan:BAAALgADCgUJBQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLgAKAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Sticky:BAAALgAECgIJAgABLgAFFAMJBQASAJIMAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8oAAIUAAgJuhZUOQDoAQAUAAgJuhZUOQDoAQAAAA==.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgcJCgABLgAECggJKAAUALoWAA==.Tanglebones:BAABLgAECn8eAAIcAAYJmwxqEAAMAQAcAAYJmwxqEAAMAQAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJEgAXAP0YAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAYAAAAAA==.',
Un='Unsocial:BAAALgADCgkJIQAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAYAAAAAA==.Vermi:BAAALgAECgMJCAAAAA==.',
Wa='Warcloud:BAABLgAECn8YAAINAAgJ+AO3RwAHAQANAAgJ+AO3RwAHAQAAAA==.Wartortle:BAABLgAECn8vAAMdAAgJpBqVDwDWAQAdAAgJpBqVDwDWAQAeAAEJnQkNbgAsAAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDwAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJDwAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgYJDwAYAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJCgAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgAECgIJAgAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIXAAgJhhjCLwDbAQAXAAgJhhjCLwDbAQAAAA==.',
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
