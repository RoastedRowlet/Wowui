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

local lookup = {'Hunter-BeastMastery','Hunter-Survival','Mage-Frost','Paladin-Retribution','Unknown-Unknown','Priest-Shadow','Priest-Holy','Paladin-Holy','Monk-Windwalker','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Mage-Fire','Warrior-Arms','Evoker-Preservation','Druid-Restoration','Druid-Balance','Mage-Arcane','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Enhancement','Paladin-Protection','Warlock-Demonology','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Monk-Mistweaver','Rogue-Subtlety','DeathKnight-Frost','Warrior-Protection','DemonHunter-Vengeance','Druid-Feral','Evoker-Augmentation','Druid-Guardian','Warrior-Fury','Priest-Discipline','DemonHunter-Devourer','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aarix:BAABNQAECn8kAAMBAAgKlBuHVQBvAgABAAgKlBuHVQBvAgACAAIKRgayEABkAAAAAA==.',
Ac='Achmed:BAAANQAECgEIAQAAAA==.',
Ad='Addÿ:BAABNQAECn8cAAIDAAUKECDIDgC7AQADAAUKECDIDgC7AQAAAA==.',
Ae='Aelasong:BAACNQAFFH8IAAIEAAMKIBWMFwDnAAAEAAMKIBWMFwDnAAA1AAQKfyIAAgQACQqWIBk6AOYCAAQACQqWIBk6AOYCAAE1AAMKBQgFAAUAAAAA.Aelinessa:BAAANQAECgYICgAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgQICgAAAA==.Allyra:BAAANQAECgYIDAABNQAECgcIBwAFAAAAAA==.Allzerim:BAAANQADCgYIBQABNQAECgcIFgAGAPARAA==.Allzora:BAABNQAECn8WAAMGAAcK8BHLKADfAQAGAAcK8BHLKADfAQAHAAMKfx2lrAALAQAAAA==.Allzorath:BAAANQADCgYIBwABNQAECgcIFgAGAPARAA==.Aloki:BAAANQAECgYIBgAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAABNQAECn8mAAIBAAkKFSXaDgBqAwABAAkKFSXaDgBqAwAAAA==.Ametrius:BAAANQADCggJEAAAAA==.Ampd:BAAANQADCgYIEgAAAA==.',
An='Anastassia:BAABNQAECn8vAAIIAAkKNx2cGgAKAwAIAAkKNx2cGgAKAwAAAA==.André:BAABNQAECn8nAAIEAAkKPiDYKwAWAwAEAAkKPiDYKwAWAwAAAA==.Anuke:BAAANQAECgUIBwAAAA==.',
Ar='Arestoz:BAAANQAECgcIEQAAAA==.Ariakith:BAAANQADCgEIAQAAAA==.Arkhlight:BAAANQAECgcICwAAAA==.Arkhmonk:BAABNQAECn8mAAIJAAkKqhTBHgA3AgAJAAkKqhTBHgA3AgAAAA==.Arkillos:BAAANQAECgYICgAAAA==.Armonos:BAABNQAECn8dAAIKAAgKGhSjQQDzAQAKAAgKGhSjQQDzAQAAAA==.Arowynn:BAAANQADCgUIBQABNQAECgUIDAAFAAAAAA==.Arrowhoof:BAEANQAECgUIDAAAAA==.Arthurian:BAAANQADCgEIAQAAAA==.Artémis:BAAANQADCgEIAgAAAA==.',
As='Ashiri:BAAANQABCgUIBgAAAA==.Ashmage:BAAANQAECgQJBAAAAA==.Ashmorph:BAAANQAECgYIEAABNQAECgQJBAAFAAAAAA==.Asterisk:BAABNQAECn8lAAIBAAkKyBJeVgBtAgABAAkKyBJeVgBtAgAAAA==.Astromo:BAAANQADCgMJBQAAAA==.Asya:BAAANQAECggICQAAAA==.Asymmetric:BAAANQAECggIAwAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQAECgEIAQAAAA==.',
Ax='Axxiom:BAAANQABCgUIBQAAAA==.Axxium:BAACNQAFFH8GAAILAAIKFhvTHQCeAAALAAIKFhvTHQCeAAA1AAQKfzUAAwsACQp1Hs0lAMwCAAsACQp1Hs0lAMwCAAwABwpzCDumAEQBAAAA.',
Az='Azastra:BAABNQAECn8VAAINAAYK3gnWIQA8AQANAAYK3gnWIQA8AQAAAA==.Azorian:BAAANQAECgIIAwAAAA==.',
['Añ']='Aña:BAAANQAECgQIDAAAAA==.Añarchist:BAAANQADCgUJBwABNQAECgQIDAAFAAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAABNQAECn8dAAIOAAgKuAtbAwDDAQAOAAgKuAtbAwDDAQAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgAFAAAAAA==.Bagelpanda:BAAANQAECgEIAQAAAA==.Balgrim:BAABNQAECn8VAAIPAAcK6hK0rgCjAQAPAAcK6hK0rgCjAQAAAA==.Balki:BAAANQADCgcIBwABNQAECgkJIwAQAOATAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Barsch:BAAANQADCggICAAAAA==.Basalt:BAABNQAECn8WAAIBAAcKlhWqgwABAgABAAcKlhWqgwABAgAAAA==.Bastenwode:BAAANQAECgIIAgAAAA==.Bawce:BAAANQADCgcIDgAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgYIDgAAAA==.Becký:BAAANQAECgQIDAAAAA==.Beedriven:BAAANQAECgUICQABNQAECgcIHgAFAAAAAQ==.Beroan:BAAANQAECgYIDwAAAA==.Bertrille:BAAANQADCgYICQAAAA==.',
Bi='Bigcøøkie:BAAANQAECgEIAQAAAA==.Bigolcrities:BAAANQADCggJEgAAAA==.Bigshaft:BAAANQADCgYICgABNQADCggICgAFAAAAAA==.Bigwannabe:BAAANQAECgYIDwAAAA==.',
Bl='Blackmagma:BAAANQAECgUIBQABNQAECgcIHQAMAGAaAA==.Blackpinkk:BAABNQAECn8eAAIBAAkKtyL3DQBwAwABAAkKtyL3DQBwAwAAAA==.Blackppinkk:BAABNQAECn8YAAMRAAgKyByaEADOAgARAAgKyByaEADOAgASAAEKAACfyQAVAAAAAA==.Bloodbunny:BAAANQAECgIIAgAAAA==.Blëssed:BAAANQADCgMIBAAAAA==.',
Bo='Boggartt:BAAANQAECgIIAgAAAA==.Bootscoots:BAAANQAECgYICAAAAA==.Bornite:BAAANQADCgUICgAAAA==.Bowme:BAAANQAECgYIEAAAAA==.',
Br='Braedae:BAAANQAECgEIAgAAAA==.Brickaton:BAAANQAECgUICAAAAA==.Brocknor:BAABNQAECn8qAAIPAAgKGxqlZABdAgAPAAgKGxqlZABdAgAAAA==.Broodling:BAAANQABCgEIAQAAAA==.Brookie:BAAANQADCgMIAwAAAA==.',
Bu='Buckeyes:BAAANQAECggIDQAAAA==.Buddhaspalm:BAAANQAECgEIAQAAAA==.Butterdtoast:BAEBNQAECn8fAAIJAAcKVxlUIwAIAgAJAAcKVxlUIwAIAgAAAA==.',
Bw='Bwansamdi:BAAANQADCgYIDgAAAA==.',
Ca='Cabbresoa:BAAANQAECgUIEgAAAA==.Caboose:BAABNQAECn8aAAITAAgKlhtXYAC+AgATAAgKlhtXYAC+AgAAAA==.Cadbvucolta:BAAANQADCgUIBwAAAA==.Cadius:BAAANQAECgEIAQAAAA==.Caledor:BAAANQAECggIDgAAAA==.Calet:BAAANQADCggIFQAAAA==.Calindrel:BAABNQAECn8eAAIPAAgKVwYJwwBvAQAPAAgKVwYJwwBvAQAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQAECgUIDAAAAA==.Castiêl:BAAANQAECgEIAQAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCggIGAAAAA==.Celson:BAAANQAECgUICwAAAA==.Celticlore:BAAANQAECgEIAQAAAA==.Cerrvantes:BAAANQADCgcIEgAAAA==.',
Ch='Charlemange:BAAANQAECgMIAwAAAA==.Chernaboz:BAABNQAECn8eAAIUAAgKNhF9DgARAgAUAAgKNhF9DgARAgAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAABNQAECn8iAAIGAAgKpQfPNQBxAQAGAAgKpQfPNQBxAQAAAA==.Chioma:BAAANQADCgcIDAABNQAECgkJLgAVALMWAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAABNQAECn8oAAIJAAkKiRsnFgCbAgAJAAkKiRsnFgCbAgAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAABNQAECn8oAAITAAkKMCbcAQDwAwATAAkKMCbcAQDwAwAAAA==.Convrge:BAAANQADCgYIBwAAAA==.Corenthos:BAABNQAECn8vAAMWAAgKQRdoTADgAQAWAAgKixRoTADgAQAKAAcKjhKTXQB5AQAAAA==.Corlys:BAAANQAECgEIAQAAAA==.Corên:BAAANQAECgEIAQAAAA==.',
Cr='Cranker:BAAANQADCgUIBQAAAA==.Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAAANQAECgcIEgAAAA==.Creepndeath:BAAANQAECgUIBQAAAA==.Creselia:BAAANQAECgUIDgAAAA==.Critmaw:BAAANQAECgEIAQABNQAECgkJHgATAGMgAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQADCgYIBgAAAA==.Crumdumpster:BAAANQAECgYICgABNQADCgYIBgAFAAAAAA==.Crèmefraîche:BAABNQAECn8bAAIXAAgKlA9oFgD+AQAXAAgKlA9oFgD+AQAAAA==.',
Cu='Cuddlerz:BAAANQAECgQIDwAAAA==.',
Cy='Cypherrellik:BAAANQAECgQIBgABNQAECgYICwAFAAAAAA==.',
Da='Dagthunderer:BAAANQAECgQIBwAAAA==.Dakkenrahl:BAAANQADCgcIEAAAAA==.Dalatras:BAAANQAECgcIBwAAAA==.Dalistra:BAAANQAECgQIBAABNQAECgcIBwAFAAAAAA==.Dalweaver:BAAANQADCgUIBQABNQAECgcIBwAFAAAAAA==.Damogdem:BAAANQADCgYICAAAAA==.Dangly:BAACNQAFFH8IAAIEAAMKgxOEFwDnAAAEAAMKgxOEFwDnAAA1AAQKfx4AAwQACQqSGb5nAGACAAQACQqSGb5nAGACAAgABwqECAOmADMBAAAA.Dantes:BAAANQADCgcICgAAAA==.Dar:BAAANQADCggIIAAAAA==.Darkflame:BAABNQAECn8dAAIBAAgKixLwagA7AgABAAgKixLwagA7AgAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dashen:BAAANQAECgMIAwAAAA==.Dayve:BAABNQAECn8qAAISAAgK5hGtPgAAAgASAAgK5hGtPgAAAgAAAA==.',
Dc='Dcpt:BAAANQAECgEIAQAAAA==.',
De='Deadgeinside:BAAANQAECgQIBAAAAA==.Deadgenah:BAAANQADCgMIAwAAAA==.Deadgnome:BAABNQAECn8ZAAIKAAgKkRpWKgBwAgAKAAgKkRpWKgBwAgAAAA==.Deadlÿ:BAAANQAECgEIAgABNQAECgkJKAATADAmAA==.Deathgimbo:BAAANQAECggIDQAAAA==.Deathstomper:BAABNQAECn8WAAIPAAkKTRixYABoAgAPAAkKTRixYABoAgAAAA==.Demondono:BAABNQAECn8oAAIVAAgKgg89PQDKAQAVAAgKgg89PQDKAQAAAA==.Dethalas:BAAANQAECgIIAwAAAA==.Dethtoy:BAAANQADCgcIBwABNQAECgkJHgAYABoMAA==.Devomo:BAAANQAECgIIAgAAAA==.Deyedora:BAAANQAECgYICgAAAA==.Dezax:BAABNQAECn8YAAIZAAgKqRvBUgBaAgAZAAgKqRvBUgBaAgAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dilligafnope:BAAANQADCgcJBwAAAA==.Dinohunter:BAABNQAECn8ZAAIBAAgKsBy3QgChAgABAAgKsBy3QgChAgAAAA==.Disabler:BAAANQAECgEIAQABNQAECgkJKAATADAmAA==.',
Dj='Djdiddles:BAABNQAECn8fAAIXAAkK1RgdCQDjAgAXAAkK1RgdCQDjAgAAAA==.',
Do='Dorimane:BAAANQAECgcIHgAAAQ==.Dorlock:BAABNQAECn8WAAIaAAcK7QYkDgBuAQAaAAcK7QYkDgBuAQAAAA==.Dorotti:BAAANQAECgQICgABNQAECgcIFwATABUZAA==.Doubled:BAAANQADCgIIAgAAAA==.',
Dr='Dragondznuts:BAAANQAECgEIAQAAAA==.Drais:BAAANQADCgIIBQABNQADCgQIBgAFAAAAAA==.Drazgul:BAAANQADCgcIDAAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAABNQAECn84AAIPAAkKOyLtJwAYAwAPAAkKOyLtJwAYAwAAAA==.Dred:BAAANQAECgQIBAAAAA==.Dredkin:BAAANQADCgQIBAAAAA==.Dredwarrior:BAAANQADCgIIAgAAAA==.Drenleigh:BAAANQAECgIIAgAAAA==.Drosmoke:BAAANQAECgIIAwAAAA==.Drprodigy:BAAANQAECgUICQAAAA==.Drunkbaby:BAAANQAECgcIDAAAAA==.',
Dy='Dybuck:BAAANQAECgMIAwAAAA==.Dyrcyn:BAABNQAECn8ZAAMEAAgKAw7bwgCQAQAEAAgKdwnbwgCQAQAYAAIKMxQ7XwBaAAAAAA==.',
['Dà']='Dànger:BAABNQAECn8nAAQBAAkKTiPoFABIAwABAAkKTiPoFABIAwACAAQKgxcoCwBHAQAbAAQK3AS+ZACTAAAAAA==.',
Ed='Edroh:BAABNQAECn8aAAMTAAgKdggb9wCbAQATAAgKfwcb9wCbAQADAAEKDQnFRAA4AAAAAA==.',
Ei='Eidur:BAABNQAECn8dAAIcAAkKDxZtIgBuAgAcAAkKDxZtIgBuAgAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elará:BAAANQADCgYIBgAAAA==.Eleannora:BAAANQADCgEIAQAAAA==.Elemane:BAAANQAECgQIBQABNQAECgcIHgAFAAAAAQ==.Elemefayoh:BAABNQAECn8eAAMLAAcKXSTXKAC+AgALAAcKXSTXKAC+AgAMAAEKAACCHgFMAAAAAA==.Elementlo:BAABNQAECn8eAAIXAAkKyCJGBgAgAwAXAAkKyCJGBgAgAwABNQABCgIIAgAFAAAAAA==.Elsafromtemu:BAABNQAECn8bAAMDAAkK5QpWDwCxAQADAAkK5QpWDwCxAQAOAAMKfADvCwBCAAAAAA==.Elspeth:BAABNQAECn8qAAIYAAgKAiHzCQD7AgAYAAgKAiHzCQD7AgAAAA==.',
Em='Emagonarain:BAAANQAECgUIBQABNQAECgkJGAAGANUdAA==.Emagonasooth:BAABNQAECn8YAAIGAAkK1R2tEQDgAgAGAAkK1R2tEQDgAgAAAA==.Emerey:BAAANQADCggIEwAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQAECgMIAgAAAA==.Ennola:BAAANQADCgYIBwAAAA==.',
Ep='Ephriia:BAAANQAECgYIEgAAAA==.',
Er='Erikprince:BAAANQAECgUIDQAAAA==.Erso:BAAANQAECgIIAwAAAA==.',
Et='Eternalpaín:BAABNQAECn8wAAIEAAkKfh8BNAD6AgAEAAkKfh8BNAD6AgAAAA==.',
Ev='Evagria:BAAANQADCgYIBgAAAA==.Evanrude:BAAANQAECgEIAQAAAA==.',
Fa='Fal:BAAANQADCggIHwAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAABNQAECn8iAAISAAkKxgt+QgDpAQASAAkKxgt+QgDpAQAAAA==.',
Fe='Feliché:BAAANQAECggICwABNQAECgkJHgAHADkaAA==.Fevirin:BAAANQAECgcICwAAAA==.',
Fi='Fiddlesticks:BAAANQAECgYIDAAAAA==.Firefawkes:BAAANQAECgQJBAAAAA==.Fistbump:BAABNQAECn8aAAIdAAgKfh5EDgCaAgAdAAgKfh5EDgCaAgAAAA==.',
Fl='Fletchling:BAABNQAECn8eAAMBAAkKESIcJQABAwABAAgKGyIcJQABAwAbAAUKcyHiLQDaAQAAAA==.Flizrak:BAAANQADCggIEAABNQAFFAcIFQATAJ8VAA==.',
Fo='Footsteps:BAAANQADCgcJEQAAAA==.',
Fr='Freefallen:BAAANQAECgEIAQAAAA==.Frostclot:BAABNQAECn8kAAIKAAgKXyEWHgC/AgAKAAgKXyEWHgC/AgAAAA==.Frostsalad:BAAANQAECgQIBgAAAA==.Frozoned:BAAANQAECggICwABNQAFFAEIAQAFAAAAAA==.',
Fu='Fulta:BAABNQAECn8jAAIbAAgKnRcHIgA6AgAbAAgKnRcHIgA6AgAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Gadoon:BAAANQADCgMIAwAAAA==.Garadin:BAAANQAECgIIAgAAAA==.Garnok:BAAANQAECggIDAAAAA==.Garwa:BAABNQAECn8oAAMBAAkKhyIzHAAmAwABAAkKhyIzHAAmAwAbAAUKfRRaQQBFAQAAAA==.',
Ge='Geniver:BAAANQAECgIIAgAAAA==.Gerla:BAABNQAECn8cAAIEAAgKkQu6twCoAQAEAAgKkQu6twCoAQAAAA==.',
Gi='Gigas:BAABNQAECn8wAAQbAAgKShkjMADJAQAbAAcKpBQjMADJAQACAAUKNBOJCgBmAQABAAMKhxvb+wAHAQAAAA==.Gilgameshh:BAABNQAECn8oAAIEAAgKwhABmgDqAQAEAAgKwhABmgDqAQAAAA==.Girthbrooks:BAABNQAECn8qAAIeAAkKVRoJCQDkAgAeAAkKVRoJCQDkAgAAAA==.',
Gl='Glimmerfangs:BAAANQAECgYIDAAAAA==.',
Go='Gomory:BAAANQAECgIIAgAAAA==.Gondark:BAAANQAECgMIAwAAAA==.Gooseblade:BAAANQABCgIIAgAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCggIFgABNQAECgYIEgAFAAAAAA==.',
Gr='Grantham:BAAANQABCgQIBAAAAA==.Graverael:BAAANQADCgcICQAAAA==.Gretchen:BAABNQAECn8tAAIWAAkKESCAFQAMAwAWAAkKESCAFQAMAwABNQAFFAUICwAbABoMAA==.Greyley:BAAANQAECgQIBAABNQABCgIIAgAFAAAAAQ==.Greywolf:BAABNQAECn8kAAILAAcK4x0xTAAwAgALAAcK4x0xTAAwAgAAAA==.Gricham:BAAANQADCgUIBQAAAA==.Grimlight:BAAANQAECggIDgABNQAECgkJIQASAIAkAA==.Grymmhain:BAAANQADCggICAAAAA==.',
Gw='Gwawls:BAAANQADCgcIBwABNQAECgUIBQAFAAAAAA==.',
['Gä']='Gärry:BAAANQAECgMIBQAAAA==.',
Ha='Hanzoff:BAAANQADCgQIBAAAAA==.Harrow:BAAANQAECgYICgAAAA==.Havelock:BAAANQADCgUIBgAAAA==.Havulinnaan:BAAANQAECgYICQAAAA==.Haxx:BAABNQAECn8jAAMeAAgKexCwGQAJAgAeAAgKNA6wGQAJAgAcAAIKuQx4jAB0AAAAAA==.',
He='Healls:BAAANQADCgUIBQAAAA==.Hearge:BAABNQAECn8eAAMYAAkKGgwSKQCRAQAYAAkKGgwSKQCRAQAIAAIKyAJfEgFLAAAAAA==.Hellhawk:BAAANQAECgUIEwAAAA==.Hevydevy:BAABNQAECn8aAAIHAAkKZhfINwCGAgAHAAkKZhfINwCGAgAAAA==.Hexhain:BAABNQAECn8XAAIUAAgKEQk6FgC6AQAUAAgKEQk6FgC6AQAAAA==.',
Hi='Hiddenhorde:BAAANQAECgEIAQAAAA==.',
Ho='Hockay:BAAANQAECgYIEwAAAA==.Holygun:BAAANQAECgcIDQAAAA==.Holyliight:BAAANQADCgUIBQAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQIDAAAAA==.Holysmokess:BAAANQAECgQIBAAAAA==.Holystan:BAAANQAECgcIDgAAAA==.Hondoe:BAAANQAECgUIBwAAAA==.Hookjaw:BAAANQADCgEIAQAAAA==.Hopi:BAAANQABCgQIBAAAAA==.',
Ht='Htownglaivez:BAAANQADCgYIBgABNQAECgUICAAFAAAAAA==.Htownhots:BAAANQAECgUICAAAAA==.Htownprot:BAAANQADCgMIAwABNQAECgUICAAFAAAAAA==.Htownshaman:BAAANQADCgcIDgABNQAECgUICAAFAAAAAA==.',
Hu='Humblepotato:BAAANQAECgcIBwAAAA==.Hungsten:BAAANQAECgUIBQABNQAFFAMICAAEAIMTAA==.Huntfromhell:BAABNQAECn8jAAIVAAgK/hraJQBqAgAVAAgK/hraJQBqAgAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.Icedpissfox:BAAANQADCgUJBwAAAA==.',
Id='Idonttank:BAAANQADCggIEgAAAA==.',
Il='Illio:BAAANQAECgQIDgAAAA==.',
Im='Imarea:BAABNQAECn8fAAITAAcKngRWJwFGAQATAAcKngRWJwFGAQAAAA==.Impirious:BAABNQAECn8oAAIKAAgKUBVzTADBAQAKAAgKUBVzTADBAQAAAA==.Implumz:BAAANQADCgMIAwABNQAECggIKAAKAFAVAA==.Imptard:BAAANQADCgIIAgABNQAECggIKAAKAFAVAA==.Imyx:BAABNQAECn8VAAIfAAYKHxCuVgBKAQAfAAYKHxCuVgBKAQAAAA==.',
In='Incubussy:BAAANQADCgcIBwAAAA==.Infamuspikel:BAABNQAECn8gAAIWAAkKchx8IQDAAgAWAAkKchx8IQDAAgAAAA==.Infel:BAAANQAECgYIDgAAAA==.Inkkish:BAAANQAECgYIEwAAAA==.Innovates:BAABNQAECn8wAAIYAAkKsRqRDQC/AgAYAAkKsRqRDQC/AgAAAA==.Interstellar:BAAANQAECgQIBAAAAA==.Intervene:BAAANQADCgYJFAABNQAECgkJMAAEAH4fAA==.Invictus:BAABNQAECn8sAAITAAgKwBJkrgAkAgATAAgKwBJkrgAkAgAAAA==.',
Is='Isaßeau:BAAANQADCgEIAQAAAA==.Ist:BAAANQAECgUIDAAAAA==.',
Iz='Izuael:BAAANQAECgYJBgAAAA==.',
Ja='Jackjr:BAAANQAECgcICwAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jahdar:BAAANQABCgQIBAAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQJBAABNQAFFAYIDQAPAJsbAA==.Jandoar:BAABNQAECn8VAAITAAYKCQM1TwEHAQATAAYKCQM1TwEHAQAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jasminsparks:BAAANQABCgQIAgAAAA==.Jaylea:BAABNQAECn8oAAIUAAkKXAzVEADzAQAUAAkKXAzVEADzAQAAAA==.Jaynee:BAAANQABCgUIBgAAAA==.',
Je='Jegallidin:BAAANQADCgMIBAAAAA==.Jetpilot:BAAANQAECgUIDQAAAA==.Jeypi:BAAANQAECgUIEwAAAA==.',
Ji='Jiq:BAABNQAECn8WAAIJAAcKdAhNOgA9AQAJAAcKdAhNOgA9AQAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.Jorlath:BAAANQAECgMIAwAAAA==.',
Ju='Judikai:BAABNQAECn8VAAIJAAYKdxK8NABqAQAJAAYKdxK8NABqAQAAAA==.Junesong:BAAANQAECgQIEQAAAA==.Justwipeit:BAAANQADCggJCAAAAA==.',
Ka='Kabilos:BAAANQADCggJEAAAAA==.Kaedian:BAAANQAECggIEgAAAA==.Kalesmora:BAABNQAECn8oAAIPAAgKsRTtggAQAgAPAAgKsRTtggAQAgAAAA==.Kamikaze:BAAANQAECgYIDAAAAA==.Karlov:BAAANQAECgcICwAAAA==.Karthis:BAAANQADCggIDAAAAA==.Kazera:BAAANQADCgMIBAAAAA==.Kazgrim:BAAANQADCgYICgAAAA==.',
Ke='Keanah:BAABNQAECn8gAAIWAAYK3w2qdQA+AQAWAAYK3w2qdQA+AQAAAA==.Kelrosh:BAAANQABCgIJAgAAAA==.Keynn:BAAANQADCgUIBQABNQAECggIEgAFAAAAAA==.',
Kh='Kheil:BAAANQAECgUIBQAAAA==.Kheims:BAAANQAECgQICAAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAAANQAECgcIEAAAAA==.',
Ki='Killduran:BAAANQAECgUICgAAAA==.Kimaga:BAAANQADCgUICQABNQAECgYIEgAFAAAAAA==.Kindle:BAAANQAECgUICQAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAABNQAECn8ZAAMaAAgKDhTpBwAVAgAaAAgK9hLpBwAVAgAZAAYK/w3NtQBeAQAAAA==.Kiwia:BAABNQAECn8kAAISAAgK9CNxEQA6AwASAAgK9CNxEQA6AwAAAA==.',
Kl='Klunt:BAAANQADCgEIAQABNQAECgkJJAANABgVAA==.',
Ko='Kochiyo:BAAANQABCgcIDAAAAA==.Kogä:BAAANQAECggIBAAAAA==.Kolaniber:BAAANQABCgEIAQAAAA==.Korkrum:BAAANQAECgYICwAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAABNQAECgQICAAFAAAAAA==.Krel:BAAANQADCggICAABNQAECgkJIwAQAOATAA==.Krellyroll:BAAANQAECgEIAQABNQAECgkJIwAQAOATAA==.Krelthyr:BAABNQAECn8jAAIQAAkK4BOxFQBYAgAQAAkK4BOxFQBYAgAAAA==.Krumm:BAABNQAECn8vAAIgAAgKuA9QGQCZAQAgAAgKuA9QGQCZAQAAAA==.Kruul:BAAANQABCgQJBAAAAA==.',
Ku='Kuhne:BAAANQAECgMIAwAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgUICQAAAA==.Kyther:BAAANQAECgQIBwAAAA==.',
['Kñ']='Kñightboat:BAABNQAECn8VAAIhAAYKQBUwEwB1AQAhAAYKQBUwEwB1AQAAAA==.',
La='Ladeiene:BAAANQAECgYIEQAAAA==.Laelwyn:BAAANQAECgIIAgAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQABNQAECgcIFgAKAMwSAA==.Laeritidesdk:BAABNQAECn8WAAIKAAcKzBKwXQB4AQAKAAcKzBKwXQB4AQAAAA==.Laraondra:BAAANQAECgMIAwAAAA==.Larix:BAAANQADCgYIBgABNQAECgkJHgAHADkaAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCggJEQAAAA==.Laxxium:BAAANQAECgYIBgAAAA==.',
Le='Leafwarden:BAAANQABCgYICAAAAA==.Leon:BAAANQAECgcIEAAAAA==.Leonard:BAAANQAECgcICQAAAA==.Leothedog:BAABNQAECn8eAAMIAAgK5hG3ZADnAQAIAAgK5hG3ZADnAQAEAAIKlwFNhAFMAAAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQADCgUJBQABNQAECgQICAAFAAAAAA==.',
Li='Lichgibber:BAAANQAECgEIAQAAAA==.Lightrising:BAAANQAECgMIAwAAAA==.Lilbean:BAAANQAECgQIBAAAAA==.Lilenalol:BAAANQADCgcIEwAAAA==.Lilfiorella:BAAANQADCgYIDAAAAA==.Lilmonstrman:BAABNQAECn8nAAITAAkK+BZmcwCXAgATAAkK+BZmcwCXAgAAAA==.Liltree:BAABNQAECn8cAAIBAAgKFRHabwAvAgABAAgKFRHabwAvAgAAAA==.Limbbiscuit:BAABNQAECn8gAAMBAAgKVRrvWQBkAgABAAgKVRrvWQBkAgAbAAQKdgUUXwCmAAAAAA==.Listmonk:BAAANQAECgIIAwAAAA==.',
Ll='Llothae:BAABNQAECn8WAAITAAcKoxVM1gDXAQATAAcKoxVM1gDXAQAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgcIHgAAAA==.Loyalty:BAAANQAFFAEIAQAAAA==.',
Lu='Lucifix:BAAANQADCgQIBAAAAA==.Lucinsia:BAAANQAECgcIBwAAAA==.Lul:BAACNQAFFH8KAAIPAAQKmR8MFQB7AQAPAAQKmR8MFQB7AQA1AAQKfycAAg8ACQpmItwlAB8DAA8ACQpmItwlAB8DAAAA.Luminar:BAAANQAECgEIAgAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQAECgIIAwAAAA==.',
['Lð']='Lðvergirl:BAAANQAECgYIEAAAAA==.',
Ma='Madcow:BAAANQAECgUICwAAAA==.Maelk:BAAANQADCgQIBQABNQAECgYICwAFAAAAAA==.Magistella:BAAANQAECgIIAgAAAA==.Maisrii:BAEBNQAECn8ZAAILAAcKgROjcAC2AQALAAcKgROjcAC2AQAAAA==.Maivz:BAABNQAECn8XAAMIAAcKrg1EngBGAQAIAAcKrg1EngBGAQAEAAEKjwRGugEoAAAAAA==.Malignantt:BAABNQAECn8pAAIKAAgKEhG2TwCzAQAKAAgKEhG2TwCzAQAAAA==.Maloch:BAAANQADCgIIAgAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQAECgQICAAAAA==.Maurphious:BAAANQAECgEIAQAAAA==.',
Me='Mekaniker:BAAANQABCgMIAwAAAA==.Melbee:BAABNQAECn8aAAIiAAgK5hM8EAAEAgAiAAgK5hM8EAAEAgAAAA==.Melodrama:BAAANQAECgcIDgAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Micassa:BAAANQADCgIIAgAAAA==.Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgQIDwABNQAECgcIFwATABUZAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAABNQAECn8kAAIWAAgKVREtUADQAQAWAAgKVREtUADQAQAAAA==.Mirjelys:BAAANQAECgQIBgAAAA==.',
Mo='Moarass:BAABNQAECn8hAAIRAAkKZxOKIAAiAgARAAkKZxOKIAAiAgAAAA==.Monty:BAAANQAECgIIAwAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.Mordos:BAAANQADCgMIAwAAAA==.Moridane:BAAANQAECgUICQABNQAECgcIHgAFAAAAAQ==.',
Mu='Much:BAAANQAECgMIAwAAAA==.Muffinz:BAAANQAECgQJBwABNQAECggIGQAKAJEaAA==.Mugo:BAAANQAECgQIBAABNQAECgkJHgAHADkaAA==.Multiabuse:BAAANQAECgMIBAAAAA==.',
My='Myau:BAAANQAECgcIEwAAAA==.Mylou:BAAANQAECgUIDgAAAA==.Mynia:BAABNQAECn8vAAICAAgKNAZHCQClAQACAAgKNAZHCQClAQAAAA==.',
Na='Nano:BAABNQAECn8kAAMZAAgKdhx8PQCXAgAZAAgKdhx8PQCXAgAUAAIKxA3tXABrAAAAAA==.Nayroon:BAEANQADCggIEAABNQAECggIIQABADwhAA==.Nazdreg:BAABNQAECn8YAAMUAAYKeBEHNgDoAAAZAAYKqg7uwwA+AQAUAAQKjg4HNgDoAAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAABNQAECn8qAAIfAAgKEBOfNwDzAQAfAAgKEBOfNwDzAQAAAA==.Nerfdisc:BAAANQAECgUIBwAAAA==.Nevershocked:BAABNQAECn8cAAIjAAcK/hcMCgDTAQAjAAcK/hcMCgDTAQAAAA==.Nezziee:BAAANQAECgIIAgAAAA==.',
Ni='Niitefall:BAAANQAECgcIBwABNQADCgUIBQAFAAAAAA==.Ninjaznpariz:BAAANQADCgQJBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Noobles:BAAANQAECgQIBQAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQAECgUIBQABNQAECgcIGwAbAOIQAA==.Nosredna:BAAANQAECgMIBAAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Notintheface:BAAANQAECgIIAgAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgAFAAAAAA==.',
Nu='Nuzz:BAACNQAFFH8RAAIPAAYKKiSzBgBRAgAPAAYKKiSzBgBRAgA1AAQKfyAAAg8ACQrAJesZAE8DAA8ACQrAJesZAE8DAAAA.',
Ny='Nydav:BAABNQAECn8VAAIJAAYK1h/eIQAXAgAJAAYK1h/eIQAXAgABNQAECggIEgAFAAAAAA==.Nyphithys:BAAANQAECgIIAgAAAA==.',
['Ní']='Níítefall:BAAANQAECggICAABNQADCgUIBQAFAAAAAA==.',
Ob='Obalma:BAABNQAECn8cAAMiAAkKeRwuCQC0AgAiAAkKBRouCQC0AgAkAAUK9BphKwA3AQAAAA==.',
Od='Odwalla:BAABNQAECn8cAAIBAAkKECIBGQA0AwABAAkKECIBGQA0AwAAAA==.',
Ol='Olmec:BAAANQAECgUIDwAAAA==.Olmek:BAAANQAECgIIAgAAAA==.',
On='Onlydesert:BAABNQAECn8XAAMTAAcKFRmqvQAHAgATAAcKFRmqvQAHAgAOAAEKKhFaDAA+AAAAAA==.Onranui:BAAANQADCgcIDQAAAA==.',
Oo='Oopsyourdead:BAAANQAECgUICgAAAA==.',
Op='Optiks:BAABNQAECn8eAAMTAAcKdBxHtQAXAgATAAcKtBpHtQAXAgADAAIKlhpTLQCPAAAAAA==.',
Or='Orcfan:BAAANQABCgIJAgAAAA==.Orksauce:BAABNQAECn82AAMeAAkKSCAeDQChAgAeAAcKiiEeDQChAgAcAAMKJx6LbQDyAAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAABNQAECn8aAAIEAAgKpQpivwCXAQAEAAgKpQpivwCXAQAAAA==.Osong:BAAANQADCgcIBwABNQAECggICQAFAAAAAA==.',
Ou='Outtamanna:BAAANQADCgUICQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECggILwAWAEEXAA==.',
Ox='Oxl:BAAANQADCgQIBAAAAA==.',
['Oß']='Oß:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.',
Pa='Pagophobia:BAAANQAECgMIAwAAAA==.Pallytree:BAAANQAECgIIAgAAAA==.Papiblanco:BAAANQADCggICgAAAA==.Pariahdruid:BAAANQAECggIEQAAAA==.',
Pe='Percepcions:BAAANQAECgYIDQAAAA==.Percksmash:BAAANQAECggIEQAAAA==.Perkbane:BAAANQAECggIBwABNQAECggIEQAFAAAAAA==.Perkyl:BAAANQAECgUICgAAAA==.',
Ph='Phage:BAAANQAECgQIBgABNQAECgkJJAANABgVAA==.Philon:BAAANQADCgEIAQAAAA==.Photophobia:BAABNQAECn8aAAIGAAkKch5UFQCzAgAGAAkKch5UFQCzAgAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQADCggIEAAAAA==.Pivy:BAAANQADCgYIBgABNQAECggIGgAdAH4eAA==.',
Pk='Pkrage:BAABNQAECn8vAAMgAAkKtxwBBwDuAgAgAAkKtxwBBwDuAgAPAAMK+Qz9EQGyAAAAAA==.',
Pl='Plaugez:BAAANQABCgIIAwAAAA==.Plazlie:BAABNQAECn8mAAMlAAkK8iOSAQCCAwAlAAkKEyOSAQCCAwAPAAEKciLXNQFhAAAAAA==.Plopp:BAEANQAECgcIBwAAAA==.Ploppstein:BAEANQAECgYIEQABNQAECgcIBwAFAAAAAA==.',
Po='Polyethylene:BAABNQAECn8bAAILAAgKRwbvlwBHAQALAAgKRwbvlwBHAQAAAA==.Poucastranca:BAABNQAECn8pAAMUAAgKtySdPQDKAAAUAAMKuSSdPQDKAAAZAAcKRiQMJAFwAAAAAA==.',
Pu='Punkpikachu:BAAANQAECgEIAQAAAA==.',
Pw='Pwnman:BAAANQADCgUIBQAAAA==.',
Qk='Qkoira:BAAANQAECgQICgAAAA==.',
Qu='Quanlain:BAAANQAECgYIEAAAAA==.Quillathe:BAABNQAECn8rAAMHAAgKhhVaVQAfAgAHAAgKhhVaVQAfAgAmAAYKHAkxEQASAQAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rabblle:BAAANQADCggIDgAAAA==.Rancore:BAAANQAECgYIEQAAAA==.Rashdar:BAABNQAECn8mAAIEAAkKYhwAVwCOAgAEAAkKYhwAVwCOAgAAAA==.Rasto:BAAANQADCgYICQABNQAECgQJBwAFAAAAAA==.Rattpacck:BAAANQAECgEIAQAAAA==.Rattpack:BAAANQAECgQICwAAAA==.Raves:BAAANQAECgUIDgAAAA==.Rayvynn:BAAANQADCgIIBAAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQAECgMIAwAAAA==.',
Ri='Ribeyye:BAAANQAECgcICgAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQADCgYIGAAAAA==.Rinjiabri:BAAANQAECgIIAgAAAA==.Rinjipally:BAAANQAECgYICwAAAA==.',
Ro='Robroy:BAABNQAECn8VAAMZAAYKKRcxqQB7AQAZAAYKkxIxqQB7AQAUAAEK/hNBbwBAAAAAAA==.Robrøy:BAAANQADCggJGQAAAA==.Rokmage:BAAANQAECgMIBAAAAA==.Roseclaw:BAEANQAECgQICQABNQAECggIIQABADwhAA==.Roseclawed:BAEBNQAECn8hAAIBAAgKPCErKwDrAgABAAgKPCErKwDrAgAAAA==.Roxso:BAACNQAFFH8VAAMTAAcKnxX2EgDaAQATAAYKJxX2EgDaAQADAAEKfReLDABZAAA1AAQKfzgAAxMACQp9I6ElAEkDABMACQp9I6ElAEkDAAMABgohDTEfAO0AAAAA.',
Ru='Rukaiz:BAABNQAECn8cAAIPAAcKtBaGmwDTAQAPAAcKtBaGmwDTAQAAAA==.',
Ry='Rylen:BAAANQADCgYIBgAAAA==.Rylun:BAAANQAECgEIAQAAAA==.',
['Rë']='Rëdmagma:BAABNQAECn8dAAIMAAcKYBoOXwABAgAMAAcKYBoOXwABAgAAAA==.',
['Rò']='Ròbroy:BAAANQAECggJCQAAAA==.',
['Ró']='Rónan:BAAANQAECgQIBQAAAA==.',
['Rû']='Rûsh:BAAANQADCggJEAAAAA==.',
['Rü']='Rüin:BAAANQAECgEIAQAAAA==.',
Sa='Sacrelicious:BAAANQAECgYIEQAAAA==.Saennah:BAAANQADCgIJAgAAAA==.Sagewynn:BAAANQAECgUIDAAAAA==.Sainei:BAAANQADCgUIBQABNQAECggIHAAPAP8bAA==.Salfroc:BAABNQAECn8uAAIaAAgKXRfRBgA5AgAaAAgKXRfRBgA5AgAAAA==.Samhain:BAABNQAECn8kAAInAAgKpRL3KwDeAQAnAAgKpRL3KwDeAQAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQAFAAAAAA==.Saplo:BAAANQAECgYIDwAAAA==.Sapphirosa:BAAANQAECgEIAQABNQAECgkJKAAJAIkbAA==.Sarif:BAAANQAECgQICAAAAA==.Saxel:BAAANQAECgEIAQAAAA==.',
Sc='Scallop:BAAANQADCgQIBAAAAA==.Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCggJEAAAAA==.Serenati:BAAANQAECgUIDgAAAA==.Seïya:BAAANQADCggIKAAAAA==.',
Sg='Sgthulka:BAAANQADCgQJBAAAAA==.',
Sh='Shadesmar:BAAANQAECgcIAgAAAA==.Shamawockee:BAABNQAECn8ZAAIXAAcKrQ+eGQDFAQAXAAcKrQ+eGQDFAQABNQAECgkJNAABAHggAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAABNQAECn8cAAIVAAcKrwmrTQBhAQAVAAcKrwmrTQBhAQAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQAECgIIAwAAAA==.Shautistic:BAAANQAECgQIBAAAAA==.Shocktuah:BAABNQAECn8vAAIMAAgKdiTOEwBRAwAMAAgKdiTOEwBRAwAAAA==.Shonúff:BAABNQAECn8jAAIJAAgK4hVfIgASAgAJAAgK4hVfIgASAgAAAA==.Shotaru:BAAANQAECgUIDAAAAA==.Shotpace:BAAANQAECgQICAAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQAECgEIAQABNQAECgUICQAFAAAAAA==.Shädöw:BAAANQADCgUIBwAAAA==.',
Si='Silmeria:BAABNQAECn8VAAIdAAgKxhseEAB5AgAdAAgKxhseEAB5AgAAAA==.Sinful:BAABNQAECn8zAAMlAAkK1A8oCwAPAgAlAAkK1A8oCwAPAgAPAAIKIQiGQAFIAAAAAA==.',
Sk='Skalagrim:BAAANQADCggIDwAAAA==.Skeptix:BAAANQAECgQIAgAAAA==.Skeptyk:BAABNQAECn8oAAIHAAgKISHVIADpAgAHAAgKISHVIADpAgAAAA==.Sko:BAEBNQAECn8mAAMIAAkKFxoDKwC5AgAIAAkKFxoDKwC5AgAEAAcK9Avn7wA2AQABNQADCgcJCQAFAAAAAA==.Skol:BAAANQAECgcIEgAAAA==.Skolivermist:BAEANQAECgEIAQABNQADCgcJCQAFAAAAAA==.Skolivia:BAEANQADCgcJCQAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smitti:BAAANQAECgQIBAABNQAECgcIFwATABUZAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAABNQAECn8gAAMnAAgKYyRuCQBAAwAnAAgKUiRuCQBAAwAVAAYK+SIkKABaAgAAAA==.',
Sn='Snapee:BAAANQAECgUICQAAAA==.Sniffledoo:BAABNQAECn8fAAIgAAcKxhDdGgCGAQAgAAcKxhDdGgCGAQAAAA==.Snol:BAAANQAECgQIBAAAAA==.Snuwuf:BAAANQADCgcIEAAAAA==.',
So='Sockz:BAAANQAECgUICgAAAA==.Soonmia:BAAANQADCggIDAAAAA==.Sourfangs:BAABNQAECn8eAAMPAAkKKCD5OADeAgAPAAkKKCD5OADeAgAlAAEKAABtKQBhAAAAAA==.Soxx:BAAANQADCgYICwABNQAECggIIwAeAHsQAA==.',
Sp='Spicypeño:BAABNQAECn8iAAINAAkKwCD4BQAsAwANAAkKwCD4BQAsAwABNQAFFAgIIAANAH8dAA==.Spicý:BAABNQAECn8dAAITAAkKEyKoNAAhAwATAAkKEyKoNAAhAwAAAA==.Splack:BAABNQAECn80AAIBAAkKeCBsFwA7AwABAAkKeCBsFwA7AwAAAA==.Splithoofe:BAEANQADCgUICwABNQAECgUIDAAFAAAAAA==.Sprawl:BAABNQAECn8iAAIoAAgKgxDMCQDmAQAoAAgKgxDMCQDmAQAAAA==.Sprawlher:BAAANQAECgYIEQABNQAECggIIgAoAIMQAA==.',
Sq='Squrrlydan:BAEANQAECgQJBAAAAA==.',
St='Stabzuplenty:BAAANQAECgIIAgABNQAFFAcIFQATAJ8VAA==.Staint:BAABNQAECn8kAAINAAkKGBUPDACiAgANAAkKGRUPDACiAgAAAA==.Staints:BAAANQAECgMIAwABNQAECgkJJAANABgVAA==.Starnights:BAAANQAECgUICgAAAA==.Statman:BAABNQAECn8WAAIgAAcK8gYnJAAhAQAgAAcK8gYnJAAhAQAAAA==.Steelbubble:BAABNQAECn8ZAAMPAAkKxRzDXQBwAgAPAAkKFBzDXQBwAgAlAAMKAiGoGwDqAAAAAA==.Stella:BAAANQAECgUICgAAAA==.Stengah:BAABNQAECn8rAAIQAAgK7h+ZDQDMAgAQAAgK7h+ZDQDMAgAAAA==.Stonebrew:BAAANQABCgEIAQAAAA==.Strela:BAAANQAFFAEIAgAAAQ==.',
Su='Supershenron:BAAANQADCgEIAQAAAA==.Suraki:BAABNQAECn8uAAIVAAkKsxbrIACQAgAVAAkKsxbrIACQAgAAAA==.',
Sv='Svetlian:BAAANQAECgUIBQABNQAFFAEIAgAFAAAAAA==.',
Sw='Swtblsphmy:BAAANQAECgYIDwAAAA==.',
Sy='Sylverwolf:BAAANQADCgEIAQAAAA==.Sylvestrus:BAAANQAECgYICwABNQAECgkJHgAHADkaAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAABNQAECn80AAIHAAkKWxwKHQD7AgAHAAkKWxwKHQD7AgAAAA==.Sèitheach:BAAANQAECgIIAgAAAA==.',
['Sí']='Síd:BAABNQAECn8kAAMaAAkKVBDPBQBaAgAaAAkKhA/PBQBaAgAZAAkKNwochwDQAQAAAA==.',
Ta='Tahrin:BAABNQAECn8iAAIBAAgKriFbJgD9AgABAAgKriFbJgD9AgAAAA==.Talamon:BAABNQAECn8qAAIpAAgKMxVEDgAPAgApAAgKMxVEDgAPAgAAAA==.Tamerlynn:BAAANQADCgUIBAAAAA==.Tandruid:BAABNQAECn8jAAISAAgKByBZIwCyAgASAAgKByBZIwCyAgAAAA==.Tanize:BAAANQADCggICAAAAA==.Taproot:BAAANQAECgYIAQAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAABNQAECn8bAAMBAAcKiw/IoQC+AQABAAcKiw/IoQC+AQAbAAUKuALbXQCqAAAAAA==.Tasina:BAAANQADCgUIBgAAAA==.Taurenamos:BAABNQAECn88AAMSAAgKHhUpNABDAgASAAgKHhUpNABDAgARAAcKBRgYJAAAAgAAAA==.Taynam:BAAANQAECgQICAABNQAECgUIEQAFAAAAAA==.',
Te='Tempëst:BAAANQAECgIJAgAAAA==.Tenchu:BAAANQAECgYIEwAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgUICgAAAA==.Terrørßlade:BAAANQAECgEIAQABNQAECgUICgAFAAAAAA==.',
Th='Thalorain:BAAANQAECgUIBQABNQAECgYICwAFAAAAAA==.Thark:BAAANQAECggIDQABNQAECgkJLwAXAKolAA==.Thatdruid:BAAANQAECgEIAQAAAA==.Thicknfluffy:BAAANQABCgEIAgAAAA==.Throwd:BAABNQAECn8nAAIeAAgKcA9dGQAMAgAeAAgKcA9dGQAMAgAAAA==.Thundah:BAAANQAECgEIAQAAAA==.Thurk:BAABNQAECn8vAAMXAAkKqiV1AADiAwAXAAkK+iR1AADiAwAMAAgKVSWKEgBaAwAAAA==.',
Ti='Tideshunter:BAACNQAFFH8GAAMBAAMK0AvMJQCcAAABAAIKIg7MJQCcAAAbAAIKJAR5HwBxAAA1AAQKfx8AAwEACQrLHCIuAOECAAEACQrHHCIuAOECABsACApGE+8vAMoBAAAA.Tinytony:BAABNQAECn8kAAMYAAkK9xkBDwCrAgAYAAkK9xkBDwCrAgAEAAIKdQrGbAFrAAAAAA==.Tinyweakling:BAAANQAECgIIAgABNQAECgkJHgABABEiAA==.',
To='Tookahxd:BAAANQAECgIIBAAAAA==.Toranis:BAAANQAECgEIAQAAAA==.Torrellan:BAAANQAECgEIAQAAAA==.Torrents:BAABNQAECn8oAAMLAAgKkyVPEQA6AwALAAgKkyVPEQA6AwAMAAUKvA2DxAAFAQAAAA==.Totemdroppa:BAAANQAECgQIBAABNQAECggIGQAKAJEaAA==.Totemik:BAAANQAECgEIAQAAAA==.Touchofchaos:BAAANQADCggICAAAAA==.',
Tr='Trailerpark:BAAANQAECggICAAAAA==.Triepas:BAAANQAECgUICQAAAA==.Trillest:BAAANQAECgYICwAAAA==.Trinytee:BAABNQAECn8YAAIBAAcKQxfvjQDqAQABAAcKQxfvjQDqAQAAAA==.Trippytotem:BAABNQAECn8nAAMMAAkKMxLbeQCxAQAMAAcKPRHbeQCxAQALAAcK2AU5pgAiAQAAAA==.Trolltoll:BAAANQADCgEIAQAAAA==.Trollypolly:BAAANQABCgMIAQAAAA==.',
Ty='Tyriäel:BAABNQAECn8hAAMKAAkKAiMOGwDUAgAKAAkKCB4OGwDUAgAWAAcK9iKuIgC5AgAAAA==.Tyrrible:BAAANQAECggIAQAAAA==.',
['Tà']='Tàyla:BAAANQADCgQIBAABNQAECgcIGAABAEMXAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulmec:BAAANQAECgMIAwAAAA==.Ulther:BAAANQADCggJEAAAAA==.',
Va='Vacare:BAAANQADCggJEAAAAA==.Valdyria:BAAANQADCgUIFwAAAA==.Valistar:BAAANQAECgQIBwAAAA==.Valkoienne:BAAANQADCgUICgAAAA==.Varnashar:BAAANQAECgUIBAAAAA==.Vavictus:BAAANQADCggJEAAAAA==.Vazaenei:BAAANQABCgMIAwAAAA==.',
Ve='Vedronorael:BAAANQADCgcJBgAAAA==.Veinos:BAAANQAECggIEQAAAQ==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIBAAAAA==.Vengrath:BAABNQAECn8eAAMTAAgKuB7rZQCyAgATAAgKuB7rZQCyAgADAAEK2hciPwBFAAAAAA==.Verderben:BAAANQAECgUIDAAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQAECgEIAQAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAABNQAECn8tAAIEAAcKeRUgrQDAAQAEAAcKeRUgrQDAAQAAAA==.',
Vu='Vulperra:BAABNQAECn8jAAIPAAkKbROSeAAqAgAPAAkKbROSeAAqAgAAAA==.',
Vy='Vynessa:BAAANQADCgMJAwAAAA==.',
Wa='Walk:BAAANQADCgYIBgAAAA==.Waq:BAABNQAECn8iAAQaAAgKKhb5BgAzAgAaAAgK0xX5BgAzAgAZAAYKvgsjvwBJAQAUAAQKUBaJLAAbAQAAAA==.Waterwhip:BAAANQAECgcIEwAAAA==.',
We='Wemeo:BAAANQAECgUICgAAAA==.Westfall:BAABNQAECn8kAAMKAAgKTyBKQwDsAQAKAAgKTyBKQwDsAQAWAAIKKALY1QA+AAAAAA==.',
Wi='Willowweewoo:BAAANQAECggIEQAAAA==.Willrun:BAAANQAECgUIDQAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.Witheredyam:BAAANQAECgEIAQAAAA==.',
Wo='Wolfbayne:BAAANQAECgUIBwAAAA==.Wompeal:BAABNQAECn8cAAMHAAcKAR2/SwA+AgAHAAcKAR2/SwA+AgAmAAEKIBJKJwA3AAAAAA==.Wonkwonk:BAABNQAECn8fAAMDAAcKagnIFABcAQADAAcKagnIFABcAQAOAAEKfwH0DwATAAAAAA==.Worth:BAABNQAECn8vAAIEAAkK3CKgDgCRAwAEAAkK3CKgDgCRAwAAAA==.',
Wr='Wrukolas:BAABNQAECn8aAAIZAAcKmwpqrwBsAQAZAAcKmwpqrwBsAQAAAA==.',
Wy='Wystan:BAABNQAECn8lAAILAAgKnx8+KgC4AgALAAgKnx8+KgC4AgAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAABNQAECn8nAAMpAAgK/RhfCwBTAgApAAgK/RhfCwBTAgAdAAMK5AvXPQCBAAAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xandritten:BAAANQABCgIIAgAAAA==.Xanthe:BAABNQAECn8cAAMIAAgKpxMhWAAOAgAIAAgKpxMhWAAOAgAEAAEKkQHhzAEcAAAAAA==.Xavin:BAAANQADCgcICQAAAA==.',
Xe='Xentow:BAABNQAECn8pAAIBAAgKvQf1ngDEAQABAAgKvQf1ngDEAQAAAA==.',
Ya='Yamling:BAAANQADCggIHgAAAA==.Yayaka:BAAANQADCgcIEgAAAA==.',
Yi='Yizdano:BAACNQAFFH8HAAMeAAMK7BImDQDHAAAeAAMKRw0mDQDHAAAcAAIKMwgXGACJAAA1AAQKfy4AAxwACQq4GhwlAF0CABwACAq4GhwlAF0CAB4ACQqBC/0bAPIBAAAA.',
Yu='Yukiina:BAAANQADCgcIEwAAAA==.Yungbean:BAAANQAECgQIBwAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQAECgQICQABNQAECgkJHgAHADkaAA==.Zambora:BAAANQADCgcICgAAAA==.Zamwi:BAAANQAECgQIDQAAAA==.Zavrix:BAAANQAECggIAQAAAA==.',
Ze='Zeebra:BAAANQAECgYIDgAAAA==.Zeesaw:BAABNQAECn8eAAMPAAgKjxhGdAA1AgAPAAgKjxhGdAA1AgAlAAIKRxixJACHAAAAAA==.Zenden:BAAANQAECgIIAgAAAA==.Zerebrand:BAAANQAECgIIAgABNQAECgkJJwATAJ4fAA==.Zeretrix:BAABNQAECn8nAAMTAAkKnh+RMwAjAwATAAkKnh+RMwAjAwADAAQK0AtdJgC8AAAAAA==.Zerospace:BAABNQAECn8dAAIEAAgKiwviwwCOAQAEAAgKiwviwwCOAQAAAA==.',
Zi='Ziros:BAAANQAECggICAAAAA==.',
Zl='Zlutar:BAAANQAECgQIBgAAAA==.',
Zy='Zynos:BAABNQAECn8iAAIVAAgKlxIpNwDyAQAVAAgKlxIpNwDyAQAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.Zyraethiel:BAAANQAFFAEIAQAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQADCgYIBgAAAA==.',
['Úà']='Úà:BAAANQADCgIIAQABNQAECgQICgAFAAAAAA==.',
['Üb']='Überhealz:BAABNQAECn8eAAMHAAkKORoAQwBcAgAHAAkKORoAQwBcAgAGAAMKXAmvWgCXAAAAAA==.',
['ßö']='ßöw:BAABNQAECn8vAAIBAAgKqSFpJwD4AgABAAgKqSFpJwD4AgAAAA==.',
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
