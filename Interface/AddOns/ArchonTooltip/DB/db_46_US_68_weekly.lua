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

local lookup = {'Warrior-Protection','Warrior-Arms','Warrior-Fury','Hunter-Survival','Druid-Feral','Druid-Guardian','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Mage-Frost','Druid-Balance','Shaman-Restoration','Unknown-Unknown','DeathKnight-Frost','Warlock-Destruction','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination',}
local provider = {region='US',realm='Dethecus',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aashhlie:BAAALgAECgkJAQAAAA==.Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAABLgAECn8UAAQBAAMJLhHUBwCUAAABAAMJLhHUBwCUAAACAAMJrgdPWgBwAAADAAMJoQbjFQBfAAAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAgJLwADAH0cAA==.',
Ar='Arasis:BAACLgAFFH8HAAIEAAMJeRr7GAAKAQAEAAMJeRr7GAAKAQAuAAQKfzUAAgQACQl5JR4CADEDAAQACQl5JR4CADEDAAAA.Arìel:BAAALgAECgYJCwAAAA==.',
As='Asexpected:BAAALgAECggJCQABLgAECgkJIAAFAB4aAA==.Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAABLgAFFH8HAAIGAAIJShv4IACZAAAGAAIJShv4IACZAAAAAA==.Bamag:BAABLgAECn8eAAIDAAgJgSLxBgA5AwADAAgJgSLxBgA5AwAAAA==.',
Bi='Bigmak:BAAALgAFFAIJBAAAAA==.',
Bo='Boom:BAAALgAFFAkJBAAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgAECgEJAgAAAA==.',
Ce='Celestine:BAAALgAECgEJAQAAAA==.Cenobité:BAABLgAECn8rAAMHAAgJqCS2CQCpAgAHAAgJqCS2CQCpAgAIAAIJPxvvcAB/AAAAAA==.Ceridemon:BAABLgAECn8mAAIJAAkJbhDaHQCNAQAJAAkJbhDaHQCNAQAAAA==.',
Ch='Chingee:BAACLgAFFH8GAAMKAAYJ+QEvHQDPAAAKAAQJQgIvHQDPAAALAAIJZgH/RgBXAAAuAAQKf0wAAwsACQnHGqIJAKECAAsACQnsGaIJAKECAAoACAmLDkAmALoBAAAA.',
Co='Cobalt:BAAALgAECgUJCgABLgAFFAQJBwAMAP4GAA==.Cobel:BAAALgAECgMJAwAAAA==.Consarios:BAABLgAFFH8KAAINAAgJFRevHQCRAQANAAgJFRevHQCRAQAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8UAAMHAAQJIBOWIgDLAAAHAAMJhRSWIgDLAAAIAAMJbQrEOgC7AAAuAAQKfzUAAwcACQm7GroRADUCAAcACQlOGroRADUCAAgABAkeFC9OAMcAAAAA.Cyvus:BAABLgAECn8kAAMKAAgJawVZQwArAQAKAAgJawVZQwArAQAOAAYJ+wktTQDbAAAAAA==.',
Da='Dab:BAABLgAECn9BAAIPAAkJhSWhBABZAwAPAAkJhSWhBABZAwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMQAAkJER8LEgCnAgAQAAgJtx8LEgCnAgAEAAkJ9RgADABiAgAAAA==.Daisy:BAAALgADCgEJAQAAAA==.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgARABQaAA==.Darkhorse:BAABLgAECn8mAAISAAgJwh6RDABdAgASAAgJwh6RDABdAgAAAA==.Darkmer:BAABLgAECn88AAIPAAkJ9wlviABTAQAPAAkJ9wlviABTAQAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAITAAkJahBrGgB+AQATAAkJahBrGgB+AQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgcJCwAAAA==.Dsntdrptotem:BAABLgAECn8yAAMUAAkJVBUhJADGAQAUAAkJ2xIhJADGAQAVAAcJ2BGDEwCBAQAAAA==.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgAECgEJAQAAAA==.',
Ep='Epicamerican:BAAALgAECgUJBwAAAA==.',
Ff='Ffecanti:BAAALgAECgcJDwAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gabrièl:BAAALgAECgEJAQAAAA==.Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAIWAAgJDRZnIgDHAQAWAAgJDRZnIgDHAQABLgAFFAkJLQAQAPUaAA==.Gorberfn:BAAALgAECgMJAwABLgAFFAkJLQAQAPUaAA==.',
Gr='Greenspot:BAAALgAECgYJCwABLgAECgkJPAAPAPcJAA==.Grimorn:BAACLgAFFH8nAAIPAAkJ8h/xAABGAgAPAAkJ8h/xAABGAgAuAAQKfykAAg8ACQnAIcADAJkDAA8ACQnAIcADAJkDAAAA.Grogvald:BAABLgAECn8xAAIRAAkJXCL5AgB0AwARAAkJXCL5AgB0AwAAAA==.',
Gu='Guang:BAAALgADCgEJAQAAAA==.',
['Gø']='Gøober:BAACLgAFFH8tAAQQAAkJ9RrMDAADAgAXAAYJ4RucAwAPAgAQAAgJ8hrMDAADAgAEAAMJICHiFwATAQAuAAQKf0IABBcACQlCJoMDAG0DABcACQkUIYMDAG0DAAQACQnlIMIFAMkCABAABwmqJPsdAHICAAAA.',
Ha='Hadrick:BAAALgAFFAEJAQAAAA==.',
He='Herax:BAABLgAECn8hAAIUAAgJ4xqeHQD0AQAUAAgJ4xqeHQD0AQAAAA==.',
Hi='Hidrógeno:BAACLgAFFH8FAAINAAMJLgxfegDBAAANAAMJLgxfegDBAAAuAAQKfxcAAg0ACAkrHssxAFsCAA0ACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBgABLgAECggJKAAMALoWAA==.',
Ho='Hoofartted:BAACLgAFFH8GAAIVAAMJUhjqDQDgAAAVAAMJUhjqDQDgAAAuAAQKfzsAAhUACQkII2kEAKsCABUACQkII2kEAKsCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Ib='Ibite:BAAALgAECgEJAQAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAMJDAASAPgZAA==.',
Io='Io:BAAALgAFFAEJAQABLgAFFAUJDQAIAEshAA==.',
Is='Istarìa:BAAALgAECgEJAQAAAA==.',
Ja='Jachen:BAAALgADCgMJAwAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIYAAkJLhbFPwAdAgAYAAkJLhbFPwAdAgAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIZAAcJ4x0cKACQAQAZAAcJ4x0cKACQAQAAAA==.',
Ki='Kijana:BAABLgAFFH8IAAIQAAQJ6iS6IACCAQAQAAQJ6iS6IACCAQABLgAFFAkJKQAQAFofAA==.Kindraa:BAAALgAECgEJAQAAAA==.',
La='Laherrmosa:BAAALgAECgQJBQAAAA==.Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leftarm:BAAALgAECgQJBAAAAA==.Leveltwo:BAACLgAFFH8GAAIEAAMJiRGiDAClAAAEAAMJiRGiDAClAAAuAAQKf1QABAQACQkmHwwBAEACAAQACQkmHwwBAEACABcAAQkWERg7ADUAABAAAQlWBERJASkAAAAA.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn9LAAILAAkJFRU2FQAxAgALAAkJFRU2FQAxAgAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAaALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
['Lì']='Lìly:BAAALgAECgYJBwAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQABLgAECgMJAwAbAAAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgUJBgAAAA==.',
My='Myrddraal:BAAALgAECgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgMJBgAAAA==.Nastybob:BAABLgAECn8zAAIPAAkJtyRACAAxAwAPAAkJtyRACAAxAwAAAA==.',
Ni='Nicobulus:BAABLgAECn8hAAIUAAkJHBBELACUAQAUAAkJHBBELACUAQAAAA==.Nightsblack:BAAALgADCggJDwAAAA==.Nightspell:BAAALgAECgYJDgAAAA==.',
No='Nor:BAABLgAECn8XAAMRAAcJ7B3DHAAvAgARAAYJmSDDHAAvAgANAAYJjhX8pgAtAQAAAA==.',
['Nä']='Näota:BAAALgAECgUJBQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8sAAIYAAkJIRw7AwBHAgAYAAkJIRw7AwBHAgAuAAQKfykAAhgACQkBJDkDAMsDABgACQkBJDkDAMsDAAAA.',
Ph='Phcicoknight:BAAALgAECgEJAQAAAA==.Pheal:BAABLgAECn8hAAMPAAgJ2hWaWwC0AQAPAAgJ2hWaWwC0AQAcAAEJAxM1OQA4AAAAAA==.Phiend:BAAALgAECgQJEQAAAA==.Phlak:BAABLgAECn8UAAIaAAYJVAv2dgD5AAAaAAYJVAv2dgD5AAAAAA==.',
Pl='Pluvl:BAABLgAECn8eAAISAAkJkQOdKwA8AQASAAkJkQOdKwA8AQAAAA==.',
['Pö']='Pöstal:BAAALgAECgEJAgAAAA==.',
Qu='Quimby:BAABLgAECn8ZAAMMAAkJZQwjBwBcAQAMAAkJZQwjBwBcAQAdAAEJAACCVQAAAAAAAA==.',
Ra='Raign:BAAALgAECgcJEwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAkJMAASAKMZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCQAAAA==.Rivia:BAABLgAECn8cAAINAAgJrBz2QQAfAgANAAgJrBz2QQAfAgAAAA==.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Saannthh:BAAALgAECgcJBwAAAA==.Safaridan:BAABLgAECn8eAAQRAAkJFBpWGQBIAgARAAkJFBpWGQBIAgAeAAUJXgwIMwCXAAANAAIJegf7sQEpAAAAAA==.Saimie:BAAALgAECgkJBgAAAA==.Saintjoe:BAAALgAECgEJAQAAAA==.Sapphirre:BAAALgAECgYJBgAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAgAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgUJCwAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIJAAgJXyCjBgD8AgAJAAgJXyCjBgD8AgAAAA==.',
Sk='Skass:BAAALgAECgIJAgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAINAAcJsCC4MQBcAgANAAcJsCC4MQBcAgAAAA==.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBQAAAA==.Sloan:BAABLgAECn8dAAILAAYJFwTDTQDMAAALAAYJFwTDTQDMAAAAAA==.',
So='Sodadragon:BAAALgAECgUJBQABLgAECgkJMgAUAFQVAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAwABLgAFFAkJKAAfAHsZAA==.',
Sq='Squirrelydan:BAAALgAECgYJDAAAAA==.',
Sr='Srgalahad:BAAALgAECgkJCgABLgAECgkJPAAPAPcJAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLwAOAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Sticky:BAAALgAECgIJAwABLgAFFAQJCwAfAMcOAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8oAAIMAAgJuhajQADbAQAMAAgJuhajQADbAQAAAA==.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgcJCgABLgAECggJKAAMALoWAA==.Tanglebones:BAABLgAECn82AAMgAAYJBw3FEQAJAQAgAAYJBw3FEQAJAQASAAYJPQd4OADvAAAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJGQAaAOsbAA==.Taukra:BAAALgADCgYJBgAAAA==.',
Te='Terribleone:BAAALgAFFAIJBAAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAbAAAAAA==.',
Tu='Turtles:BAAALgAECgMJBAAAAA==.',
Un='Unsocial:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAbAAAAAA==.Vermi:BAAALgAECgMJCAAAAA==.',
Vo='Voidfiend:BAAALgAECgMJAwAAAA==.',
Wa='Warcloud:BAABLgAECn8aAAIRAAkJEQRMRwAiAQARAAkJEQRMRwAiAQAAAA==.Wartortle:BAABLgAECn8wAAMBAAgJMhvoEADbAQABAAgJMhvoEADbAQACAAEJnQnygAApAAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgQJBwAAAA==.Wulfgaz:BAAALgAECggJEQAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECggJEQAbAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJDQAAAA==.',
Za='Zappytangle:BAAALgAECgYJDwAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgAECgMJBAAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIaAAgJhhjSNQDZAQAaAAgJhhjSNQDZAQAAAA==.',
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
