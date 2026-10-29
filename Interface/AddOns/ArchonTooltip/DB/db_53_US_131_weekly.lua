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

local lookup = {'Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Druid-Feral','Druid-Guardian','Shaman-Elemental','Warlock-Demonology','DeathKnight-Blood','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','Hunter-Marksmanship','Shaman-Restoration','Evoker-Preservation','Monk-Mistweaver','Monk-Windwalker','Hunter-Survival','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','Warrior-Fury','Monk-Brewmaster','Warrior-Protection','Shaman-Enhancement','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Advîl:BAABNQAECn8tAAIBAAoKDR2HDAACAwABAAoKDR2HDAACAwAAAA==.',
Ae='Aeryhnn:BAAANQADCgcIHwABNQAECgQIEwACAAAAAA==.',
Al='Alarogue:BAAANQAECgYIBgAAAA==.Alexandre:BAABNQAECn8dAAIDAAkKXhBqlgDbAQADAAkKXhBqlgDbAQAAAA==.Allasia:BAAANQADCgcIBgAAAA==.Alterboy:BAAANQADCgIIAgABNQAECggIJAABAMciAA==.Alton:BAABNQAECn8xAAIBAAoKSg9hWAAQAgABAAoKSg9hWAAQAgAAAA==.',
Am='Amoonsia:BAAANQAECgQICAAAAA==.',
An='Anfernyphere:BAABNQAECn8VAAMBAAgKyx7VLQCvAgABAAgKyx7VLQCvAgAEAAQK8w/PHwHqAAABNQAECgQIBwACAAAAAA==.Ansuz:BAAANQAECgIIBwAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQAECgEIAgAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAABNQAECn8iAAMFAAgKUBPECwB5AQAFAAgKUBPECwB5AQAGAAYKRwtGMwAHAQAAAA==.Aristia:BAAANQADCggIDgABNQAECgoKJwAHADIQAA==.Arweni:BAAANQAECgIIAgAAAA==.',
At='Atheizt:BAABNQAECn8eAAIBAAkKcRtgJwDLAgABAAkKcRtgJwDLAgAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Bakachan:BAAANQAECgIIAwAAAA==.Baldilocks:BAAANQADCgQIBAAAAA==.Banedon:BAAANQADCgMJBQABNQAECggIJAABAMciAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIEAACAAAAAA==.Beastmaster:BAAANQAECgMIAwAAAA==.Beetingu:BAAANQADCgcIFgABNQAECggIIAAIAHkjAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAABNQAECn8sAAIGAAkKhSVKBwASAwAGAAkKhSVKBwASAwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.Billd:BAAANQAECgEIAQAAAA==.',
Bl='Blacken:BAABNQAECn8aAAIJAAcKxhhLLgA2AQAJAAcKxhhLLgA2AQAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgQIBwABNQAFFAIIBgAKAAkjAA==.Blakylightz:BAAANQAFFAIIAgAAAA==.Blazen:BAABNQAECn8qAAIHAAoK/x9/IAAJAwAHAAoK/x9/IAAJAwAAAA==.Blinker:BAABNQAECn8aAAILAAgKwwsNDgApAQALAAgKwwsNDgApAQAAAA==.Bloodynuts:BAABNQAECn8cAAMMAAkKqhOAFwAiAgAMAAgKURSAFwAiAgANAAIKzhImjwB1AAAAAA==.Bloyfbloyf:BAACNQAFFH8HAAIOAAQKzgS+CwCmAAAOAAQKzgS+CwCmAAA1AAQKfyIAAg4ACgrPE0gaAMwBAA4ACgrPE0gaAMwBAAAA.Blueshadøw:BAAANQAECgEIAgAAAA==.',
Bo='Bobbidyboo:BAACNQAFFH8UAAIPAAUKSgftBQAyAQAPAAUKSgftBQAyAQA1AAQKfz0AAg8ACgoVE+4kAPwBAA8ACgoVE+4kAPwBAAAA.Bonesclone:BAAANQAECgIIAwAAAA==.',
Br='Brewshido:BAAANQAECgIIBAAAAA==.Briareosx:BAABNQAECn8yAAIQAAoKLBv8SACvAgAQAAoKLBv8SACvAgAAAA==.Brixtia:BAAANQADCgcIBgABNQAECgkJKgARAKwUAA==.Brovar:BAACNQAFFH8WAAIEAAUKMB61CwCOAQAEAAUKMB61CwCOAQA1AAQKfz0AAgQACgrEIzIWAGwDAAQACgrEIzIWAGwDAAAA.',
Bu='Bubbaa:BAABNQAECn8hAAMSAAkKrR/+IQDgAgASAAkKrR/+IQDgAgAHAAEKAAAMJAFJAAAAAA==.Buddydaelf:BAABNQAECn8gAAIDAAkK5hXKXwBXAgADAAkK5hXKXwBXAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgkJKQATAAcQAA==.',
Ce='Ceanaflowers:BAABNQAECn8ZAAIQAAoKrRBwjAD9AQAQAAoKrRBwjAD9AQAAAA==.',
Ch='Challah:BAAANQAECgMIAwAAAA==.Chia:BAABNQAECn8jAAMUAAkKkBR9GQDnAQAUAAkKkBR9GQDnAQAVAAIKnQaEYQBZAAABNQADCgMIAwACAAAAAA==.Chianamoya:BAAANQADCgYICwABNQAECgQIEwACAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clairvoyant:BAAANQAECgEIAQAAAA==.Clarisse:BAAANQAECgIIBAABNQAECgoKOQAJAJUZAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQAECgMICAAAAA==.Coolarrow:BAABNQAECn8kAAIDAAkKoRi0PwDkAQADAAkKoRi0PwDkAQABNQAFFAQIEAADAIIaAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAAANQAECgYIDAAAAA==.Crosshair:BAABNQAECn8VAAMWAAYKghC0CQCQAQAWAAYKghC0CQCQAQARAAEKXAHingAfAAAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAcIFQAIAMIQAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgoKMQAXALkdAA==.',
['Cê']='Cêlaçane:BAAANQAECgEIAQAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECgYIDgAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davaeh:BAAANQADCgIIAgABNQAECggIJAABAMciAA==.Davandar:BAAANQADCgYIDAAAAA==.Daveah:BAABNQAECn8jAAISAAgKwgkCVQBEAQASAAgKwgkCVQBEAQAAAA==.',
De='Deathberry:BAABNQAECn8qAAIIAAgK6AxukAC9AQAIAAgK6AxukAC9AQAAAA==.Deathsmoke:BAAANQADCgEIAQAAAA==.Delphron:BAAANQAECgIIBQAAAA==.Demoncharge:BAAANQAECgEIAwABNQAECgEIAwACAAAAAA==.Demonflayer:BAAANQAECgEIAwAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAwACAAAAAA==.Denaeaa:BAABNQAECn8YAAMUAAcKYBeXGQDmAQAUAAcKYBeXGQDmAQAVAAIKlgCTTQAkAAABNQAFFAQICAASAIAFAA==.Depala:BAAANQADCgcIEAABNQAECgIIAgACAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECn8qAAMHAAoKAhVVQgBLAQAHAAkKbhRVQgBLAQASAAEKvgHO2AAiAAAAAA==.',
Dh='Dharmakat:BAAANQADCgUIBQAAAA==.',
Di='Dist:BAAANQAECgMICQAAAA==.Divinestorm:BAABNQAECn8kAAMBAAgKxyLkFACeAgABAAcKMiLkFACeAgAEAAYKEA0wCAERAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Dn='Dnyal:BAAANQAECggICAAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgoKPAAQAJUmAA==.Dogbreathrlz:BAAANQAECgEIAQAAAA==.Dolomite:BAAANQAECgEIAgAAAA==.Dookerslol:BAAANQADCgUIAwAAAA==.Dotexe:BAABNQAECn8lAAINAAcKCxyCEACBAQANAAcKCxyCEACBAQAAAA==.Dotsy:BAACNQAFFH8YAAQYAAUKnBycAAAOAQAYAAUKJBycAAAOAQAIAAQKMx/XFACpAAAZAAEKlxOOGgBQAAA1AAQKfz0ABBkACgrsIFgTANcBAAgACQrPIJUzALsCABkABgoXH1gTANcBABgABwpPHKUGAFYBAAAA.',
Dr='Drackarys:BAAANQADCgcIIgAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAACNQAFFH8GAAMKAAIKCSPHAgC7AAAKAAIKCSPHAgC7AAATAAIKMyCeDACWAAA1AAQKfzwAAxMACgqxIU4DAIMDABMACgqxIU4DAIMDAAoACAqpIH4PAGICAAAA.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECn8pAAMTAAkKBxAtIgC6AQATAAkKBxAtIgC6AQAKAAcKcw2QIQBCAQAAAA==.Dravas:BAAANQAECgUIDAAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQAECgEIAQAAAA==.Drzark:BAAANQAECgQIEAAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECggIHgASACQcAA==.',
Dw='Dwdog:BAABNQAECn8bAAIYAAYKgw+NBwA4AQAYAAYKgw+NBwA4AQAAAA==.',
['Dà']='Dàthguy:BAABNQAECn82AAIaAAoKsSNpAwC+AwAaAAoKsSNpAwC+AwAAAA==.',
['Dé']='Défault:BAABNQAECn8yAAMaAAoKIh4wEwAfAwAaAAoKIh4wEwAfAwAbAAQKOA0hcwDTAAAAAA==.',
Ed='Edaras:BAAANQAECgEIBgAAAA==.',
El='Elek:BAAANQAECgYIDQABNQAFFAMIBQAZAKIQAA==.Elennie:BAAANQAECgIIAgAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAABNQAECn8eAAIaAAcKmxnnQwALAgAaAAcKmxnnQwALAgAAAA==.',
En='Enyo:BAABNQAECn8lAAIcAAgK4RUnJgAUAgAcAAgK4RUnJgAUAgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQAECgEIAQAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Ex='Excalipoor:BAAANQADCgIIAQAAAA==.',
Fa='Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggIDgABNQAECggIEQACAAAAAA==.Felsmoke:BAAANQADCgYIBgAAAA==.Fervid:BAABNQAECn8dAAIdAAgKuQ+KiwAsAQAdAAgKuQ+KiwAsAQAAAA==.Feylen:BAABNQAECn8wAAIdAAoK4SUkCgCvAwAdAAoK4SUkCgCvAwAAAA==.',
Fi='Fido:BAABNQAECn8iAAIJAAgKHxGXLwAwAQAJAAgKHxGXLwAwAQAAAA==.Fidø:BAAANQADCgUIDwABNQAECggIIgAJAB8RAA==.Fifthelement:BAABNQAECn8qAAISAAkK0iBtFwCJAgASAAkK0iBtFwCJAgAAAA==.Figgson:BAAANQADCgQIBAAAAA==.Figgy:BAABNQAECn8lAAISAAgK7hYEOgCyAQASAAgK7hYEOgCyAQAAAA==.Fiorstrasza:BAABNQAECn8iAAMTAAkKQhJzDgCNAQATAAkKQhJzDgCNAQAKAAIKbwZNNgBcAAAAAA==.Firry:BAAANQADCgYIEgAAAA==.Fistsofsmoke:BAAANQADCgUICAAAAA==.',
Fj='Fjalgeirr:BAABNQAECn8qAAMOAAkKnQxIKwBDAQAOAAkKnQxIKwBDAQAeAAEKAADSPQAFAAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAABNQAECn8jAAIfAAcKCRlsRwCTAQAfAAcKCRlsRwCTAQAAAA==.',
Fr='Freaksbetter:BAAANQADCgcIBwAAAA==.Froot:BAAANQAECgUIEAAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECn82AAIEAAoK/B/GLgAOAwAEAAoK/B/GLgAOAwAAAA==.',
Ga='Gaëll:BAAANQAECgEIAQAAAA==.',
Ge='Gearsprocket:BAAANQAECgYIEgABNQAECgoKMQABAEoPAA==.Geosmin:BAABNQAECn8bAAISAAkKsBAuYwDkAQASAAkKsBAuYwDkAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECgoKMQABAEoPAA==.',
Gh='Ghue:BAABNQAECn8cAAMXAAkKpwrBGQAxAQAXAAkKsQjBGQAxAQAEAAYKMwzQAgEbAQAAAA==.Ghòst:BAAANQAECgIIAwAAAA==.',
Gi='Gilalade:BAABNQAECn8eAAIDAAcKlxcHjQDwAQADAAcKlxcHjQDwAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQAECgIIAgABNQAECgoKKAAKAEcYAA==.',
Go='Gobann:BAAANQADCgYIBgABNQAECgkJKgARAKwUAA==.Gonern:BAABNQAECn8xAAMXAAoKuR3QCgDuAgAXAAoK9xzQCgDuAgAEAAkKBxcEpwDSAQAAAA==.Gooby:BAACNQAFFH8SAAIfAAUKdxY5EACSAQAfAAUKdxY5EACSAQA1AAQKfxsAAx8ACgpmF+UjAEkCAB8ACgpmF+UjAEkCACAAAQrvAImTABUAAAAA.Goond:BAAANQAECgcIDQABNQAFFAMIBQAZAKIQAA==.Gooney:BAAANQAECgIIAgAAAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQABCggIGgAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIEAACAAAAAA==.Grlfriend:BAAANQAECgQICQAAAA==.Grodin:BAAANQADCgYIDwAAAA==.Grofiest:BAABNQAECn8mAAMgAAkKpQ7wGABMAQAgAAkKpQ7wGABMAQAfAAEKoAFi1QAbAAAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECgoKPAAQAJUmAA==.Guggychan:BAABNQAECn88AAMQAAoKlSbpAgDkAwAQAAoKdSbpAgDkAwAhAAMKTSbXEADdAAAAAA==.Gunslinger:BAAANQAECgEIAgAAAA==.Gunsmoke:BAAANQAECgEIAgAAAA==.',
Gw='Gwynbleidd:BAABNQAECn89AAIJAAoKXw7kIQCEAQAJAAoKXw7kIQCEAQAAAA==.',
Ha='Hadrian:BAAANQADCgYIDwAAAA==.Haldor:BAAANQADCgcIBwAAAA==.Hanohakua:BAAANQADCgcIDgAAAA==.Haohmaru:BAABNQAECn8jAAIiAAcKfh89CgByAgAiAAcKfh89CgByAgAAAA==.Harthen:BAAANQADCgcIGAABNQAECggIIgAFAFATAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAABNQAECn8WAAQhAAcKHhQEGQARAQAQAAYK2xBL4AApAQAhAAQKOhsEGQARAQAjAAEK8gyJRwAmAAAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAABNQAECn8eAAIEAAkK9QjU1QBwAQAEAAkK9QjU1QBwAQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECggIEAAAAA==.Holypower:BAAANQADCgcIBwAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIEgAAAA==.Huneyhunter:BAABNQAECn8dAAIFAAYKHAeYIgD8AAAFAAYKHAeYIgD8AAAAAA==.',
Ic='Ichigozero:BAAANQADCgQIBgAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgUICwAAAA==.',
Ir='Ironaxe:BAABNQAECn8pAAIDAAkK+wp/pgC5AQADAAkK+wp/pgC5AQAAAA==.',
It='Itsademon:BAAANQAECgYICgAAAA==.',
Ja='Jaeksoolie:BAABNQAECn8XAAMkAAgKxg/iFgD7AQAkAAgKxg/iFgD7AQAHAAEKAACxOgExAAAAAA==.Jaks:BAAANQAECgEIAQAAAA==.Jakyro:BAABNQAECn8jAAMTAAcKNQjJLABAAQATAAcKNQjJLABAAQAKAAYK/A4gDwDiAAAAAA==.Javeech:BAABNQAECn8eAAIEAAcKlhqtlwD0AQAEAAcKlhqtlwD0AQAAAA==.Jaypark:BAABNQAECn8dAAIVAAkK7BX0HgA5AgAVAAkK7BX0HgA5AgAAAA==.Jayse:BAABNQAECn8ZAAMhAAoKfgmlFABVAQAhAAoKWwmlFABVAQAQAAQK8gR2HQGhAAABNQAECgoKJQAHAKAhAA==.',
Jc='Jchaotic:BAAANQAECgEIAgAAAA==.',
Je='Jeezus:BAAANQAECgQIBQABNQAFFAYICgAJAGwVAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUICgAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAABNQAECn8nAAMMAAoKhBeoGQBQAgAMAAoKcheoGQBQAgANAAEK6RCCVAA/AAAAAA==.',
Ju='Juanda:BAAANQAFFAEIAQAAAA==.Junghee:BAABNQAECn84AAMUAAoKoyO0BgAsAwAUAAoKoyO0BgAsAwAVAAcK9hQeLQCwAQAAAA==.Juudaz:BAACNQAFFH8KAAIJAAYKbBWdEgAtAQAJAAYKbBWdEgAtAQA1AAQKf1QABBoACgqQJJECADoDABoACgorJJECADoDAAkACgpmIHQYAOoCABsABwqwFeNCALkBAAAA.',
['Jï']='Jïnx:BAABNQAECn8pAAIHAAkKriFqIQAEAwAHAAkKriFqIQAEAwAAAA==.',
Ka='Kaalhvel:BAAANQAECgYIEgAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAABNQAECn8jAAQBAAcK9RzdSABDAgABAAcK9RzdSABDAgAEAAQKGgv57wCVAAAXAAEKLQuhTgAtAAAAAA==.Kapkywa:BAABNQAECn8iAAIPAAoK7yDsAQC5AwAPAAoK7yDsAQC5AwABNQAECgkJHgABAHEbAA==.Kasherquon:BAAANQAECgUIDQAAAA==.Katsumyo:BAAANQADCggIGQAAAA==.Kawaiimonsta:BAAANQADCggICAAAAA==.',
Ke='Kellyx:BAAANQAECgMIBAAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAABNQAECn8aAAIHAAYK7QSGhwCPAAAHAAYK7QSGhwCPAAAAAA==.Kisuke:BAAANQAECgUIBQABNQAECgoKPAAQAJUmAA==.Kiyara:BAABNQAECn8wAAIDAAoKNhJZMAAeAgADAAoKNhJZMAAeAgAAAA==.Kizaki:BAABNQAECn8VAAIcAAYKyx2eKQD2AQAcAAYKyx2eKQD2AQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAFFAIIBgAKAAkjAA==.',
Kr='Krelliz:BAABNQAECn8sAAMSAAgK7xKwbADFAQASAAgK7xKwbADFAQAHAAYKIgceZADhAAAAAA==.Kristiné:BAAANQAECgEIAQAAAA==.Krolly:BAAANQAECgQICwAAAA==.Krystar:BAAANQAECgYIEQAAAA==.',
Ku='Kungfuwho:BAABNQAECn8lAAQUAAoKTgu2IQB5AQAUAAoKTgu2IQB5AQAVAAUK/QdbTwC4AAAiAAEKAADbNgAdAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgYIFQAcAMsdAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgIIAwAAAA==.',
Le='Leksa:BAAANQAECgEIAQAAAA==.Lenaea:BAACNQAFFH8IAAISAAQKgAXNDgDzAAASAAQKgAXNDgDzAAA1AAQKfzoAAxIACgoBFjZBAFwCABIACgoBFjZBAFwCAAcAAgrLCUcVAWMAAAAA.',
Li='Liiege:BAAANQAECggIEAABNQAFFAIIBgAKAAkjAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAABNQAECn8nAAMXAAoKbRkUDQDTAQAXAAoKbRkUDQDTAQAEAAEKAADYdAEAAAABNQAECgoKOQAJAJUZAA==.',
Lo='Lobø:BAABNQAECn8gAAIDAAcKvhI6jADyAQADAAcKvhI6jADyAQAAAA==.Lowtierscrub:BAAANQAECgUIBwABNQAECgoKGQAQAK0QAA==.',
Lu='Luccyy:BAAANQADCgQICwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAABNQAECn8kAAIaAAkKkA2/VwCxAQAaAAkKkA2/VwCxAQAAAA==.Luth:BAAANQADCggICAABNQAECgYIEQACAAAAAA==.Luthex:BAAANQAECgYIEQAAAA==.',
Ly='Lylacy:BAABNQAECn89AAIIAAoKkw9pNQDVAQAIAAoKkw9pNQDVAQAAAA==.Lyrea:BAAANQAECgEIAQAAAA==.',
Ma='Madscience:BAABNQAECn8lAAIdAAgKJAW9vgDLAAAdAAgKJAW9vgDLAAAAAA==.Magiicae:BAAANQADCgIIAgABNQAFFAIIBgAKAAkjAA==.Magoliko:BAAANQAECgEIAgAAAA==.Manatee:BAAANQAECgEIAQAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECn8oAAIPAAgKJRuiEQALAgAPAAgKJRuiEQALAgAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAABNQAECn8xAAMhAAoKIBGYBgDOAQAhAAoKIBGYBgDOAQAjAAYKIwqUHACrAAAAAA==.Meowmeowmew:BAAANQADCgUIBQABNQAECggIJAABAMciAA==.',
Mi='Minjae:BAAANQAECgUIEAABNQAECgoKMwAZAO8UAA==.Misfirë:BAAANQAECgQIDQABNQAECgoKMgAaACIeAA==.',
Mo='Mogwaí:BAABNQAECn8aAAMUAAgK6xA6GAD8AAAUAAcKJg46GAD8AAAVAAIK7Qg7RwA5AAAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morrìgan:BAAANQAECgIIAgAAAA==.Morvane:BAAANQADCgYICQABNQAECgoKMQABAEoPAA==.Movack:BAABNQAECn8XAAIEAAcKwwph3wBcAQAEAAcKwwph3wBcAQAAAA==.Mowri:BAAANQAECgEIAgAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAABNQAECn8fAAMPAAcK/yFoHgBtAQAPAAQKzSBoHgBtAQAlAAcKVgrQXgBVAQAAAA==.',
My='Mytho:BAAANQAECgEIBwAAAA==.Mythunran:BAABNQAECn8lAAIRAAkK7Af+FQBjAQARAAkK7Af+FQBjAQAAAA==.',
['Mö']='Mörï:BAABNQAECn8aAAIEAAgK+wtqzwB8AQAEAAgK+wtqzwB8AQAAAA==.',
Na='Naethanial:BAAANQAECgYICwAAAA==.Nas:BAAANQAECgUICQAAAA==.Natalina:BAAANQADCgcJCgABNQAECgIIAgACAAAAAA==.Nav:BAAANQADCgUIBQAAAA==.Nax:BAAANQAECgYICwAAAA==.Naz:BAAANQADCgYIEQAAAA==.',
Ne='Nerfhammer:BAACNQAFFH8OAAIEAAUKFxtXDACEAQAEAAUKFxtXDACEAQA1AAQKfz8AAgQACgreJPEWAGkDAAQACgreJPEWAGkDAAAA.Nessalove:BAACNQAFFH8YAAIfAAUKjha/CQCQAQAfAAUKjha/CQCQAQA1AAQKfz0AAh8ACgrBHDo4AIcCAB8ACgrBHDo4AIcCAAAA.Neutrino:BAAANQAECgYIDgAAAA==.',
Ni='Nicolbowlass:BAABNQAECn8WAAMKAAgKjxAbCwA2AQAKAAcKRBIbCwA2AQAmAAEKBgjPJQAtAAAAAA==.Nightomen:BAAANQAECgEIAQABNQAECgcIHwAPAP8hAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICQABNQAECgUIEAACAAAAAA==.',
No='Noone:BAABNQAECn84AAMSAAoK1hKIJgAaAgASAAoK1hKIJgAaAgAHAAYKwQmltAApAQAAAA==.Noriel:BAAANQAECgYIEwAAAA==.',
Nz='Nz:BAAANQAECgcIDAAAAA==.',
Od='Oddeccentric:BAAANQAECgYIDQABNQAFFAYIFAAjAPcUAA==.',
Og='Ognyal:BAAANQAECggICAAAAA==.',
On='Onna:BAAANQADCgMIAwAAAA==.',
Op='Opali:BAAANQAECgYIEAAAAA==.',
Os='Osanar:BAAANQAFFAQIBAAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgoKNgAaALEjAA==.Overburned:BAAANQAECgEIAQAAAA==.Overshoot:BAABNQAECn8hAAIDAAkKZA/clQDcAQADAAkKZA/clQDcAQAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgQIBgABNQAECgkJJgAfAJMbAA==.Papimonk:BAAANQAECgMIAwABNQAECgkJIgASAIwcAA==.Parvarti:BAABNQAECn8lAAMZAAYKvwSQRwCpAAAZAAUKxgGQRwCpAAAIAAYKcgSgrwCSAAAAAA==.Pathogenic:BAABNQAECn8WAAIgAAYKWRMEOABlAQAgAAYKWRMEOABlAQAAAA==.',
Pe='Peluquin:BAAANQADCgIIAgAAAA==.Persimmoñ:BAAANQADCggJEgAAAA==.',
Ph='Philliesteak:BAAANQAECgEIAQAAAA==.',
Po='Polkadott:BAABNQAECn8gAAMIAAgKeSPLcQALAgAIAAYKKCTLcQALAgAZAAIKHCK9PgDHAAAAAA==.',
Pr='Presidìum:BAABNQAECn8eAAIXAAgKzhG7FgBNAQAXAAgKzhG7FgBNAQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAABNQAECn8kAAILAAkK0xyCBgCYAgALAAkK0xyCBgCYAgAAAA==.Provoked:BAAANQAECgQIBQABNQAECgoKHwASAEcZAA==.',
Ps='Psylocke:BAABNQAECn8rAAINAAkK7wxEEQB4AQANAAkK7wxEEQB4AQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUICQABNQAECgkJHAAMAKoTAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Rahuwu:BAAANQAECgMIAwABNQAECgoKPAAQAJUmAA==.Raveger:BAAANQADCgYIDwABNQAECggIJAABAMciAA==.',
Re='Reladin:BAABNQAECn8iAAIXAAcK7QsJNABDAQAXAAcK7QsJNABDAQAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIJwAAAA==.Renzr:BAABNQAECn8yAAMaAAkK6SBOHADiAgAaAAkKoh1OHADiAgAJAAcKPSNoHgC/AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgUICAABNQAFFAcIIQAKALsaAA==.',
Ro='Roag:BAABNQAECn8YAAIdAAcKYAqVvQDNAAAdAAcKYAqVvQDNAAAAAA==.Roley:BAABNQAECn8oAAIPAAoKfQ2CGQChAQAPAAoKfQ2CGQChAQAAAA==.Rowin:BAABNQAECn8VAAQPAAgKlgIYSQDuAAAPAAgKlgIYSQDuAAAFAAEKAAAQSQAoAAAlAAIKCAEpyAAaAAAAAA==.',
Ru='Rustedroots:BAAANQADCgUIBQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgcIDAABNQAECgQIEwACAAAAAA==.Sapphyre:BAAANQAECgEIAQAAAA==.Saristelonio:BAAANQAECgMIBAABNQAECgkJIAARAOYJAA==.Saristrix:BAABNQAECn8gAAIRAAkK5gk+GwAoAQARAAkK5gk+GwAoAQAAAA==.Sarnara:BAABNQAECn8pAAIXAAkKHxlIFQBXAgAXAAkKHxlIFQBXAgAAAA==.Satyria:BAAANQAECgQJBwAAAA==.Savagedeath:BAAANQAECgQIBQAAAA==.',
Se='Secord:BAABNQAECn8kAAIDAAYK2ALJAAEDAQADAAYK2ALJAAEDAQAAAA==.Senarx:BAAANQAECgEIAwAAAA==.Seonghwa:BAAANQADCgYIEAAAAA==.Sereniity:BAAANQADCgYIBgABNQAFFAIIBgAKAAkjAA==.Seriiez:BAAANQAECgEIBgAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgcIDAAAAA==.Shamous:BAAANQAECgEIAgAAAA==.Shampooh:BAAANQAECgEIAQAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgoKKwANAMkaAA==.Sharku:BAACNQAFFH8IAAIdAAQKgg7DSgCSAAAdAAQKgg7DSgCSAAA1AAQKfzsAAx0ACgoIHVRwAJ0CAB0ACgoIHVRwAJ0CAAsAAQrHF849AEkAAAAA.Shegothalf:BAAANQAECgUICwAAAA==.Shougo:BAAANQADCgQIBAAAAA==.',
Si='Siannean:BAAANQAECgEIAQAAAA==.Sickem:BAAANQAECgQIBAAAAA==.',
Sk='Skibblé:BAABNQAECn8UAAIZAAYKyAbPKAAzAQAZAAYKyAbPKAAzAQAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQIDAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgQIEwAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgkJMgAaAOkgAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAABNQAECn8jAAMMAAoKuQ9YIwCuAQAMAAoKmAxYIwCuAQANAAUK6hFZXQBBAQAAAA==.Starbux:BAABNQAECn8dAAIfAAkKqw0VQwClAQAfAAkKqw0VQwClAQAAAA==.Steakx:BAABNQAECn83AAIDAAoKpyC9GgAuAwADAAoKpyC9GgAuAwAAAA==.Stormwulf:BAABNQAECn8eAAMSAAgKJBzeLwDkAQASAAgKJBzeLwDkAQAHAAIKCwzdnABoAAAAAA==.',
Su='Sunmae:BAABNQAECn8WAAIHAAgKIQ4udADFAQAHAAgKIQ4udADFAQABNQAECggIIgAFAFATAA==.Suriel:BAAANQAECgQIEwAAAA==.Suumcuique:BAAANQADCggICAABNQAECgcIHwAPAP8hAA==.',
Sv='Svaha:BAAANQADCgYIEgAAAA==.Svenya:BAABNQAECn8aAAMPAAkKKhDoQwANAQAPAAcKeAroQwANAQAlAAMK+AUlowBVAAAAAA==.',
Sy='Sygne:BAAANQAECgUICQAAAA==.Sylphid:BAABNQAECn8XAAMEAAoKlQ1MwQCaAQAEAAkKiwxMwQCaAQAXAAUKbg4LJgDRAAABNQAFFAYICgAJAGwVAA==.',
Sz='Szell:BAABNQAECn8iAAIDAAcKzw1TggAuAQADAAcKzw1TggAuAQAAAA==.',
['Së']='Sëkhmët:BAAANQADCgYIBQABNQADCgMIAwACAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQACAAAAAA==.Taln:BAAANQADCgUICQAAAA==.Tassandie:BAABNQAECn8mAAMfAAkKkxtKLQAPAgAfAAkKkxtKLQAPAgAgAAEKAACVVgAAAAAAAA==.Tayebeh:BAAANQADCgYIFQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAFFAIIBgAKAAkjAA==.',
Th='Thebrownbear:BAAANQAECgIIAwAAAA==.Theebucket:BAAANQAECgcIBwAAAA==.Theo:BAAANQAECggIDAABNQAECgoKMwAfACIaAA==.Therese:BAAANQADCgUIBQAAAA==.Theresee:BAAANQADCggIEAAAAA==.',
Ti='Tionie:BAAANQAECggIDwAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECggIJAABAMciAA==.Tokyojoe:BAACNQAFFH8IAAIcAAQKzAvDBgDKAAAcAAQKzAvDBgDKAAA1AAQKfy8AAhwACgouFQARANkBABwACgouFQARANkBAAAA.Torrick:BAAANQAECgUIBQABNQAECgkJKQATAAcQAA==.Totemtot:BAABNQAECn8jAAIkAAcKywMSIgA7AQAkAAcKywMSIgA7AQAAAA==.Toupee:BAAANQADCgQIBAAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECgkJLAAGAIUlAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECgkJKQAXAB8ZAA==.',
Uf='Uffizzle:BAAANQAECggIEQAAAA==.',
Ul='Ulf:BAABNQAECn8zAAISAAoKCSEtGAATAwASAAoKCSEtGAATAwAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECn85AAIJAAoKlRmyIgCgAgAJAAoKlRmyIgCgAgAAAA==.Varlamor:BAABNQAECn8dAAMgAAcKBAk1OwBPAQAgAAcKBAk1OwBPAQAfAAEKvAPXAwEoAAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAFFAIIBgAKAAkjAA==.Vathraen:BAAANQAECgEIAgAAAA==.',
Ve='Velanistra:BAABNQAECn8ZAAIEAAgKSAlC4wBVAQAEAAgKSAlC4wBVAQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgMICAAAAA==.Vervane:BAABNQAECn8mAAIOAAgKwgoQSACJAQAOAAgKwgoQSACJAQAAAA==.',
Vg='Vgerr:BAABNQAECn8hAAIEAAgKjwfn6ABKAQAEAAgKjwfn6ABKAQAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAFFAUIDgAEABcbAA==.',
Vo='Vohu:BAABNQAECn8qAAMRAAkKrBT0OgB5AQARAAcKcxD0OgB5AQADAAYKLRZ4ewA9AQAAAA==.Voidpower:BAAANQAECggIEQAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBwAAAA==.Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQAECgEIAQAAAA==.Windeyaho:BAABNQAECn8YAAIGAAkKTiP3BQA0AwAGAAkKTiP3BQA0AwAAAA==.',
Xa='Xal:BAAANQAECgQICQABNQAECgoKMQAXALkdAA==.Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDgAAAA==.',
Xt='Xten:BAAANQAECgQIEwAAAA==.',
Yo='Yoshinox:BAABNQAECn9DAAIDAAoKbSEjDAB8AwADAAoKbSEjDAB8AwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgYIDwAAAA==.Zenagdrina:BAABNQAECn8bAAIDAAgKoAeCiwAbAQADAAgKoAeCiwAbAQAAAA==.Zenobiå:BAABNQAECn8sAAIHAAkK3QzOPQBdAQAHAAkK3QzOPQBdAQAAAA==.Zeypher:BAAANQADCgcIGgAAAA==.',
Zh='Zhaann:BAAANQAECgQIEwAAAA==.',
Zi='Zinarra:BAAANQADCgcIBwAAAA==.Ziron:BAAANQADCgIIAgABNQAECgIIBgACAAAAAA==.Zironlock:BAABNQAECn8UAAIIAAgKiBPjbAAXAgAIAAgKiBPjbAAXAgABNQAECgIIBgACAAAAAA==.',
Zo='Zorach:BAAANQAECgIIBQAAAA==.',
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
