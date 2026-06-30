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

local lookup = {'Warrior-Fury','Hunter-Survival','Druid-Feral','Druid-Guardian','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Mage-Frost','Druid-Balance','Shaman-Restoration','Unknown-Unknown','DeathKnight-Frost','Warlock-Destruction','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgQJEQAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAgJLAABAHocAA==.',
Ar='Arasis:BAACLgAFFH8GAAICAAMJeRr7GAAKAQACAAMJeRr7GAAKAQAuAAQKfzUAAgIACQl5JR4CADEDAAIACQl5JR4CADEDAAAA.Arìel:BAAALgAECgYJCgAAAA==.',
As='Asexpected:BAAALgAECggJCQABLgAECgkJHgADAHsYAA==.Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAABLgAFFH8HAAIEAAIJShv4IACZAAAEAAIJShv4IACZAAAAAA==.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwABAAgJgSLxBgA5AwAAAA==.',
Bi='Bigmak:BAAALgAECgkJDAAAAA==.',
Bo='Boom:BAAALgAFFAkJBAAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgAECgEJAgAAAA==.',
Ce='Celestine:BAAALgAECgEJAQAAAA==.Cenobité:BAABLgAECn8rAAMFAAgJqCS2CQCpAgAFAAgJqCS2CQCpAgAGAAIJPxvvcAB/AAAAAA==.Ceridemon:BAABLgAECn8mAAIHAAkJbhDaHQCNAQAHAAkJbhDaHQCNAQAAAA==.',
Ch='Chingee:BAACLgAFFH8GAAMIAAYJ+QEvHQDPAAAIAAQJQgIvHQDPAAAJAAIJZgH/RgBXAAAuAAQKf0wAAwkACQnHGqIJAKECAAkACQnsGaIJAKECAAgACAmLDkAmALoBAAAA.',
Co='Cobalt:BAAALgAECgUJBQABLgAFFAMJCgAKADYbAA==.Cobel:BAAALgAECgMJAwAAAA==.Consarios:BAABLgAFFH8HAAILAAYJHRmvHQCRAQALAAYJHRmvHQCRAQAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8UAAMFAAQJIBOWIgDLAAAFAAMJhRSWIgDLAAAGAAMJbQrEOgC7AAAuAAQKfzUAAwUACQm7GroRADUCAAUACQlOGroRADUCAAYABAkeFC9OAMcAAAAA.Cyvus:BAABLgAECn8kAAMIAAgJawVZQwArAQAIAAgJawVZQwArAQAMAAYJ+wktTQDbAAAAAA==.',
Da='Dab:BAABLgAECn9BAAINAAkJhSWhBABZAwANAAkJhSWhBABZAwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMOAAkJER8LEgCnAgAOAAgJtx8LEgCnAgACAAkJ9RgADABiAgAAAA==.Daisy:BAAALgADCgEJAQAAAA==.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgAPABQaAA==.Darkhorse:BAABLgAECn8mAAIQAAgJwh6RDABdAgAQAAgJwh6RDABdAgAAAA==.Darkmer:BAABLgAECn87AAINAAkJ9wlviABTAQANAAkJ9wlviABTAQAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAIRAAkJahBrGgB+AQARAAkJahBrGgB+AQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgcJCwAAAA==.Dsntdrptotem:BAABLgAECn8xAAMSAAkJVBUhJADGAQASAAkJ2xIhJADGAQATAAcJ2BGDEwCBAQAAAA==.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgAECgEJAQAAAA==.',
Ep='Epicamerican:BAAALgAECgUJBwAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAIUAAgJDRZnIgDHAQAUAAgJDRZnIgDHAQABLgAFFAkJKgAOANwXAA==.Gorberfn:BAAALgAECgMJAwABLgAFFAkJKgAOANwXAA==.',
Gr='Greenspot:BAAALgAECgYJBgABLgAECgkJOwANAPcJAA==.Grimorn:BAACLgAFFH8kAAINAAkJFx7xAABGAgANAAkJFx7xAABGAgAuAAQKfykAAg0ACQnAIcADAJkDAA0ACQnAIcADAJkDAAAA.Grogvald:BAABLgAECn8uAAIPAAgJPSb5AgB0AwAPAAgJPSb5AgB0AwAAAA==.',
Gu='Guang:BAAALgADCgEJAQAAAA==.',
['Gø']='Gøober:BAACLgAFFH8qAAQOAAkJ3BfMDAADAgAVAAYJ4RucAwAPAgAOAAgJZxfMDAADAgACAAMJICHiFwATAQAuAAQKf0IABBUACQlCJoMDAG0DABUACQkUIYMDAG0DAAIACQnlIMIFAMkCAA4ABwmqJPsdAHICAAAA.',
Ha='Hadrick:BAAALgAFFAEJAQAAAA==.',
He='Herax:BAABLgAECn8hAAISAAgJ4xqeHQD0AQASAAgJ4xqeHQD0AQAAAA==.',
Hi='Hidrógeno:BAACLgAFFH8FAAILAAMJLgxfegDBAAALAAMJLgxfegDBAAAuAAQKfxcAAgsACAkrHssxAFsCAAsACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBgABLgAECggJKAAKALoWAA==.',
Ho='Hoofartted:BAACLgAFFH8GAAITAAMJUhjqDQDgAAATAAMJUhjqDQDgAAAuAAQKfzkAAhMACAnOI2kEAKsCABMACAnOI2kEAKsCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Ib='Ibite:BAAALgAECgEJAQAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAMJDAAQAPgZAA==.',
Is='Istarìa:BAAALgAECgEJAQAAAA==.',
Ja='Jachen:BAAALgADCgMJAwAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIWAAkJLhbFPwAdAgAWAAkJLhbFPwAdAgAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIXAAcJ4x0cKACQAQAXAAcJ4x0cKACQAQAAAA==.',
Ki='Kijana:BAABLgAFFH8IAAIOAAQJ6iS6IACCAQAOAAQJ6iS6IACCAQABLgAFFAkJIwAOAPcZAA==.Kindraa:BAAALgADCgkJKgAAAA==.',
La='Laherrmosa:BAAALgAECgQJBQAAAA==.Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAACLgAFFH8GAAICAAMJiRFeBwCxAAACAAMJiRFeBwCxAAAuAAQKf0wABAIACQl3HpEGALcCAAIACQl3HpEGALcCABUAAQkWERg7ADUAAA4AAQlWBERJASkAAAAA.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn9LAAIJAAkJFRU2FQAxAgAJAAkJFRU2FQAxAgAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAYALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
['Lì']='Lìly:BAAALgAECgEJAgAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQABLgAECgMJAwAZAAAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgUJBgAAAA==.',
My='Myrddraal:BAAALgAECgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgMJBQAAAA==.Nastybob:BAABLgAECn8zAAINAAkJtyRACAAxAwANAAkJtyRACAAxAwAAAA==.',
Ni='Nicobulus:BAABLgAECn8hAAISAAkJHBBELACUAQASAAkJHBBELACUAQAAAA==.Nightsblack:BAAALgADCggJCAAAAA==.Nightspell:BAAALgAECgYJDgAAAA==.',
No='Nor:BAABLgAECn8XAAMPAAcJ7B3DHAAvAgAPAAYJmSDDHAAvAgALAAYJjhX8pgAtAQAAAA==.',
['Nä']='Näota:BAAALgAECgUJBQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8pAAIWAAkJXxU7AwBHAgAWAAkJXxU7AwBHAgAuAAQKfykAAhYACQkBJDkDAMsDABYACQkBJDkDAMsDAAAA.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMNAAgJ2hWaWwC0AQANAAgJ2hWaWwC0AQAaAAEJAxM1OQA4AAAAAA==.Phiend:BAAALgAECgQJEQAAAA==.Phlak:BAABLgAECn8UAAIYAAYJVAv2dgD5AAAYAAYJVAv2dgD5AAAAAA==.',
Pl='Pluvl:BAABLgAECn8eAAIQAAkJkQOdKwA8AQAQAAkJkQOdKwA8AQAAAA==.',
['Pö']='Pöstal:BAAALgAECgEJAgAAAA==.',
Qu='Quimby:BAABLgAECn8ZAAMKAAkJcQyYAwBuAQAKAAkJcQyYAwBuAQAbAAEJAACCVQAAAAAAAA==.',
Ra='Raign:BAAALgAECgcJEwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAgJHgAQAJIWAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAILAAgJrBz2QQAfAgALAAgJrBz2QQAfAgAAAA==.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Saannthh:BAAALgAECgcJBwAAAA==.Safaridan:BAABLgAECn8eAAQPAAkJFBpWGQBIAgAPAAkJFBpWGQBIAgAcAAUJXgwIMwCXAAALAAIJegf7sQEpAAAAAA==.Saimie:BAAALgAECgkJBgAAAA==.Saintjoe:BAAALgAECgEJAQAAAA==.Sapphirre:BAAALgAECgYJBgAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAgAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgUJCwAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIHAAgJXyCjBgD8AgAHAAgJXyCjBgD8AgAAAA==.',
Sk='Skass:BAAALgAECgIJAgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAILAAcJsCC4MQBcAgALAAcJsCC4MQBcAgAAAA==.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBQAAAA==.Sloan:BAABLgAECn8dAAIJAAYJFwTDTQDMAAAJAAYJFwTDTQDMAAAAAA==.',
So='Sodadragon:BAAALgAECgEJAQABLgAECgkJMQASAFQVAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAwABLgAFFAkJJQAdAEIYAA==.',
Sq='Squirrelydan:BAAALgAECgEJAQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLwAMAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Sticky:BAAALgAECgIJAwABLgAFFAQJCwAUAN8RAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8oAAIKAAgJuhajQADbAQAKAAgJuhajQADbAQAAAA==.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgcJCgABLgAECggJKAAKALoWAA==.Tanglebones:BAABLgAECn82AAMeAAYJBw3FEQAJAQAeAAYJBw3FEQAJAQAQAAYJPQd4OADvAAAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJGQAYAOsbAA==.Taukra:BAAALgADCgYJBgAAAA==.',
Te='Terribleone:BAAALgAFFAIJAgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAZAAAAAA==.',
Tu='Turtles:BAAALgADCgEJAQAAAA==.',
Un='Unsocial:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAZAAAAAA==.Vermi:BAAALgAECgMJCAAAAA==.',
Wa='Warcloud:BAABLgAECn8aAAIPAAkJEQRMRwAiAQAPAAkJEQRMRwAiAQAAAA==.Wartortle:BAABLgAECn8wAAMfAAgJMhvoEADbAQAfAAgJMhvoEADbAQAgAAEJnQnygAApAAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgQJBwAAAA==.Wulfgaz:BAAALgAECgcJEAAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgcJEAAZAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJDQAAAA==.',
Za='Zappytangle:BAAALgAECgYJDwAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgAECgMJBAAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIYAAgJhhjSNQDZAQAYAAgJhhjSNQDZAQAAAA==.',
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
