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

local lookup = {'Warrior-Fury','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Paladin-Retribution','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Balance','Shaman-Restoration','DeathKnight-Frost','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAcJHgABADAcAA==.',
Ar='Arasis:BAABLgAECn81AAICAAkJeSUvAQBGAwACAAkJeSUvAQBGAwAAAA==.Arìel:BAAALgADCgkJDwAAAA==.',
As='Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAAALgAFFAIJBAAAAA==.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwABAAgJgSLxBgA5AwAAAA==.',
Bi='Bigmak:BAAALgAECgEJAQAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCggJFQAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMDAAgJqCQMBwC4AgADAAgJqCQMBwC4AgAEAAIJPxvvcAB/AAAAAA==.Ceridemon:BAABLgAECn8iAAIFAAkJ4g9pFgCeAQAFAAkJ4g9pFgCeAQAAAA==.',
Ch='Chingee:BAABLgAECn9MAAMGAAkJxxopCwCSAgAGAAkJ7BkpCwCSAgAHAAgJiw5AJgC6AQAAAA==.',
Co='Consarios:BAAALgAFFAEJAQAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8NAAIDAAMJgQ21GwDHAAADAAMJgQ21GwDHAAAuAAQKfzUAAwMACQm7GqMNAEQCAAMACQlOGqMNAEQCAAQABAkeFGlFAMkAAAAA.Cyvus:BAABLgAECn8kAAMHAAgJawVZQwArAQAHAAgJawVZQwArAQAIAAYJ+wl3PgDsAAAAAA==.',
Da='Dab:BAABLgAECn9BAAIJAAkJhSWMAgBnAwAJAAkJhSWMAgBnAwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMKAAkJER8LEgCnAgAKAAgJtx8LEgCnAgACAAkJ9RgfCQBzAgAAAA==.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgALABQaAA==.Darkhorse:BAABLgAECn8iAAIMAAgJIB5cCgBbAgAMAAgJIB5cCgBbAgAAAA==.Darkmer:BAABLgAECn8qAAIJAAYJ9QU6wgDPAAAJAAYJ9QU6wgDPAAAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAINAAkJahBrGgB+AQANAAkJahBrGgB+AQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8rAAMOAAkJihSWHQDIAQAOAAkJmxGWHQDIAQAPAAcJ2BGDEwCBAQAAAA==.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAIQAAgJDRaEHADRAQAQAAgJDRaEHADRAQABLgAFFAgJIgAKAFcaAA==.Gorberfn:BAAALgAECgMJAwABLgAFFAgJIgAKAFcaAA==.',
Gr='Grimorn:BAACLgAFFH8iAAIJAAgJfyD6AQC8AgAJAAgJfyD6AQC8AgAuAAQKfykAAgkACQnAIcADAJkDAAkACQnAIcADAJkDAAAA.Grogvald:BAABLgAECn8cAAILAAgJOSLuCADWAgALAAgJOSLuCADWAgAAAA==.',
['Gø']='Gøober:BAACLgAFFH8iAAQKAAgJVxqgAwAJAgARAAYJ4RucAwAPAgAKAAcJORqgAwAJAgACAAIJOyElHACzAAAuAAQKf0IABBEACQlCJoMDAG0DABEACQkUIYMDAG0DAAIACQnlIM8DAN8CAAoABwmqJLEVAH0CAAAA.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8hAAIOAAgJ4xoIFwABAgAOAAgJ4xoIFwABAgAAAA==.',
Hi='Hidrógeno:BAACLgAFFH8FAAISAAMJLgwdUwDbAAASAAMJLgwdUwDbAAAuAAQKfxcAAhIACAkrHssxAFsCABIACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBQABLgAECggJHAATABQUAA==.',
Ho='Hoofartted:BAACLgAFFH8FAAIPAAMJUhjABwD+AAAPAAMJUhjABwD+AAAuAAQKfzkAAg8ACAnOIwkDALkCAA8ACAnOIwkDALkCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAIJBAAUAAAAAA==.',
Is='Istarìa:BAAALgADCgkJGgAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIVAAkJLhbJMwAsAgAVAAkJLhbJMwAsAgAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIWAAcJ4x3yIACTAQAWAAcJ4x3yIACTAQAAAA==.',
Ki='Kijana:BAABLgAFFH8IAAIKAAQJ6iSFCwCeAQAKAAQJ6iSFCwCeAQABLgAFFAUJEQAKAHolAA==.Kindraa:BAAALgADCgkJGQAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn80AAICAAkJzBlKCQBwAgACAAkJzBlKCQBwAgAAAA==.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn8xAAIGAAgJnRLgGgDLAQAGAAgJnRLgGgDLAQAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAXALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgIJAgAAAA==.',
My='Myrddraal:BAAALgADCgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgEJAQAAAA==.Nastybob:BAABLgAECn8zAAIJAAkJtyToBABBAwAJAAkJtyToBABBAwAAAA==.',
Ni='Nicobulus:BAABLgAECn8XAAIOAAgJiwrIOwAWAQAOAAgJiwrIOwAWAQAAAA==.Nightspell:BAAALgAECgUJBgAAAA==.',
No='Nor:BAABLgAECn8XAAMLAAcJ7B3DHAAvAgALAAYJmSDDHAAvAgASAAYJjhWwiwA5AQAAAA==.',
['Nä']='Näota:BAAALgAECgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8hAAIVAAgJYBc7AwBHAgAVAAgJYBc7AwBHAgAuAAQKfykAAhUACQkBJDkDAMsDABUACQkBJDkDAMsDAAAA.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMJAAgJ2hX5SQDCAQAJAAgJ2hX5SQDCAQAYAAEJAxMGKQA5AAAAAA==.Phiend:BAAALgAECgQJDQAAAA==.Phlak:BAAALgAECgYJDwAAAA==.',
Pl='Pluvl:BAABLgAECn8cAAIMAAgJ7QLyLAADAQAMAAgJ7QLyLAADAQAAAA==.',
Qu='Quimby:BAAALgAECgcJDQAAAA==.',
Ra='Raign:BAAALgADCgkJGwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQAMAD4ZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAISAAgJrBziSADMAQASAAgJrBziSADMAQAAAA==.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQLAAkJFBpWGQBIAgALAAkJFBpWGQBIAgAZAAUJXgzQKgCYAAASAAIJegdXZQEwAAAAAA==.Sapphirre:BAAALgADCgcJEQAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAQAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgQJBAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIFAAgJXyCjBgD8AgAFAAgJXyCjBgD8AgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAISAAcJsCC4MQBcAgASAAcJsCC4MQBcAgAAAA==.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBAAAAA==.Sloan:BAABLgAECn8UAAIGAAYJOwPZQADMAAAGAAYJOwPZQADMAAAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAQABLgAFFAgJHQAaAGwZAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLgAIAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8cAAITAAgJFBQESACsAQATAAgJFBQESACsAQAAAA==.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgMJAwABLgAECggJHAATABQUAA==.Tanglebones:BAABLgAECn8UAAIbAAYJwgvKDwAIAQAbAAYJwgvKDwAIAQAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJDgAXACEYAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAUAAAAAA==.',
Un='Unsocial:BAAALgADCgkJGAAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAUAAAAAA==.Vermi:BAAALgAECgMJBQAAAA==.',
Wa='Warcloud:BAABLgAECn8YAAILAAgJ+AO1QwAHAQALAAgJ+AO1QwAHAQAAAA==.Wartortle:BAABLgAECn8uAAMcAAgJpBrbDQDiAQAcAAgJpBrbDQDiAQAdAAEJnQnoYwAsAAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDAAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJCgAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgYJCgAUAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJBwAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgADCgYJBgAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIXAAgJhhg8KwDeAQAXAAgJhhg8KwDeAQAAAA==.',
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
