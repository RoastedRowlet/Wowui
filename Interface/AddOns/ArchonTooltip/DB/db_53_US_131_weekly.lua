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

local lookup = {'Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Druid-Feral','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Warlock-Demonology','DeathKnight-Blood','Evoker-Preservation','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Warrior-Arms','Hunter-Marksmanship','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','Warrior-Fury','Monk-Brewmaster','Warrior-Protection','Shaman-Enhancement','Druid-Balance',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Advîl:BAABNQAECn8nAAIBAAoKgRqvBACbAgABAAoKgRqvBACbAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgcIGAABNQAECgQIDwACAAAAAA==.',
Al='Alexandre:BAABNQAECn8cAAIDAAgK7hFqlgDbAQADAAgK7hFqlgDbAQAAAA==.Allasia:BAAANQADCgcIBgAAAA==.Alterboy:BAAANQADCgIIAgABNQAECgYIHQABAH0jAA==.Alton:BAABNQAECn8xAAIBAAoKSg9hWAAQAgABAAoKSg9hWAAQAgAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAABNQAECn8VAAMBAAgKyx7VLQCvAgABAAgKyx7VLQCvAgAEAAQK8w/PHwHqAAABNQAECgQIBQACAAAAAA==.Ansuz:BAAANQAECgIIAgAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAABNQAECn8bAAMFAAYK3BHjFwB7AQAFAAYK3BHjFwB7AQAGAAYKRwtGMwAHAQABNQAECggIFgAHACEOAA==.Aristia:BAAANQADCggIDgABNQAECgoKIwAHAMsSAA==.Arweni:BAAANQAECgEIAQAAAA==.',
At='Atheizt:BAABNQAECn8eAAIBAAkKcRtgJwDLAgABAAkKcRtgJwDLAgABNQAECgoKGQAIAJkbAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Bakachan:BAAANQAECgIIAgAAAA==.Baldilocks:BAAANQADCgQIBAAAAA==.Banedon:BAAANQADCgMJBQABNQAECgYIHQABAH0jAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIDgACAAAAAA==.Beastmaster:BAAANQAECgMIAwAAAA==.Beetingu:BAAANQADCgYIEQABNQAECgcIHgAJANsjAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAABNQAECn8kAAIGAAgKpiVKBwASAwAGAAgKpiVKBwASAwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.',
Bl='Blacken:BAABNQAECn8UAAIKAAcKxhg3EwBIAQAKAAcKxhg3EwBIAQAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgQIBgABNQAECgoKOQALALEhAA==.Blakylightz:BAAANQAFFAIIAgAAAA==.Blazen:BAABNQAECn8pAAIHAAoK/x9/IAAJAwAHAAoK/x9/IAAJAwAAAA==.Blinker:BAABNQAECn8XAAIMAAcKgwyLCAAFAQAMAAcKgwyLCAAFAQAAAA==.Bloodynuts:BAABNQAECn8cAAMNAAkKqhOAFwAiAgANAAgKURSAFwAiAgAOAAIKzhImjwB1AAAAAA==.Bloyfbloyf:BAACNQAFFH8GAAIPAAMKzgQrBwCwAAAPAAMKzgQrBwCwAAA1AAQKfx4AAg8ACgpPEPwIALUBAA8ACgpPEPwIALUBAAAA.Blueshadøw:BAAANQAECgEIAQAAAA==.',
Bo='Bobbidyboo:BAACNQAFFH8PAAIIAAUK8waAAwBEAQAIAAUK8waAAwBEAQA1AAQKfzkAAggACgqTEe4kAPwBAAgACgqTEe4kAPwBAAAA.Bonesclone:BAAANQAECgIIAgAAAA==.',
Br='Brewshido:BAAANQAECgIIAwAAAA==.Briareosx:BAABNQAECn8sAAIQAAoKEht2EgDFAQAQAAoKEht2EgDFAQAAAA==.Brixtia:BAAANQADCgcIBgABNQAECggIJAARAKAVAA==.Brovar:BAACNQAFFH8RAAIEAAUKzx1HBQAIAQAEAAUKzx1HBQAIAQA1AAQKfzkAAgQACgpkIDIWAGwDAAQACgpkIDIWAGwDAAAA.',
Bu='Bubbaa:BAABNQAECn8hAAMSAAkKrR/+IQDgAgASAAkKrR/+IQDgAgAHAAEKAAAMJAFJAAAAAA==.Buddydaelf:BAABNQAECn8eAAIDAAkKbxXKXwBXAgADAAkKbxXKXwBXAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgkJJgALAPEPAA==.',
Ce='Ceanaflowers:BAABNQAECn8VAAIQAAoKnA/nPAArAQAQAAoKnA/nPAArAQAAAA==.',
Ch='Chia:BAABNQAECn8iAAMTAAgKKhY5CQBEAQATAAgKKhY5CQBEAQAUAAIKnQaEYQBZAAABNQADCgMIAwACAAAAAA==.Chianamoya:BAAANQADCgYICwABNQAECgQIDwACAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQAECgEIAQABNQAECgoKLwAKAPYXAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQAECgMIBQAAAA==.Coolarrow:BAABNQAECn8eAAIDAAkKgRX7EgDZAQADAAkKgRX7EgDZAQABNQAFFAQIDAADAIIaAA==.Cosby:BAAANQABCgIIAgAAAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAAANQAECgYICAAAAA==.Crosshair:BAAANQAECgUIEAAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAcIFQAJAMIQAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgoKKgAVALkdAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECgYICgAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davandar:BAAANQADCgYIDAAAAA==.Daveah:BAABNQAECn8cAAISAAYKzwrkPQDyAAASAAYKzwrkPQDyAAAAAA==.',
De='Deathberry:BAABNQAECn8qAAIJAAgK6Az3MQAzAQAJAAgK6Az3MQAzAQAAAA==.Delphron:BAAANQAECgEIAwAAAA==.Demoncharge:BAAANQAECgEIAgAAAA==.Demonflayer:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Denaeaa:BAABNQAECn8YAAMTAAcKYBeXGQDmAQATAAcKYBeXGQDmAQAUAAIKlgDCOgAoAAABNQAFFAMIBwASAMQEAA==.Depala:BAAANQADCgcIEAABNQAECgIIAgACAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECn8hAAIHAAgKJhQLZwDrAQAHAAgKJhQLZwDrAQAAAA==.',
Di='Dist:BAAANQAECgMIBgAAAA==.Divinestorm:BAABNQAECn8dAAMBAAYKfSO0BgBfAgABAAYKfSO0BgBfAgAEAAUKfAwwCAERAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgoKOAAQAGMmAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQAECgEIAQAAAA==.Dookerslol:BAAANQADCgUIAwAAAA==.Dotexe:BAABNQAECn8fAAIOAAcKlhtBCwBzAQAOAAcKlhtBCwBzAQAAAA==.Dotsy:BAACNQAFFH8TAAQJAAUKVRtkDACyAAAJAAQKMx9kDACyAAAWAAEKAAAmCQBdAAAXAAEKlxOOGgBQAAA1AAQKfzkABAkACgq5IIkbAIIBABcABgoXH1gTANcBAAkACQrPIIkbAIIBABYABQrQGbgOAGUBAAAA.',
Dr='Drackarys:BAAANQADCgcIGwAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAABNQAECn85AAMLAAoKsSFOAwCDAwALAAoKsSFOAwCDAwAYAAcKwCB+DwBiAgAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECn8mAAMLAAkK8Q8tIgC6AQALAAkK8Q8tIgC6AQAYAAcKcw2QIQBCAQAAAA==.Dravas:BAAANQAECgEIAgAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQAECgQIDQAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgcIGAASAOoZAA==.',
Dw='Dwdog:BAABNQAECn8XAAIWAAYKqAx+AwAyAQAWAAYKqAx+AwAyAQAAAA==.',
['Dà']='Dàthguy:BAABNQAECn81AAIZAAkKoSVpAwC+AwAZAAkKoSVpAwC+AwAAAA==.',
['Dé']='Défault:BAABNQAECn8qAAMZAAkKYSAwEwAfAwAZAAkKYSAwEwAfAwAaAAQKOA0hcwDTAAAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elek:BAAANQAECgYICwABNQAECgoKLQAJAI0iAA==.Elennie:BAAANQAECgIIAgAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAABNQAECn8ZAAIZAAcKmxneFAA4AQAZAAcKmxneFAA4AQAAAA==.',
En='Enyo:BAABNQAECn8hAAIbAAgK4RUnJgAUAgAbAAgK4RUnJgAUAgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Fa='Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggIDgABNQAECggIDgACAAAAAA==.Felsmoke:BAAANQADCgYIBgAAAA==.Fervid:BAABNQAECn8XAAIcAAgKuQ8GPgBBAQAcAAgKuQ8GPgBBAQAAAA==.Feylen:BAABNQAECn8qAAIcAAoKtSUkCgCvAwAcAAoKtSUkCgCvAwAAAA==.',
Fi='Fido:BAABNQAECn8bAAIKAAYKahMRKQDQAAAKAAYKahMRKQDQAAAAAA==.Fidø:BAAANQADCgUICwABNQAECgYIGwAKAGoTAA==.Fifthelement:BAABNQAECn8kAAISAAgKXSBVEADVAQASAAgKXSBVEADVAQAAAA==.Figgson:BAAANQADCgQIBAAAAA==.Figgy:BAABNQAECn8dAAISAAcKOBY2LQAtAQASAAcKOBY2LQAtAQAAAA==.Fiorstrasza:BAABNQAECn8gAAMLAAgK9BMyBwBXAQALAAgK9BMyBwBXAQAYAAIKbwZNNgBcAAAAAA==.Firry:BAAANQADCgYIEgAAAA==.Fistsofsmoke:BAAANQADCgIIAwAAAA==.',
Fj='Fjalgeirr:BAABNQAECn8kAAMPAAgKVQ3pJgDUAAAPAAgKVQ3pJgDUAAAdAAEKAADSPQAFAAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAABNQAECn8eAAIeAAcKbBcTJQBsAQAeAAcKbBcTJQBsAQAAAA==.',
Fr='Froot:BAAANQAECgUIDgAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECn8zAAIEAAoKGx8vEwDiAQAEAAoKGx8vEwDiAQAAAA==.',
Ga='Gaëll:BAAANQADCggIEQAAAA==.',
Ge='Gearsprocket:BAAANQAECgYIDwABNQAECgoKMQABAEoPAA==.Geosmin:BAABNQAECn8bAAISAAkKsBAuYwDkAQASAAkKsBAuYwDkAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECgoKMQABAEoPAA==.',
Gh='Ghue:BAAANQAECgUICgAAAA==.Ghòst:BAAANQAECgIIAgAAAA==.',
Gi='Gilalade:BAABNQAECn8ZAAIDAAcKlxY9UAARAQADAAcKlxY9UAARAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQADCgUIBQAAAA==.',
Go='Gobann:BAAANQADCgYIBgABNQAECggIJAARAKAVAA==.Gonern:BAABNQAECn8qAAMVAAoKuR3QCgDuAgAVAAoK9xzQCgDuAgAEAAYKAhsEpwDSAQAAAA==.Gooby:BAABNQAFFH8SAAIeAAUKdxYIBwBrAQAeAAUKdxYIBwBrAQAAAA==.Goond:BAAANQAECgcIDQABNQAECgoKLQAJAI0iAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQABCggIGAAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIDgACAAAAAA==.Grlfriend:BAAANQAECgQIBgAAAA==.Grodin:BAAANQADCgYIDwAAAA==.Grofiest:BAABNQAECn8gAAIfAAgKjA8kLgC0AQAfAAgKjA8kLgC0AQAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECgoKOAAQAGMmAA==.Guggychan:BAABNQAECn84AAMQAAoKYybpAgDkAwAQAAoKRCbpAgDkAwAgAAMKTSauCQDnAAAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECn80AAIKAAoKUw0FDgB1AQAKAAoKUw0FDgB1AQAAAA==.',
Ha='Hadrian:BAAANQADCgYIDwAAAA==.Haldor:BAAANQADCgcIBwAAAA==.Hanohakua:BAAANQADCgcIDgAAAA==.Haohmaru:BAABNQAECn8eAAIhAAcKfh89CgByAgAhAAcKfh89CgByAgAAAA==.Harthen:BAAANQADCgYIEQABNQAECggIFgAHACEOAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAABNQAECn8WAAQgAAcKHhQEGQARAQAQAAYK2xBL4AApAQAgAAQKOhsEGQARAQAiAAEK8gyJRwAmAAAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAABNQAECn8dAAIEAAkKfwjU1QBwAQAEAAkKfwjU1QBwAQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECggICgAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIEgAAAA==.Huneyhunter:BAABNQAECn8ZAAIFAAYKHAeYIgD8AAAFAAYKHAeYIgD8AAAAAA==.',
Ic='Ichigozero:BAAANQADCgQIBgAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgUICQAAAA==.',
Ir='Ironaxe:BAABNQAECn8jAAIDAAgKfAxhYgDmAAADAAgKfAxhYgDmAAAAAA==.',
It='Itsademon:BAAANQAECgUICAAAAA==.',
Ja='Jaeksoolie:BAABNQAECn8XAAMjAAgKxg/iFgD7AQAjAAgKxg/iFgD7AQAHAAEKAACxOgExAAAAAA==.Jakyro:BAABNQAECn8eAAMLAAcKNQjJLABAAQALAAcKNQjJLABAAQAYAAYKUAw0CwCyAAAAAA==.Javeech:BAABNQAECn8eAAIEAAcKlhqtlwD0AQAEAAcKlhqtlwD0AQAAAA==.Jaypark:BAABNQAECn8dAAIUAAkK7BX0HgA5AgAUAAkK7BX0HgA5AgAAAA==.Jayse:BAABNQAECn8YAAMgAAoKfgm7CAAAAQAgAAoKWwm7CAAAAQAQAAQK8gR2HQGhAAABNQAECgoKIwAHAHMhAA==.',
Jc='Jchaotic:BAAANQAECgEIAQAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAFFAUICQAKAGARAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUICgAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAABNQAECn8dAAMNAAoKiRXDBAD6AQANAAoKPxXDBAD6AQAOAAEK6RC9SABCAAAAAA==.',
Ju='Juanda:BAAANQAFFAEIAQAAAA==.Junghee:BAABNQAECn8yAAMTAAoKMSNaAgBHAgATAAoKMSNaAgBHAgAUAAcK9hQeLQCwAQAAAA==.Juudaz:BAACNQAFFH8JAAIKAAUKYBGdEgAtAQAKAAUKYBGdEgAtAQA1AAQKfz8ABAoACgoDInQYAOoCAAoACgpmIHQYAOoCABkABgqYIuo3AEYCABoABwqwFeNCALkBAAAA.',
['Jï']='Jïnx:BAABNQAECn8jAAIHAAgKBCJqIQAEAwAHAAgKBCJqIQAEAwAAAA==.',
Ka='Kaalhvel:BAAANQAECgUIDgAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAABNQAECn8eAAMBAAcK9RzdSABDAgABAAcK9RzdSABDAgAEAAQKGgtingChAAAAAA==.Kapkywa:BAABNQAECn8ZAAIIAAoKmRt+AQAPAwAIAAoKmRt+AQAPAwAAAA==.Kasherquon:BAAANQAECgQICQABNQAECgUIBwACAAAAAA==.Katsumyo:BAAANQADCggIGQAAAA==.Kawaiimonsta:BAAANQADCggICAAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAABNQAECn8VAAIHAAUKHAU0YAB3AAAHAAUKHAU0YAB3AAAAAA==.Kiyara:BAABNQAECn8qAAIDAAoK2A28CwAVAgADAAoK2A28CwAVAgAAAA==.Kizaki:BAABNQAECn8VAAIbAAYKyx2eKQD2AQAbAAYKyx2eKQD2AQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAECgoKOQALALEhAA==.',
Kr='Krelliz:BAABNQAECn8lAAMSAAgK7xKwbADFAQASAAgK7xKwbADFAQAHAAYK/QZRLwABAQAAAA==.Kristiné:BAAANQAECgEIAQAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgUIDQAAAA==.',
Ku='Kungfuwho:BAABNQAECn8lAAQTAAoKTgu2IQB5AQATAAoKTgu2IQB5AQAUAAUK/QdbTwC4AAAhAAEKAADbNgAdAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgYIFQAbAMsdAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgEIAgAAAA==.',
Le='Leksa:BAAANQABCgEIAQAAAA==.Lenaea:BAACNQAFFH8HAAISAAMKxAT7CwC9AAASAAMKxAT7CwC9AAA1AAQKfzYAAxIACgoBFjZBAFwCABIACgoBFjZBAFwCAAcAAgrLCUcVAWMAAAAA.',
Li='Liiege:BAAANQAECgYIDQABNQAECgoKOQALALEhAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAABNQAECn8lAAMVAAoKbRn0AgAEAgAVAAoKbRn0AgAEAgAEAAEKAABpIgEAAAABNQAECgoKLwAKAPYXAA==.',
Lo='Lobø:BAABNQAECn8gAAIDAAcKvhI6jADyAQADAAcKvhI6jADyAQAAAA==.Lowtierscrub:BAAANQAECgUIBwABNQAECgoKFQAQAJwPAA==.',
Lu='Luccyy:BAAANQADCgQICwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAABNQAECn8hAAIZAAkKPA2/VwCxAQAZAAkKPA2/VwCxAQAAAA==.Luth:BAAANQADCggICAABNQAECgUIDQACAAAAAA==.Luthex:BAAANQAECgUIDQAAAA==.',
Ly='Lylacy:BAABNQAECn8xAAIJAAkKRhCLFAClAQAJAAkKRhCLFAClAQAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAABNQAECn8eAAIcAAcKXAVqjgCqAAAcAAcKXAVqjgCqAAAAAA==.Magiicae:BAAANQADCgIIAgABNQAECgoKOQALALEhAA==.Magoliko:BAAANQAECgEIAgAAAA==.Manatee:BAAANQADCggIEgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECn8oAAIIAAgKJRt2BAArAgAIAAgKJRt2BAArAgAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAABNQAECn8nAAMgAAgKPw8JDwC8AQAgAAgKOQ8JDwC8AQAiAAYKIwrXEAC0AAAAAA==.',
Mi='Minjae:BAAANQAECgUIEAABNQAECgoKLwAJAEwUAA==.Misfirë:BAAANQAECgQIDQABNQAECgkJKgAZAGEgAA==.',
Mo='Mogwaí:BAAANQAECgUIEQAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morrìgan:BAAANQAECgIIAgAAAA==.Morvane:BAAANQADCgYICQABNQAECgoKMQABAEoPAA==.Movack:BAABNQAECn8XAAIEAAcKwwph3wBcAQAEAAcKwwph3wBcAQAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAABNQAECn8aAAMIAAcKoiDACwB9AQAIAAQKzSDACwB9AQAkAAcKRQrQXgBVAQAAAA==.',
My='Mytho:BAAANQAECgEIAQAAAA==.Mythunran:BAABNQAECn8dAAIRAAgKuAdpDAAsAQARAAgKuAdpDAAsAQAAAA==.',
['Mö']='Mörï:BAABNQAECn8aAAIEAAgK+wtqzwB8AQAEAAgK+wtqzwB8AQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgUICAAAAA==.Natalina:BAAANQADCgcJCgABNQAECgIIAgACAAAAAA==.Nax:BAAANQAECgYICQAAAA==.Naz:BAAANQADCgYIEAAAAA==.',
Ne='Nerfhammer:BAACNQAFFH8LAAIEAAUKJRpXDACEAQAEAAUKJRpXDACEAQA1AAQKfzsAAgQACgqnIfEWAGkDAAQACgqnIfEWAGkDAAAA.Nessalove:BAACNQAFFH8TAAIeAAUKVhX2BQCEAQAeAAUKVhX2BQCEAQA1AAQKfzkAAh4ACgp+HDo4AIcCAB4ACgp+HDo4AIcCAAAA.Neutrino:BAAANQAECgUIDQAAAA==.',
Ni='Nicolbowlass:BAAANQAECgcIDgAAAA==.Nightomen:BAAANQADCggICAABNQAECgcIGgAIAKIgAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICAABNQAECgUIDgACAAAAAA==.',
No='Noone:BAABNQAECn8yAAMSAAoKHRLiCAA0AgASAAoKHRLiCAA0AgAHAAYKwQmltAApAQAAAA==.Noriel:BAAANQAECgYIDgAAAA==.',
Nz='Nz:BAAANQAECgUICgAAAA==.',
Od='Oddeccentric:BAAANQAECgYICQABNQAFFAUIDgAYANcRAA==.',
Op='Opali:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgkJNQAZAKElAA==.Overshoot:BAABNQAECn8bAAIDAAgKchEjWwD3AAADAAgKchEjWwD3AAAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgMIAwABNQAECggIHwAeALQaAA==.Papimonk:BAAANQAECgMIAwABNQAECggIHgASAOcZAA==.Parvarti:BAABNQAECn8gAAMXAAYKvwSQRwCpAAAXAAUKxgGQRwCpAAAJAAYKcgQsjABuAAAAAA==.Pathogenic:BAABNQAECn8WAAIfAAYKWRMEOABlAQAfAAYKWRMEOABlAQAAAA==.',
Pe='Peluquin:BAAANQADCgIIAgAAAA==.Persimmoñ:BAAANQADCggJEgAAAA==.',
Ph='Philliesteak:BAAANQADCgEIAQAAAA==.',
Po='Polkadott:BAABNQAECn8eAAMJAAcK2yPLcQALAgAJAAUKBSXLcQALAgAXAAIKHCK9PgDHAAAAAA==.',
Pr='Presidìum:BAABNQAECn8dAAIVAAgKihGaCABxAQAVAAgKihGaCABxAQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAABNQAECn8eAAIMAAgKAB+CBgCYAgAMAAgKAB+CBgCYAgAAAA==.Provoked:BAAANQAECgIIAgABNQAECgkJGwASADQXAA==.',
Ps='Psylocke:BAABNQAECn8pAAIOAAgKZQw4EABDAQAOAAgKZQw4EABDAQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAANAKoTAA==.',
Ra='Rahuwu:BAAANQAECgMIAwABNQAECgoKOAAQAGMmAA==.Raveger:BAAANQADCgYIDwABNQAECgYIHQABAH0jAA==.',
Re='Reladin:BAABNQAECn8eAAIVAAcKnQsJNABDAQAVAAcKnQsJNABDAQAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIIAAAAA==.Renzr:BAABNQAECn8xAAMZAAkK6SBOHADiAgAZAAkKoh1OHADiAgAKAAcKPSNoHgC/AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgUICAABNQAFFAcIIQAYALsaAA==.',
Ro='Roag:BAABNQAECn8VAAIcAAYKUwr5lQCcAAAcAAYKUwr5lQCcAAAAAA==.Roley:BAABNQAECn8eAAIIAAkKrw2nLwCeAQAIAAkKrw2nLwCeAQAAAA==.Rowin:BAAANQAECggIEwAAAA==.',
Ru='Rustedroots:BAAANQADCgUIBQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgQJBQABNQAECgQIDwACAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgcIHgARAGcKAA==.Saristrix:BAABNQAECn8eAAIRAAcKZwpPFwDMAAARAAcKZwpPFwDMAAAAAA==.Sarnara:BAABNQAECn8jAAIVAAgKCRxIFQBXAgAVAAgKCRxIFQBXAgAAAA==.Satyria:BAAANQAECgQJBgAAAA==.Savagedeath:BAAANQAECgIIAwAAAA==.',
Se='Secord:BAABNQAECn8fAAIDAAYK2AI1lACFAAADAAYK2AI1lACFAAAAAA==.Senarx:BAAANQABCgQIAwAAAA==.Seonghwa:BAAANQADCgYIEAAAAA==.Sereniity:BAAANQADCgYIBgABNQAECgoKOQALALEhAA==.Seriiez:BAAANQAECgEIAQAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgUIBwAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shampooh:BAAANQADCgYICwAAAA==.Shanthe:BAAANQADCgUIBQABNQAECggIJwAOACodAA==.Sharku:BAACNQAFFH8HAAIcAAMKgg6MJABUAAAcAAMKgg6MJABUAAA1AAQKfzYAAxwACgr4HEgYAK8BABwACgr4HEgYAK8BAAwAAQrHF849AEkAAAAA.Shegothalf:BAAANQAECgQIBAAAAA==.',
Si='Sickem:BAAANQAECgQIBAAAAA==.',
Sk='Skibblé:BAABNQAECn8UAAIXAAYKyAbPKAAzAQAXAAYKyAbPKAAzAQAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQICAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgQIDwAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgkJMQAZAOkgAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAABNQAECn8fAAMNAAoKJQ9YIwCuAQANAAoKBAxYIwCuAQAOAAUK6hFZXQBBAQAAAA==.Starbux:BAABNQAECn8cAAIeAAkKLQyDFwC1AQAeAAkKLQyDFwC1AQAAAA==.Steakx:BAABNQAECn8vAAIDAAoKnR+HBgBgAgADAAoKnR+HBgBgAgAAAA==.Stormwulf:BAABNQAECn8YAAMSAAcK6hnsagDLAQASAAcK6hnsagDLAQAHAAIKCwzkYAB2AAAAAA==.',
Su='Sunmae:BAABNQAECn8WAAIHAAgKIQ4udADFAQAHAAgKIQ4udADFAQAAAA==.Suriel:BAAANQAECgQIDwAAAA==.Suumcuique:BAAANQADCggICAABNQAECgcIGgAIAKIgAA==.',
Sv='Svaha:BAAANQADCgYIEgAAAA==.Svenya:BAABNQAECn8ZAAMIAAgKBhLoQwANAQAIAAYKAQzoQwANAQAkAAMK+AUlowBVAAAAAA==.',
Sy='Sygne:BAAANQAECgQIBAAAAA==.Sylphid:BAAANQAECggIEQABNQAFFAUICQAKAGARAA==.',
Sz='Szell:BAABNQAECn8cAAIDAAYKvw7/agDVAAADAAYKvw7/agDVAAAAAA==.',
['Së']='Sëkhmët:BAAANQADCgYIBQABNQADCgMIAwACAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQACAAAAAA==.Taln:BAAANQADCgUICQAAAA==.Tassandie:BAABNQAECn8fAAIeAAgKtBqmHgCLAQAeAAgKtBqmHgCLAQAAAA==.Tayebeh:BAAANQADCgYIFQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECgoKOQALALEhAA==.',
Th='Theebucket:BAAANQAECgcIBwAAAA==.Theo:BAAANQAECggIBQABNQAECgoKMQAfAGkWAA==.Therese:BAAANQADCgUIBQAAAA==.Theresee:BAAANQADCggIEAAAAA==.',
Ti='Tionie:BAAANQAECggICQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgYIHQABAH0jAA==.Tokyojoe:BAABNQAECn8lAAIbAAoK/BP9HgBYAgAbAAoK/BP9HgBYAgAAAA==.Torrick:BAAANQADCgcIDQABNQAECgkJJgALAPEPAA==.Totemtot:BAABNQAECn8eAAIjAAcKyQMSIgA7AQAjAAcKyQMSIgA7AQAAAA==.Toupee:BAAANQADCgUIBAAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECggIJAAGAKYlAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECggIIwAVAAkcAA==.',
Uf='Uffizzle:BAAANQAECggIDgAAAA==.',
Ul='Ulf:BAABNQAECn8tAAISAAoKlx8tGAATAwASAAoKlx8tGAATAwAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECn8vAAIKAAoK9heyIgCgAgAKAAoK9heyIgCgAgAAAA==.Varlamor:BAABNQAECn8dAAMfAAcKBAk1OwBPAQAfAAcKBAk1OwBPAQAeAAEKvAPXAwEoAAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECgoKOQALALEhAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAABNQAECn8UAAIEAAgKYAhC4wBVAQAEAAgKYAhC4wBVAQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgMIBAAAAA==.Vervane:BAABNQAECn8gAAIPAAcKbAwQSACJAQAPAAcKbAwQSACJAQAAAA==.',
Vg='Vgerr:BAABNQAECn8dAAIEAAgKHAbn6ABKAQAEAAgKHAbn6ABKAQAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAFFAUICwAEACUaAA==.',
Vo='Vohu:BAABNQAECn8kAAMRAAgKoBX0OgB5AQARAAYKGRP0OgB5AQADAAIKrhpDuABNAAAAAA==.Voidpower:BAAANQAECgQICAAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBAAAAA==.Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Windeyaho:BAABNQAECn8VAAIGAAgKwyL3BQA0AwAGAAgKwyL3BQA0AwAAAA==.',
Xa='Xal:BAAANQAECgQIBwABNQAECgoKKgAVALkdAA==.Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAAANQAECgQIDwAAAA==.',
Yo='Yoshinox:BAABNQAECn85AAIDAAoKJCEjDAB8AwADAAoKJCEjDAB8AwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgUICwAAAA==.Zenagdrina:BAABNQAECn8aAAIDAAcKtAfiVwD/AAADAAcKtAfiVwD/AAAAAA==.Zenobiå:BAABNQAECn8jAAIHAAgKYw36HwA7AQAHAAgKYw36HwA7AQAAAA==.Zeypher:BAAANQADCgYIEwAAAA==.',
Zh='Zhaann:BAAANQAECgQIDwAAAA==.',
Zi='Ziron:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Zironlock:BAABNQAECn8UAAIJAAgKiBPjbAAXAgAJAAgKiBPjbAAXAgABNQAECgEIAQACAAAAAA==.',
Zo='Zorach:BAAANQAECgIIAgAAAA==.',
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
