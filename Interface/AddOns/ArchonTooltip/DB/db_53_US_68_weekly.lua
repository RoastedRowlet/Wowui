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

local lookup = {'DemonHunter-Devourer','Hunter-Survival','Mage-Frost','Mage-Arcane','Paladin-Retribution','Unknown-Unknown','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Druid-Restoration','DeathKnight-Unholy','Paladin-Holy','Warlock-Demonology','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Priest-Discipline','Rogue-Assassination','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Rogue-Subtlety','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='Dethecus',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aashhley:BAAANQAECggIBgAAAA==.Aashhlie:BAAANQAECggIBwAAAA==.',
Al='Alistis:BAABNQAECn8sAAIBAAoKQBjzIwAoAgABAAoKQBjzIwAoAgAAAA==.',
Am='Amutio:BAAANQADCgYJBwAAAA==.',
Ar='Arasis:BAABNQAECn81AAICAAkK+CLbAQA9AwACAAkK+CLbAQA9AwAAAA==.Arìel:BAAANQABCggIGQAAAA==.',
Bi='Biggiecasts:BAACNQAFFH8gAAMDAAkKqxXQAgD9AAAEAAgK7xKXDgADAgADAAMKHx7QAgD9AAA1AAQKfyoAAwQACgqvI9BDAPwCAAQACgrfItBDAPwCAAMAAgrXIRAgAMMAAAAA.Bigmak:BAACNQAFFH8MAAIFAAQKzhgUEQDrAAAFAAQKzhgUEQDrAAA1AAQKf0UAAgUACgqHIQEVAAoDAAUACgqHIQEVAAoDAAAA.',
Bl='Blasphemar:BAAANQADCggIDgAAAA==.',
Bo='Boom:BAAANQAECggIBQABNQAFFAgIAQAGAAAAAA==.Boopienoodle:BAAANQAECgQICQAAAA==.Boopnoodle:BAAANQADCggICAAAAA==.',
Br='Braellyn:BAAANQADCggIEAAAAA==.',
Bu='Burnyou:BAAANQABCgcIDwAAAA==.',
Ca='Cassandre:BAAANQADCgcIBwAAAA==.',
Ce='Ceridemon:BAABNQAECn8zAAIHAAgKyQzQNABgAQAHAAgKyQzQNABgAQAAAA==.',
Ch='Chingee:BAABNQAECn8pAAMIAAoK4RhHNgCPAgAIAAkK/BhHNgCPAgAJAAEKAACIcwA/AAAAAA==.',
Co='Consarios:BAABNQAECn9MAAIFAAoKUiWaBwC+AwAFAAoKUiWaBwC+AwAAAA==.',
Cy='Cyrendondk:BAACNQAFFH8JAAIKAAMKlQu6HgBlAAAKAAMKlQu6HgBlAAA1AAQKf0cAAgoACgqeE3pHANsBAAoACgqeE3pHANsBAAAA.Cyvus:BAAANQADCggICAAAAA==.',
Da='Daedara:BAAANQADCgQIBAAAAA==.Daggz:BAABNQAECn89AAMLAAoK7havFADmAQAMAAcK+hnUeAAdAgALAAoKBRKvFADmAQAAAA==.Darkmer:BAAANQAECgMIBAABNQAECgoKKQAFAHMGAA==.',
Di='Dixiereaper:BAABNQAECn8YAAIKAAoKkQZGaABSAQAKAAoKkQZGaABSAQAAAA==.',
Dr='Dragonalady:BAAANQADCgQIBAAAAA==.',
Ds='Dsntdrptotem:BAABNQAECn9LAAINAAoKQxw3HQB3AgANAAoKQxw3HQB3AgAAAA==.',
Ep='Epicamerican:BAAANQADCgcIEgAAAA==.',
Ff='Ffecanti:BAAANQAECgQIBgAAAA==.',
Fl='Flashands:BAAANQAECgEIAQAAAA==.Flydadphd:BAAANQAECgQIBAABNQAFFAUICwAOAOMhAA==.',
Ga='Gandonn:BAAANQADCgEIAQAAAA==.',
Gr='Greenspot:BAAANQADCgMIAwABNQAECgoKKQAFAHMGAA==.Grimorn:BAACNQAFFH8dAAIPAAgKgBtVAACuAgAPAAgKgBtVAACuAgA1AAQKfzkAAg8ACgqzJesBAN8DAA8ACgqzJesBAN8DAAAA.Grogvald:BAABNQAECn8aAAIQAAYKzyJmRQBQAgAQAAYKzyJmRQBQAgAAAA==.Gromlumn:BAAANQADCgcIBwABNQAECgoKLAARAFkUAA==.',
['Gø']='Gøober:BAACNQAFFH8dAAMMAAgK6RmCAwAsAgAMAAYKfhyCAwAsAgALAAUKChZTEAA3AQA1AAQKf0EAAwwACgpDJnwJAJEDAAwACQqhJXwJAJEDAAsACgr/INQLABwDAAAA.',
Ha='Hardlocklife:BAABNQAECn8mAAIRAAkKoB/eGgAaAwARAAkKoB/eGgAaAwAAAA==.',
He='Herax:BAAANQAECgIIAgAAAA==.Hesperus:BAAANQAECgQIBwAAAA==.',
Hi='Hidrógeno:BAAANQAECgMICwABNQAFFAgIKAARADcSAA==.',
Ho='Holler:BAAANQADCggICgAAAA==.Hoofartted:BAABNQAECn9QAAISAAoKkiLdAQCYAwASAAoKkiLdAQCYAwAAAA==.Horndawg:BAAANQADCgMIBAAAAA==.',
Ib='Ibite:BAAANQAECgcIDAAAAA==.Iblastyou:BAAANQAECgQIBAAAAA==.',
Io='Io:BAAANQAECgMIBgABNQAFFAIIBgAKABAZAA==.',
Is='Istarìa:BAAANQABCggIGQAAAA==.',
Kh='Khajiit:BAACNQAFFH8NAAITAAQKZRHzEADbAAATAAQKZRHzEADbAAA1AAQKfz8AAhMACgoGIZwJAPkCABMACgoGIZwJAPkCAAAA.',
Ki='Kijana:BAAANQAECgMIAwABNQAFFAUICAAUAFEaAA==.Kindraa:BAAANQABCggIFQAAAA==.',
Le='Leftarm:BAAANQADCgUIBQAAAA==.Leveltwo:BAAANQAECgcICQAAAA==.',
Li='Littlestar:BAABNQAECn8iAAMVAAkKFRiUAgCEAgAVAAkKFRiUAgCEAgAJAAEKAAC9dgAAAAAAAA==.',
Lo='Lolaa:BAAANQADCgMIAwAAAA==.Lorgestick:BAAANQAECgUIBgAAAA==.',
Lu='Luther:BAAANQABCgQIBAABNQAECgoKOgARAG0XAA==.',
Ly='Lyraa:BAAANQADCgIIAwAAAA==.',
['Lì']='Lìly:BAAANQABCggIFgAAAA==.',
Mi='Mints:BAABNQAECn8gAAIWAAgKzx5tGgCpAgAWAAgKzx5tGgCpAgAAAA==.',
Mo='Moramore:BAAANQAECgMIAQAAAA==.',
My='Myrddraal:BAAANQADCgMIAwAAAA==.',
Na='Naenae:BAAANQADCgYJCAAAAA==.',
Ne='Nellielle:BAAANQAECggICAAAAA==.',
Ni='Nightspell:BAAANQADCgQJBAAAAA==.',
No='Nor:BAAANQAECgEIAQAAAA==.Nornlock:BAAANQAECggICAABNQAFFAUICgAXANAVAA==.',
['Nä']='Näota:BAAANQAECgMIAwAAAA==.',
Oh='Ohmesoholy:BAABNQAECn8fAAMQAAkKUiY1CQCAAwAQAAkKUiY1CQCAAwAFAAQKGg+5JAGfAAAAAA==.',
Ou='Outoftime:BAABNQAECn8pAAIFAAoKcwZs0gB3AQAFAAoKcwZs0gB3AQAAAA==.',
Pa='Paladan:BAAANQADCgUIBQAAAA==.Papanoellego:BAACNQAFFH8cAAMDAAgKYSCcAgAHAQAEAAcKRx/ADQAKAgADAAMKnh6cAgAHAQA1AAQKfzIAAwQACgrfJcwbAGcDAAQACgq1JcwbAGcDAAMABgqIJbcMAK8BAAAA.',
Ph='Pheal:BAAANQAECgcIDgAAAA==.Phiend:BAAANQAECgMIBAAAAA==.Phlak:BAAANQADCgUIBQAAAA==.',
Po='Powndage:BAABNQAECn8XAAIQAAkKUwdQlgDmAAAQAAkKUwdQlgDmAAAAAA==.',
Qu='Quimby:BAABNQAECn8hAAIRAAkK9w2zeQBcAQARAAkK9w2zeQBcAQAAAA==.',
Ra='Rabbitstew:BAAANQAECgcIEAAAAA==.Raign:BAAANQAECgEIAQAAAA==.',
Ri='Rivent:BAABNQAECn8ZAAIHAAkK4w6cNABiAQAHAAkK4w6cNABiAQAAAA==.Rivia:BAAANQAECgYICAAAAA==.',
Ro='Royalmace:BAACNQAFFH8eAAQRAAgKBiOLAADsAgARAAcKciWLAADsAgAYAAIKLxXHDgCYAAAZAAEK6hYqEABUAAA1AAQKfzsABBEACgpzJewDALoDABEACgpzJewDALoDABgABwpiI48KAE4CABkAAgqAFYccAH0AAAAA.',
Sa='Safaridan:BAABNQAECn8qAAQQAAoKhhlCNgCLAgAQAAoKhhlCNgCLAgAXAAYKDAxUPgAEAQAFAAEKUwyCowE1AAAAAA==.Saimie:BAAANQADCgUIBQABNQAECgMIAQAGAAAAAA==.Saldott:BAAANQAECgYIBgAAAA==.Santhx:BAAANQAECggICQAAAA==.Sarene:BAABNQAECn8pAAIQAAoKhhaSQABiAgAQAAoKhhaSQABiAgAAAA==.',
Sc='Scamp:BAABNQAECn8VAAMRAAcKUBZOtgDSAAARAAYKBhVOtgDSAAAZAAEKwxxjJgBTAAAAAA==.Scarlot:BAABNQAECn86AAMRAAoKbRfTLgBEAgARAAoKbRfTLgBEAgAYAAcKDAcoGQCNAAAAAA==.',
Se='Sentry:BAAANQADCgYICgAAAA==.Serous:BAAANQAECgUICQAAAA==.',
Si='Sienen:BAAANQAECgQIBgAAAA==.',
Sk='Skeeter:BAAANQADCggIEAABNQAECgoKKwAYAO8XAA==.',
Sl='Slashly:BAAANQADCgcJBwAAAA==.',
Sp='Spanish:BAAANQAECgMIBAAAAA==.Spinkick:BAAANQADCgYIBwAAAA==.',
Sq='Squirrelydan:BAAANQAECggIDQAAAA==.',
Sr='Sryven:BAAANQADCggJCAAAAA==.',
St='Stampede:BAABNQAECn8VAAIMAAoKWSK+IwAIAwAMAAoKWSK+IwAIAwABNQAECggIFQABAMIhAA==.Stic:BAAANQAECgMIAwAAAA==.Stiks:BAAANQADCggICAAAAA==.',
Sv='Svinehundt:BAABNQAECn8sAAIRAAoKWRRxcQAMAgARAAoKWRRxcQAMAgAAAA==.',
Ta='Tanglebones:BAABNQAECn8iAAMaAAkKbAdaYQBpAQAaAAkKKgdaYQBpAQAWAAMKWgaNQwB4AAAAAA==.Tanglezugzug:BAAANQADCggIFwAAAA==.',
Th='Theskinny:BAAANQAECgYIEAAAAA==.',
Tr='Trip:BAAANQAECggIDwABNQAFFAcIGgAFAFcQAA==.',
Tu='Turtles:BAAANQADCgEIAQAAAA==.',
Un='Unsocial:BAAANQABCggICQAAAA==.',
Vi='Viska:BAAANQADCgYIBgAAAA==.',
Vo='Voidfiend:BAAANQAECgEIAwAAAA==.',
Wa='Wartortle:BAAANQAECgQIBQAAAA==.',
Wh='Whack:BAABNQAECn8qAAQUAAoK+B8vMwD0AgAUAAoKeR4vMwD0AgAbAAIKgh32IgCeAAAcAAEKyRv7NwBRAAAAAA==.',
Wu='Wu:BAAANQADCgUIDAAAAA==.Wulfgaz:BAAANQAECgUIEwABNQAECgoKNQATAH8VAA==.',
Wy='Wylf:BAABNQAECn81AAMTAAoKfxUtIgDXAQATAAoKfxUtIgDXAQAOAAQK+Qv2SgC7AAAAAA==.',
Za='Zappytangle:BAABNQAECn8iAAINAAcKiAXCvwATAQANAAcKiAXCvwATAQAAAA==.',
Ze='Zerø:BAAANQADCgYICAAAAA==.',
Zi='Zinthous:BAAANQAECgIIAgAAAA==.',
['Äl']='Ältäir:BAAANQAECggIEQAAAA==.',
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
