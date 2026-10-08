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

local lookup = {'Priest-Holy','Priest-Discipline','Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','Warlock-Destruction','Shaman-Elemental','Monk-Mistweaver','Warrior-Protection','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Blood','Druid-Balance','Druid-Feral','Monk-Windwalker','Paladin-Retribution','Warlock-Demonology','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','Warlock-Affliction','DeathKnight-Frost','Mage-Frost','Druid-Guardian','Paladin-Holy','Warrior-Fury','Rogue-Outlaw','Monk-Brewmaster','Warrior-Arms','Paladin-Protection','Mage-Fire',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Activion:BAAANQAECgIIAwAAAA==.',
Ad='Addelana:BAAANQADCgQIBAAAAA==.Adelanaa:BAABNQAECoEcAAQBAAgKJhGdWwDfAQABAAgK1hCdWwDfAQACAAUKFQgdEwDcAAADAAEKJgFlgwAWAAABNQADCgQIBAAEAAAAAA==.Adrasta:BAAANQAECgUIBQAAAA==.Adriell:BAAANQAECgUICwAAAA==.Adura:BAAANQADCgcICAAAAA==.',
Ae='Aelathe:BAAANQAECgIIAgAAAA==.Aeneas:BAAANQAECggICQAAAA==.Aenimma:BAABNQAECoEjAAIFAAgKvQNWjADNAAAFAAgKvQNWjADNAAAAAA==.Aerys:BAAANQADCggIDQAAAA==.',
Ak='Akey:BAABNQAECoEZAAIGAAgKwAVtlgCoAQAGAAgKwAVtlgCoAQAAAA==.',
Al='Alamwah:BAAANQADCgEIAQABNQAECggIEgAEAAAAAA==.Alaroo:BAAANQAECgYIBwAAAA==.Alatao:BAAANQABCgYIBwAAAA==.Aleinaas:BAAANQADCgYICgAAAA==.Aleine:BAAANQAECgUIBgAAAA==.Alektra:BAABNQAECoEhAAIHAAkKyxHxCgA+AgAHAAkKyxHxCgA+AgAAAA==.Alexella:BAAANQADCgcICQAAAA==.Allerfala:BAAANQADCgQIBAABNQAECgEIAQAEAAAAAA==.Alliete:BAAANQADCgIIAgAAAA==.Allya:BAAANQAECgQICwABNQAECgUICgAEAAAAAA==.Aloine:BAABNQAECoEoAAIBAAkKbwMoegByAQABAAkKbwMoegByAQAAAA==.Alteredbeast:BAAANQAECgQIBAABNQAECgkJKAAIAG8ZAA==.',
Am='Amogus:BAAANQAECgUICQAAAA==.Amoresh:BAAANQAECgQJCQAAAA==.Ampuzzible:BAAANQAFFAMIAwAAAA==.',
An='Anbebi:BAAANQAECgYICgAAAA==.Anchor:BAAANQABCgEIAgAAAA==.Anqu:BAAANQADCgMIAwAAAA==.',
Ar='Arawynn:BAAANQAECgIIAQAAAA==.Arbitera:BAABNQAECoEYAAIJAAgKQBvzDwBYAgAJAAgKQBvzDwBYAgAAAA==.Arkona:BAAANQADCggIFQAAAA==.Arthelais:BAAANQAECgYIDAAAAA==.Arzir:BAABNQAECoEuAAIKAAkKQhbiDAA6AgAKAAkKQhbiDAA6AgAAAA==.',
As='Ashbringer:BAAANQAECgYICwAAAA==.Asmonjoel:BAAANQADCgcICAAAAA==.Assumi:BAAANQADCggIJAAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Audree:BAAANQADCgYIBAAAAA==.Aurellia:BAAANQAECggICQAAAA==.',
Av='Avoide:BAAANQAECgIIAgAAAA==.',
Ax='Axedup:BAAANQAECgcIDwABNQAFFAYIFgALAMYdAA==.',
Ay='Aydy:BAAANQAECgYIDgAAAA==.',
Az='Azamat:BAAANQAECgMIBAAAAA==.Azuredemonx:BAABNQAECoFFAAILAAgKERzKFACpAgALAAgKERzKFACpAgAAAA==.',
Ba='Backup:BAAANQAECgQIEAAAAA==.Balayn:BAAANQADCgYICQAAAA==.Banan:BAAANQAECgIIAgAAAA==.Banhbolock:BAAANQAECggIEgAAAA==.Banoni:BAAANQABCgQIBgABNQAECgIIAgAEAAAAAA==.',
Bb='Bbajer:BAAANQAECgMIAQAAAA==.Bbqporkbuns:BAACNQAFFIEFAAIMAAIKQR1mBACyAAAMAAIKQR1mBACyAAA1AAQKgSwAAgwACQrnIRIDAGoDAAwACQrnIRIDAGoDAAAA.',
Be='Bearzy:BAAANQAECgEIAgAAAA==.Bearzz:BAABNQAECoEqAAIGAAgKyh10NwChAgAGAAgKyh10NwChAgAAAA==.Beefcakes:BAAANQADCgEIAQAAAA==.Bekinsale:BAAANQADCgYIBgABNQAECgMIBAAEAAAAAA==.Belledormi:BAABNQAECoEnAAQNAAcKUgtcIgAYAQANAAYKeQlcIgAYAQAOAAIKCgz7GgBpAAAPAAIKbgs3QgBiAAAAAA==.Bellest:BAABNQAECoEcAAMIAAkKWhCRTAAYAgAIAAkKWhCRTAAYAgAQAAQKXQGq4AB7AAAAAA==.Benji:BAABNQAECoEfAAMIAAkKyiPXDwBcAwAIAAkKyiPXDwBcAwAQAAYKvAqtpAD9AAAAAA==.',
Bf='Bfev:BAAANQAECgcIEAAAAA==.',
Bg='Bggestthighs:BAAANQAECgQIBQABNQAECgcJLAARACQVAA==.',
Bi='Bid:BAABNQAECoEeAAIGAAcKsx0IWQA/AgAGAAcKsx0IWQA/AgAAAA==.Bigado:BAAANQADCggICgAAAA==.Bigalo:BAABNQAECoEaAAISAAcKTw9lBwDTAQASAAcKTw9lBwDTAQAAAA==.Bigarms:BAAANQAECgcIDAAAAA==.Bigfel:BAAANQABCgQIBAAAAA==.Biggesthighz:BAABNQAECoEsAAIRAAcKJBXcLwCmAQARAAcKJBXcLwCmAQAAAA==.Bird:BAAANQAECgMIBQAAAA==.',
Bl='Blindanddeaf:BAABNQAECoEVAAMTAAcKyhBkOAC6AQATAAcKyhBkOAC6AQAUAAEKwQfvLQAnAAAAAA==.Bluee:BAAANQAECgIIAgABNQAECgYIFAAVAHIVAA==.',
Bo='Boohbooh:BAAANQADCggIFQAAAA==.Boomakus:BAABNQAECoEXAAIWAAkKcxZ/NwAIAgAWAAkKcxZ/NwAIAgAAAA==.',
Br='Brannie:BAAANQAECgUJBwAAAA==.Brenine:BAABNQAECoEiAAMWAAcKnRINRQCwAQAWAAcKnRINRQCwAQAXAAMKhgsyJgCnAAAAAA==.Brewskie:BAAANQADCgEIAgAAAA==.Brodess:BAACNQAFFIELAAIIAAUK9BvbEQASAQAIAAUK9BvbEQASAQA1AAQKgTMAAwgACQokJh8BAPIDAAgACQokJh8BAPIDABAAAQpPC+MRASMAAAAA.Brody:BAABNQAECoEWAAILAAkKrB78DgDsAgALAAkKrB78DgDsAgAAAA==.Bromorc:BAAANQADCgcIGAAAAA==.Broner:BAABNQAECoEYAAIYAAcKdAx6MQBUAQAYAAcKdAx6MQBUAQAAAA==.Bronlite:BAAANQADCgYIEwAAAA==.Brorn:BAAANQADCgQIBAAAAA==.Brotherlee:BAABNQAECoEsAAIZAAkKThrxSQCQAgAZAAkKThrxSQCQAgAAAA==.',
Bu='Bubski:BAAANQAECgMIBQAAAA==.Bulimio:BAAANQADCgIIAgAAAA==.Bumpymonkey:BAAANQAECggIBwAAAA==.Bunz:BAAANQAECgUIBQAAAA==.Buratt:BAAANQADCgcIGAAAAA==.Busterx:BAAANQADCgQIBAAAAA==.Butternut:BAAANQAECgYIBgAAAA==.',
['Bé']='Béllâ:BAAANQADCggIAgAAAA==.',
['Bõ']='Bõggie:BAAANQAECgcICwABNQAFFAYIEQAFAGIYAA==.',
Ca='Calabor:BAAANQADCggJDQAAAA==.Caleano:BAAANQADCgQIBAAAAA==.Capacitør:BAABNQAECoEcAAIIAAcKFh8gNwB0AgAIAAcKFh8gNwB0AgAAAA==.Cardib:BAABNQAECoEsAAMaAAkKCCGQOACPAgAaAAcKnyGQOACPAgAHAAMKtRhbNQDhAAAAAA==.Carlîn:BAAANQAECgUIBQAAAA==.Cattamend:BAABNQAECoEkAAMCAAkK3xwOBACAAgABAAcKayFUJQC5AgACAAgKjxkOBACAAgAAAA==.Cattawrath:BAAANQAECggIEAAAAA==.Cattazap:BAABNQAECoEcAAMQAAkK2iOFBQCKAwAQAAkK2iOFBQCKAwAIAAIKlxul3gCgAAAAAA==.Cauliflawer:BAAANQAECgcIEwAAAA==.Cavoda:BAAANQADCgMIAwAAAA==.',
Ch='Chakrakhan:BAABNQAECoEYAAIYAAgKExShIgDlAQAYAAgKExShIgDlAQAAAA==.Char:BAAANQAECgQIBQAAAA==.Chase:BAAANQAECgMIBQAAAA==.Chaysey:BAAANQADCgIIAgAAAA==.Chinadh:BAACNQAFFIEWAAILAAYKxh1OAgBHAgALAAYKxh1OAgBHAgA1AAQKgSQAAgsACQpHJA0HAFkDAAsACQpHJA0HAFkDAAAA.Chinahunter:BAAANQAECggIEAABNQAFFAYIFgALAMYdAA==.Chinamage:BAABNQAECoEaAAIbAAgKSSJMNwANAwAbAAgKSSJMNwANAwABNQAFFAYIFgALAMYdAA==.Chopzuey:BAAANQADCgQICAAAAA==.Chugtiki:BAABNQAECoEpAAMIAAkKUBjKMwCEAgAIAAkKUBjKMwCEAgAQAAEKSgsMDQEnAAAAAA==.Chuunky:BAAANQABCgIIAgAAAA==.',
Ci='Cinderaz:BAAANQADCgcIGAAAAA==.',
Cl='Clikboomboom:BAAANQADCgUIBwAAAA==.',
Co='Cones:BAAANQADCgcIDgABNQAECgcIDAAEAAAAAA==.Conesworth:BAABNQAECoEoAAIIAAkKbxlMNACBAgAIAAkKbxlMNACBAgAAAA==.Conesy:BAAANQAECgUIDAABNQAECgkJKAAIAG8ZAA==.Coquina:BAAANQAECgIIAgAAAA==.Cordeilia:BAACNQAFFIEKAAIBAAQKiQe6FQAXAQABAAQKiQe6FQAXAQA1AAQKgTUAAgEACQqhFtM0AHMCAAEACQqhFtM0AHMCAAAA.Cordi:BAAANQABCgEIAQAAAA==.Corruptax:BAAANQADCgcIDgAAAA==.Costiigan:BAAANQADCgYIBgAAAA==.',
Cr='Critsaquino:BAABNQAECoEaAAMcAAgKBRYpIgBIAgAcAAgKBRYpIgBIAgAdAAQKNg9aMwD/AAAAAA==.Critsngigs:BAAANQAECgcIDgAAAA==.Crotchsniffa:BAAANQAECgEIAQAAAA==.Crowlêy:BAAANQAECgEIAQABNQAECgkJNgAGAO4eAA==.',
Cy='Cyberlust:BAAANQADCggICAAAAA==.Cyklar:BAAANQADCgcIFgAAAA==.',
Da='Daddydevito:BAABNQAECoEvAAIWAAkKsQqdSACcAQAWAAkKsQqdSACcAQAAAA==.Daddythyme:BAAANQAECgcIEQAAAA==.Dames:BAAANQADCgYIBgAAAA==.Damocies:BAAANQAECgcIBgAAAA==.Danky:BAAANQAECgUICAAAAA==.Daqueta:BAAANQAECgYICQAAAA==.Daquetarg:BAAANQAECgMIBAAAAA==.Daquetawar:BAAANQAECgQIBAAAAA==.Dardrolor:BAAANQAECgEIAQAAAA==.Darknstormy:BAAANQADCgcIFAABNQADCggIFQAEAAAAAA==.Darkpal:BAAANQAECggJEAAAAA==.Dazrawr:BAAANQAECgYICQAAAA==.Dazzi:BAAANQADCgYIEgAAAA==.',
De='Deathdaddy:BAAANQAECgEIAQAAAA==.Decapitation:BAAANQAECgYIDgAAAA==.Deepkingz:BAAANQAECggIEgAAAA==.Defacedd:BAAANQADCgYICgAAAA==.Deify:BAAANQAECgQIBwAAAA==.Deifyh:BAAANQADCgQIBQAAAA==.Deliaz:BAAANQADCgcIGAAAAA==.Destruction:BAAANQAECggICAAAAA==.',
Di='Digitalhungr:BAAANQAECgQIBAABNQAECgkJKAAIAG8ZAA==.Dismarryx:BAAANQAECgEIAgAAAA==.',
Dj='Djapana:BAAANQADCgcIGgABNQADCggIFQAEAAAAAA==.Djshadowz:BAAANQAECgEIAQAAAA==.',
Dk='Dkunt:BAAANQAECgYIBQAAAA==.',
Dn='Dnomm:BAAANQADCgcIGAAAAA==.',
Do='Dogmuffin:BAAANQADCgMIAwAAAA==.Doristhedull:BAAANQAECgUIBgAAAA==.',
Dp='Dps:BAAANQAECgIIAgAAAA==.',
Dr='Drakyon:BAAANQAECgMIBgAAAA==.Dreaddlord:BAAANQAECgQIBAABNQAECggIHAAWAAgIAA==.Dreadiedude:BAABNQAECoEcAAMWAAgK8QhmTACIAQAWAAgK8QhmTACIAQAeAAEK2QFUbAAnAAAAAA==.Drowlie:BAAANQADCgYIBgABNQAECgYICwAEAAAAAA==.Drust:BAAANQAECgQICAABNQAECggIDQAEAAAAAA==.',
Du='Durrin:BAAANQAECgQIBwAAAA==.Dutchman:BAAANQAECgUIDQAAAA==.',
Ef='Effectus:BAABNQAECoEaAAQaAAgKuw42eADQAQAaAAgKuw42eADQAQAHAAIKtQRcZgBJAAAfAAEKNwdDLgAuAAAAAA==.',
Ei='Eith:BAAANQAECgcIDwAAAA==.',
El='Elele:BAAANQABCgUIBQAAAA==.Eljay:BAAANQAECgYJDwAAAA==.Ellell:BAABNQAECoE1AAIIAAgKEwlOfwB2AQAIAAgKEwlOfwB2AQAAAA==.Ellieb:BAAANQAECgcICQAAAA==.Elliemental:BAAANQABCggIDQAAAA==.',
Em='Emberly:BAAANQADCgEIAQAAAA==.Emsulquiorra:BAAANQAECgMIBAAAAA==.',
En='Endersfault:BAABNQAECoEoAAIKAAkKPx6zBQD0AgAKAAkKPx6zBQD0AgAAAA==.Enterni:BAAANQAECgUIBQAAAA==.Enve:BAAANQADCgIIAgABNQAECgUIBQAEAAAAAA==.',
Ep='Epicdemoness:BAABNQAECoEiAAILAAkKgBl0FACsAgALAAkKgBl0FACsAgAAAA==.',
Er='Eroni:BAABNQAECoEYAAIGAAgKogvWdwDxAQAGAAgKogvWdwDxAQAAAA==.',
Eu='Euphea:BAAANQADCgcIDgAAAA==.',
Ev='Evaelfie:BAACNQAFFIEKAAMgAAQKXw9JCQAFAQAgAAQKaw5JCQAFAQAFAAMKqgu9EADIAAA1AAQKgSIAAyAACQrGEVAuAPcBACAACQq7EFAuAPcBAAUABQoSDlV3ABMBAAAA.',
Fa='Fanks:BAAANQAECgIIAgABNQAECgUIBQAEAAAAAA==.Farrand:BAAANQAECggIBwAAAA==.',
Fe='Fearology:BAAANQAECgQIBAAAAA==.Felcollins:BAAANQAECgMIAwAAAA==.Felicia:BAABNQAECoEfAAITAAkK4B/3DAAqAwATAAkK4B/3DAAqAwAAAA==.Fellordkiki:BAABNQAECoEkAAQfAAgKOhDcDgA7AQAfAAUKtg/cDgA7AQAaAAYKeAtRzAAEAQAHAAQKIAxnNADmAAAAAA==.',
Fi='Filthydh:BAAANQADCgYIBgABNQAECgkJJgAZAAkkAA==.Filthypally:BAABNQAECoEmAAIZAAkKCSRCFABkAwAZAAkKCSRCFABkAwAAAA==.Fivëam:BAAANQABCgIJAgAAAA==.',
Fl='Flashheart:BAAANQAECgUICgAAAA==.Fleabag:BAAANQADCgYIEwAAAA==.',
Fo='Fossgate:BAAANQAECggIEQABNQAECggIIwAFAL0DAA==.Foxe:BAEANQADCgMIAwABNQAECgcIIgAKAOwjAA==.',
Fr='Freezefauker:BAABNQAECoEcAAIhAAgKaBMxCgD3AQAhAAgKaBMxCgD3AQAAAA==.Fridge:BAABNQAECoEdAAIbAAcK8yKxWAC9AgAbAAcK8yKxWAC9AgAAAA==.Frostxfury:BAAANQAECggIEAAAAA==.Frøstynips:BAACNQAFFIEcAAQgAAcKERg9AgDtAQAgAAYKBRU9AgDtAQAFAAQKOhlOCQBZAQAVAAIKnxnQGQCaAAA1AAQKgTwAAyAACQrrJW8GAGoDACAACQp5JW8GAGoDAAUACQqnJTAQACADAAAA.',
Fu='Furysdeath:BAAANQAECgcIBwAAAA==.Furysgrip:BAABNQAECoElAAIVAAkKkRknHgCnAgAVAAkKkRknHgCnAgAAAA==.',
['Fì']='Fìsty:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECoEdAAMGAAYKCwfowQBKAQAGAAYKCwfowQBKAQARAAEKsgJ5iQAiAAABNQAECgEIAQAEAAAAAA==.Gaidal:BAABNQAECoEgAAMXAAYKyhwmDgD7AQAXAAYKyhwmDgD7AQAiAAIKkhrVOACaAAAAAA==.Galafrey:BAAANQAECgQIBQABNQAECggIGgAGAO4bAA==.Garaktou:BAAANQADCgQICAAAAA==.Gashweaver:BAAANQADCgMJAwAAAA==.',
Ge='Gekyum:BAACNQAFFIENAAIRAAUKCSIjBQDpAQARAAUKCSIjBQDpAQA1AAQKgSsAAhEACQqAIxUGAGYDABEACQqAIxUGAGYDAAAA.Getinmyspit:BAAANQAECgQIBQAAAA==.',
Gh='Ghazgkhull:BAAANQADCgYIDQABNQAECgIIAgAEAAAAAA==.',
Gi='Gidyana:BAAANQAECgMIAwAAAA==.Girlsdayoni:BAAANQAECgQICAAAAA==.Girlsnight:BAAANQADCgQIBwAAAA==.',
Gl='Glancelot:BAABNQAECoEZAAIZAAkK3x4ILQD2AgAZAAkK3x4ILQD2AgAAAA==.Glipglorp:BAAANQADCgQIBAAAAA==.',
Gn='Gnuh:BAAANQAECgMIAwABNQAECgcIGAAKAAchAA==.Gnurse:BAAANQAECgYIDgAAAA==.',
Go='Gommo:BAABNQAECoEXAAIZAAgKyRF2hADsAQAZAAgKyRF2hADsAQAAAA==.Goodgirl:BAAANQAECgYICAAAAA==.Gorbad:BAAANQAECgEIAQAAAA==.',
Gr='Greggoryy:BAAANQAECgIIAgAAAA==.Groundizzle:BAABNQAECoEYAAIBAAkK5BLyQwA2AgABAAkK5BLyQwA2AgAAAA==.',
Gt='Gtoromu:BAAANQADCggIFAAAAA==.',
Gu='Guanyu:BAAANQAECgUICwAAAA==.Guccisosa:BAAANQADCgYIBgAAAA==.Guccisweet:BAAANQADCggIDAAAAA==.Guineamon:BAAANQAECgEIAQAAAA==.',
Ha='Hammel:BAAANQAECggIAQAAAA==.Haruk:BAABNQAECoEtAAMjAAkKTCF0DABWAwAjAAkKTCF0DABWAwAZAAQK7xaG5gAUAQAAAA==.Hattle:BAAANQADCgEIAQAAAA==.',
He='Heatfist:BAAANQAECgUIEgAAAA==.Helldridge:BAAANQAECgQIBwAAAA==.Heåls:BAAANQAECgUIEAAAAA==.',
Hi='Hiruke:BAAANQAECgQIBAAAAA==.Hirukek:BAAANQAECgcICAAAAA==.',
Ho='Hoelishock:BAAANQAECgYIDgAAAA==.Hollynova:BAAANQAECgQIBQAAAA==.Holychad:BAABNQAECoEqAAMjAAkK4BazMACIAgAjAAkK4BazMACIAgAZAAgKxRYXfQAAAgAAAA==.Honeydew:BAACNQAFFIEUAAMYAAYKhhUoBADNAQAYAAYKhhUoBADNAQAJAAEK8RUjCgBOAAA1AAQKgS8AAhgACQpUIqwKABIDABgACQpUIqwKABIDAAAA.Honganteresa:BAAANQAECgYIEgAAAA==.Hoofmax:BAAANQADCgYICAAAAA==.Hotteemie:BAAANQADCgcIDgAAAA==.',
Hu='Huddson:BAAANQAECgQIBAAAAA==.',
['Hø']='Høtdøts:BAAANQAECgEIAQAAAA==.',
If='Ifrit:BAAANQAECgIIAwABNQAFFAUICgAjAFkdAA==.',
Il='Illidank:BAABNQAECoEcAAMTAAkKOhiLHACQAgATAAkKOhiLHACQAgALAAIK3wT0WQBPAAAAAA==.',
Im='Imanoob:BAAANQAECgYIBgAAAA==.Imperiex:BAAANQADCgEIAQAAAA==.',
In='Infectedlock:BAAANQAECgcIDAABNQAFFAYIFgALAMYdAA==.Inurdreams:BAAANQABCgcICAAAAA==.',
Io='Ionsw:BAABNQAECoEhAAMaAAkKgRXSYgANAgAaAAgKtxXSYgANAgAHAAUKBQx4LgAGAQAAAA==.',
Ip='Ipsifu:BAAANQAECgcICQABNQAFFAUIEgAdALUaAA==.',
Ir='Ironski:BAAANQAECgIIAwAAAA==.',
Ja='Jabutak:BAAANQADCgIIAgAAAA==.Jackillz:BAAANQADCgUIBQABNQAECgcIEAAEAAAAAA==.Jatzsy:BAAANQAECgMIBQAAAA==.Jayar:BAAANQAECgYIDQAAAA==.Jazzy:BAAANQADCgUIBQAAAA==.',
Je='Jee:BAABNQAECoEaAAIhAAgKHgaQEwBIAQAhAAgKHgaQEwBIAQAAAA==.Jenkem:BAAANQABCgQIBgAAAA==.Jescon:BAAANQAECgIIAgAAAA==.Jeé:BAAANQADCgUJBQAAAA==.',
Ji='Jiamil:BAABNQAECoEiAAIjAAkKthuOGgD4AgAjAAkKthuOGgD4AgAAAA==.Jigolow:BAAANQADCgUIBQAAAA==.',
Jo='Johlissa:BAAANQAECgIIAgAAAA==.Jolteon:BAAANQAECgYICwAAAA==.',
Ju='Jubber:BAABNQAECoEdAAQFAAcKzSEbNgAsAgAFAAYKkyIbNgAsAgAgAAcK6RpCKgAUAgAVAAcKGBZYRwC8AQAAAA==.',
Jy='Jynx:BAAANQAECgEIAQAAAA==.',
Ka='Kadashy:BAAANQAFFAQIAgAAAA==.Kadashyb:BAAANQAECgEIAQABNQAFFAQIAgAEAAAAAA==.Kadashyy:BAAANQAECgIIAwABNQAFFAQIAgAEAAAAAA==.Kaherd:BAABNQAECoEaAAIkAAcKxxLtDADEAQAkAAcKxxLtDADEAQAAAA==.Kakapooeybum:BAAANQAECgUIBgAAAA==.Kakashimaya:BAAANQADCgQIBgAAAA==.Kamikasi:BAAANQAECgEIAQAAAA==.Kaneshiro:BAABNQAECoEdAAIbAAgKJBR1swD6AQAbAAgKJBR1swD6AQAAAA==.Karytheca:BAAANQADCgYIBAAAAA==.Katae:BAAANQAFFAIIAgAAAA==.Kayrali:BAAANQADCgIIAgAAAA==.',
Kb='Kboomz:BAAANQADCgYIEQABNQADCggIFQAEAAAAAA==.',
Ke='Kegaz:BAAANQAECgUICAAAAA==.Kegward:BAAANQADCgUIBQAAAA==.Kelynada:BAABNQAECoEWAAIaAAYKdBAqogBhAQAaAAYKdBAqogBhAQAAAA==.Kendd:BAACNQAFFIEeAAMdAAcKLhu7AQA/AgAdAAYKoRy7AQA/AgAcAAQKHxAoCABLAQA1AAQKgS0ABB0ACQpqI2oFACoDAB0ACQpxH2oFACoDABwABQr8Ip8tAPoBACUABwpCECAMAH8BAAAA.Kerrigân:BAAANQAECgIIAgAAAA==.Keyshock:BAAANQADCgYJBgAAAA==.',
Ki='Kindra:BAAANQADCgYIBgAAAA==.Kinore:BAAANQAECgQIBAAAAA==.Kithari:BAABNQAECoEcAAMLAAgK7SB6DAAMAwALAAgK7SB6DAAMAwAUAAMKmxnMGgDVAAAAAA==.',
Kn='Knickerbits:BAAANQABCgEIAQAAAA==.Knotting:BAAANQADCggIFgAAAA==.',
Ko='Kochez:BAAANQADCgUICQAAAA==.Kollateral:BAAANQAECgUICQAAAA==.',
Kr='Kraejekta:BAAANQAECgYIBgAAAA==.Krankiekunt:BAACNQAFFIEKAAImAAQKzxc8BAArAQAmAAQKzxc8BAArAQA1AAQKgSgAAiYACQoIIUYEAB8DACYACQoIIUYEAB8DAAAA.Krellhim:BAAANQAECgIIAQAAAA==.',
Ku='Kuanija:BAABNQAECoEgAAMMAAkKbhyrBwDzAgAMAAkKbhyrBwDzAgAIAAUKUhFMnwAoAQAAAA==.Kuuga:BAABNQAECoEaAAMnAAgKrw01mQC0AQAnAAgKrw01mQC0AQAkAAEKoQnYLgAxAAAAAA==.',
La='Landwalker:BAACNQAFFIEJAAIeAAMKDhZ+CQD/AAAeAAMKDhZ+CQD/AAA1AAQKgR0AAh4ACQovH/cJAA0DAB4ACQovH/cJAA0DAAAA.Langas:BAAANQAECgIIAQABNQAECggIBgAEAAAAAA==.Langasbrew:BAAANQAECggIBgAAAA==.Latorius:BAAANQAECgcIEQAAAA==.Lavaloadz:BAAANQADCggIDQAAAA==.Lazziel:BAAANQAECgUICgAAAA==.',
Le='Leelu:BAAANQAECgIIAgAAAA==.Lexavis:BAACNQAFFIEJAAMjAAUK6w5IDwAwAQAjAAQKXwlIDwAwAQAZAAIKNRkGHACXAAA1AAQKgToAAyMACQr5H6QNAE0DACMACQr5H6QNAE0DABkACQp+IhwxAOcCAAE1AAQKCQk4ABsArw8A.Leyi:BAAANQAECgUICgABNQAECgcIHQAbAAoQAA==.Leyiast:BAABNQAECoEdAAIbAAcKChBy0wC6AQAbAAcKChBy0wC6AQAAAA==.Leyissa:BAAANQADCgIIAgABNQAECgcIHQAbAAoQAA==.',
Lh='Lheo:BAAANQADCgYICAAAAA==.',
Li='Liggma:BAAANQAECgQICAAAAA==.Lightborn:BAAANQADCggICAAAAA==.Lilbai:BAAANQAECggIEgABNQAECggIEgAEAAAAAA==.Lilpowpow:BAAANQADCgcIBwABNQADCggIFQAEAAAAAA==.Lilthicc:BAAANQAECgEIAQAAAA==.Lilwhite:BAAANQAECgcIEgABNQAECggIEgAEAAAAAA==.Liminal:BAAANQADCgcJBwAAAA==.',
Lo='Lockaboom:BAAANQAECgcIEwAAAA==.Loldruid:BAABNQAECoEcAAMWAAgKCAiQUABwAQAWAAgKCAiQUABwAQAeAAMKIwbLWQBsAAAAAA==.Lom:BAABNQAECoEjAAIQAAkKsRIpSQASAgAQAAkKsRIpSQASAgAAAA==.Lomzz:BAAANQADCgIJAgAAAA==.Lootee:BAAANQAECgEIAQAAAA==.Lorvensire:BAAANQADCgYIBwAAAA==.',
Lu='Lukie:BAEANQAECgIIAgAAAA==.Lunadae:BAAANQADCgQIBAAAAA==.',
Ly='Lycan:BAAANQADCgEIAQAAAA==.Lym:BAAANQAECgUIBQAAAA==.Lynarium:BAAANQAECgEIAQAAAA==.Lyradaeris:BAAANQADCgcIBwAAAA==.',
['Lÿ']='Lÿrath:BAAANQADCggIEwAAAA==.',
Ma='Magepill:BAAANQADCgQIBAAAAA==.Magharitta:BAABNQAECoEhAAMFAAgK/R9eKAB4AgAFAAcKQCJeKAB4AgAgAAIK0BJYewBzAAAAAA==.Magroth:BAABNQAECoEXAAIbAAgK/BINsQD+AQAbAAgK/BINsQD+AQAAAA==.Mahwae:BAAANQADCgIIAwAAAA==.Makavelli:BAAANQADCgIIAgAAAA==.Manoliso:BAAANQAECgUICQAAAA==.Marmite:BAAANQAECgcIDgAAAA==.Maybeforever:BAAANQAECgQIBwAAAA==.',
Me='Medesin:BAAANQADCgYIFwAAAA==.Mekhanite:BAABNQAECoEZAAIVAAgK6x5mGgDDAgAVAAgK6x5mGgDDAgAAAA==.Mercykill:BAAANQADCgUIBQAAAA==.',
Mi='Milfdella:BAAANQAECgMIAwAAAA==.Milspec:BAAANQAECgYIEgAAAA==.Minami:BAABNQAECoEcAAIoAAgKtRRNHADfAQAoAAgKtRRNHADfAQAAAA==.Minhiriath:BAAANQADCgQIBAAAAA==.Mintbadger:BAAANQADCgUIBwAAAA==.Mistea:BAAANQADCgMJAwAAAA==.Misticuffs:BAAANQAECgMIBAABNQAECgEIAQAEAAAAAA==.Mixxie:BAAANQADCgMIAwABNQAECgcICQAEAAAAAA==.',
Mo='Mochimask:BAAANQAECgYIDAAAAA==.Moetown:BAAANQADCggICAABNQAFFAUIFwAbACcYAA==.Moistex:BAAANQAECgQICAABNQAECgkJIQAKAPoaAA==.Moistmaker:BAABNQAECoFAAAIQAAgKXST0EQAgAwAQAAgKXST0EQAgAwAAAA==.Mold:BAAANQAECgUIBwABNQAECgcIDwAEAAAAAA==.Momotaku:BAABNQAECoEZAAMIAAgK0hB2WwDhAQAIAAgK0hB2WwDhAQAQAAYKag+TiwA+AQAAAA==.Monalisa:BAAANQAECggIEwAAAA==.Monkmon:BAAANQADCgIIAgABNQAECgYIEwAEAAAAAA==.Monthax:BAAANQAECgUIBQAAAA==.Moonoo:BAAANQADCgUIBQAAAA==.Mordok:BAAANQAECgEIAQAAAA==.Morena:BAAANQADCggIGAAAAA==.Morgaina:BAAANQAECgUICgAAAA==.',
Mu='Muffinman:BAAANQAECggIBgABNQAECggIBgAEAAAAAA==.Muscleclub:BAABNQAECoEoAAIJAAkKhhyXCADqAgAJAAkKhhyXCADqAgAAAA==.',
My='Mysticalzz:BAAANQAECgMIBAAAAA==.',
['Më']='Mëmëmë:BAAANQAECgMIBAAAAA==.',
['Mù']='Mùji:BAAANQAECgEIAQAAAA==.',
['Mü']='Müddrätt:BAAANQAECgEIAQAAAA==.',
Na='Naeff:BAAANQAECgYIAQAAAA==.Natria:BAABNQAECoEgAAINAAgKDQv0FwCqAQANAAgKDQv0FwCqAQAAAA==.Naya:BAABNQAECoEpAAIbAAkK3yVDBADTAwAbAAkK3yVDBADTAwAAAA==.',
Ne='Nerfdehoof:BAAANQAECgQIBAAAAA==.Nerfdelag:BAABNQAECoEZAAIFAAkKTxMsPAAKAgAFAAkKTxMsPAAKAgAAAA==.Nerfgün:BAABNQAECoEaAAIGAAgK7ht0TQBeAgAGAAgK7ht0TQBeAgAAAA==.Nescåfe:BAAANQADCgYJBgAAAA==.',
Ni='Nicodautroc:BAAANQAECgUICgAAAA==.Ninish:BAAANQADCgMIBQAAAA==.Nintone:BAAANQAECgYICwAAAA==.',
No='Nonippies:BAAANQAECgUIDQAAAA==.Noolie:BAAANQADCgIIAgABNQAECgYICwAEAAAAAA==.',
Ns='Nsi:BAAANQADCgUJCAAAAA==.',
Nu='Nubishe:BAAANQAECgMIAwAAAA==.Nutsdormu:BAABNQAECoEfAAIPAAYKrxJUKgA1AQAPAAYKrxJUKgA1AQAAAA==.',
Ny='Nythe:BAAANQADCgEIAQABNQADCgIIAgAEAAAAAA==.Nyxmoona:BAAANQADCgcIGAAAAA==.',
['Nà']='Nàishà:BAAANQAECgcICgAAAA==.',
Ob='Obskurer:BAABNQAECoEeAAMQAAkKeBn2KgCUAgAQAAkKeBn2KgCUAgAIAAMKNRDw2wCnAAAAAA==.',
Od='Odinwolf:BAAANQAECgQICQABNQAFFAUICgAjAFkdAA==.',
Oj='Ojisancage:BAABNQAECoE4AAIaAAgKOSChIgDiAgAaAAgKOSChIgDiAgAAAA==.',
Om='Omegaflaps:BAAANQAECgYJBgAAAA==.Omnitract:BAAANQADCgUIBQAAAA==.',
Or='Orinys:BAABNQAECoEiAAIPAAcKcREKIQCpAQAPAAcKcREKIQCpAQAAAA==.Orkky:BAABNQAECoEiAAMVAAkKiyDzCwBDAwAVAAkKiyDzCwBDAwAgAAEK9wtzlQAxAAAAAA==.',
Pa='Page:BAABNQAECoEjAAMcAAkKLxYGKQAYAgAcAAgK/BMGKQAYAgAdAAgK9g6dGgDwAQAAAA==.Pakurruun:BAAANQAECgUIDwAAAA==.Palahan:BAAANQADCgYIBwAAAA==.Palala:BAAANQADCgcIBwABNQAECgYIEQAEAAAAAA==.Pallatress:BAAANQADCgcIGAAAAA==.Pandor:BAAANQAECgEIAQAAAA==.Panginoon:BAABNQAECoEkAAMgAAkKTR++FADEAgAgAAkKixu+FADEAgAFAAgKcx+rIwCVAgAAAA==.Paparìch:BAABNQAECoElAAIWAAkKhyDvFAAJAwAWAAkKhyDvFAAJAwAAAA==.Paphio:BAAANQADCggIDAAAAA==.Parrymore:BAAANQAECggIAQAAAA==.',
Pe='Perden:BAAANQADCgYIBgAAAA==.Pesh:BAAANQADCgYIDQAAAA==.',
Pg='Pgundry:BAAANQAECgMIBAAAAA==.',
Ph='Phakin:BAAANQADCgMIAwAAAA==.Phex:BAAANQAECgMJAwAAAA==.',
Pi='Picks:BAAANQABCgEIAQAAAA==.Piddlesworth:BAAANQADCggIFwAAAA==.Piergeiron:BAAANQAECgYIBAAAAA==.Pinkyblue:BAABNQAECoEfAAMaAAkKsx66SABbAgAaAAgKjB26SABbAgAHAAIK9x+/QwCrAAAAAA==.Pipssqeek:BAAANQAECgIIAgAAAA==.',
Pj='Pjw:BAABNQAECoEnAAIjAAkKEhfDLQCUAgAjAAkKEhfDLQCUAgAAAA==.',
Pl='Plarrior:BAAANQADCgMIAwAAAA==.Plip:BAABNQAECoE+AAQIAAgKohzMMgCIAgAIAAgKohzMMgCIAgAMAAIK7AvAKQB7AAAQAAEKjgOuGgEbAAAAAA==.',
Po='Pokerrface:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.Polloloco:BAAANQADCgEIAQAAAA==.Poobumhead:BAABNQAECoEiAAIaAAcKDRKSeQDMAQAaAAcKDRKSeQDMAQAAAA==.Porkroll:BAAANQAECgQIBAAAAA==.Poweredman:BAAANQADCgIIAgAAAA==.Powerheal:BAAANQAECgUIBQAAAA==.',
Pr='Praetoar:BAAANQADCgYJBgAAAA==.Prftlybalncd:BAABNQAECoEXAAIPAAcKIxWHHQDXAQAPAAcKIxWHHQDXAQABNQAECgkJJwAjABIXAA==.Probabele:BAAANQAECgEIAgAAAA==.Probably:BAACNQAFFIEkAAMgAAYK9x+lAQANAgAgAAYK9x+lAQANAgAVAAEKkBAfLAAxAAA1AAQKgUUABCAACQrrJPMGAGEDACAACQrrJPMGAGEDABUAAQr/HK2vAEsAAAUAAQrnE7PHADoAAAAA.Protato:BAAANQADCggJCAAAAA==.',
Ps='Psyche:BAAANQAECggIDQABNQAECgkJHgAQAHgZAA==.',
Pt='Ptrie:BAACNQAFFIEGAAIbAAMK1Af9MQDOAAAbAAMK1Af9MQDOAAA1AAQKgRYAAhsACApUGu9vAIgCABsACApUGu9vAIgCAAAA.',
Pu='Pudgeyp:BAABNQAECoEeAAInAAkKFhkeTwCBAgAnAAkKFhkeTwCBAgAAAA==.Pudgeyr:BAAANQAECgYIBAAAAA==.Punj:BAAANQAECgQIBwAAAA==.Puntarr:BAAANQAECgEIAQAAAA==.Puppybonks:BAAANQAECgIIAgAAAA==.Purdxpriest:BAAANQABCggICAABNQADCggJDwAEAAAAAA==.Purdxwarrior:BAAANQABCgQIBQABNQADCggJDwAEAAAAAA==.',
Pw='Pwrbottom:BAAANQAECgQIAwAAAA==.',
Py='Pyroskolv:BAAANQAECgIIAQABNQAFFAUIEAALADsaAA==.Pytranze:BAAANQAECgYIBgAAAA==.',
Qi='Qibla:BAABNQAECoEfAAIZAAgKAAzoogCjAQAZAAgKAAzoogCjAQAAAA==.',
Qu='Quarizma:BAACNQAFFIEVAAIRAAcKyyL8AADEAgARAAcKyyL8AADEAgA1AAQKgTAAAhEACQqJJcMCAKsDABEACQqJJcMCAKsDAAAA.',
Ra='Radiantbunz:BAAANQADCggIIAAAAA==.Rakayashi:BAAANQAECgUIBQAAAA==.Rankone:BAAANQAECgMIBAABNQAECgQICwAEAAAAAA==.Raxe:BAEBNQAECoEiAAIKAAcK7COxBgDXAgAKAAcK7COxBgDXAgAAAA==.',
Re='Reaperoffire:BAAANQAECgEIAQAAAA==.Repliod:BAABNQAECoEcAAIiAAYKdiRJDABlAgAiAAYKdiRJDABlAgAAAA==.Reploid:BAAANQADCgcIBwABNQAECgYIHAAiAHYkAA==.Restho:BAABNQAECoEfAAMQAAgK0h4wOQBSAgAQAAcKJiIwOQBSAgAIAAcKSBTGZQC+AQAAAA==.Revarix:BAABNQAECoEeAAIgAAgK9hTdKAAeAgAgAAgK9hTdKAAeAgAAAA==.',
Rh='Rhaella:BAAANQAECgcIEwAAAA==.Rhuiser:BAABNQAECoEgAAInAAkKRCEULgDyAgAnAAkKRCEULgDyAgAAAA==.Rhuno:BAAANQAECgQICAAAAA==.',
Ri='Rigormortits:BAAANQAECgIIAgABNQAECgkJHAATADoYAA==.Ritsuki:BAAANQAECgUIDAAAAA==.Ritéboys:BAABNQAECoEaAAIZAAkKBiT7CgCbAwAZAAkKBiT7CgCbAwAAAA==.Ritëboys:BAABNQAECoEbAAMLAAgKOCGOFQCfAgALAAgKOCGOFQCfAgATAAMKdg3WawCSAAABNQAECgkJGgAZAAYkAA==.',
Ro='Rocketjuice:BAABNQAECoE0AAMbAAgKthpPgQBjAgAbAAgK1RhPgQBjAgAhAAEKdh6PMQBdAAAAAA==.Roflpwnnt:BAAANQAECgcIDwAAAA==.Ronjames:BAAANQADCgUICAAAAA==.Ronnycoleman:BAAANQAECgEIAQAAAA==.Rootweaver:BAAANQAECgQIBAAAAA==.Rothy:BAAANQAECggIEgAAAA==.',
Ru='Rutee:BAABNQAECoEoAAIZAAkK4xagWABjAgAZAAkK4xagWABjAgAAAA==.',
Ry='Ryz:BAAANQAECgEJAQABNQAECgcIEQAEAAAAAA==.',
Sa='Saard:BAAANQAECgcICAABNQAFFAUICwAbAAQQAA==.Saethene:BAAANQAECgEIAQABNQAECggIGgAGAO4bAA==.Safh:BAAANQADCggICgAAAA==.Safk:BAABNQAECoEnAAIVAAkK0xdoJQB1AgAVAAkK0xdoJQB1AgAAAA==.Saleina:BAAANQADCgIIAwAAAA==.Sandiwang:BAAANQADCgUICAAAAA==.Sangwoo:BAAANQADCgIIAgAAAA==.Sanosan:BAAANQAECgMIAwAAAA==.Sanosanz:BAAANQAECgIIBAAAAA==.Saptko:BAAANQADCgUIBQAAAA==.Sartoc:BAAANQAECgMIBAABNQAECggIGgAGAO4bAA==.',
Sc='Scabbo:BAAANQAECgYICgAAAA==.Scalesoul:BAAANQAECggIJgAAAQ==.',
Sd='Sdfgoose:BAAANQAECgYICAAAAA==.',
Se='Seiferoth:BAACNQAFFIEKAAIjAAUKWR0zCAC3AQAjAAUKWR0zCAC3AQA1AAQKgScAAiMACQpEI8AHAIADACMACQpEI8AHAIADAAAA.Selitha:BAAANQADCgQIBAAAAA==.Sergantcolen:BAAANQAECgUIBgAAAA==.Señornanna:BAAANQADCgQIBAAAAA==.',
Sh='Shaddai:BAABNQAECoEaAAIoAAgKmhgpFgAmAgAoAAgKmhgpFgAmAgAAAA==.Shadowofevil:BAABNQAECoEXAAIaAAcKmwbpsAA+AQAaAAcKmwbpsAA+AQAAAA==.Shadypally:BAAANQADCgUICgAAAA==.Shakywing:BAAANQADCgIIAgAAAA==.Shalavoo:BAAANQAECgIIAgAAAA==.Shamankiller:BAAANQAECgMICAAAAA==.Shamazzle:BAAANQAECgYIDwAAAA==.Shamlen:BAABNQAECoE5AAIIAAgKxQfJeACHAQAIAAgKxQfJeACHAQAAAA==.Sharkyob:BAAANQAECgQICgAAAA==.Shichokeme:BAAANQADCgMIAwAAAA==.Shiicho:BAAANQADCgYICwAAAA==.Shinieedruid:BAABNQAECoEYAAIWAAgKxhg/NgAQAgAWAAgKxhg/NgAQAgAAAA==.Shions:BAAANQADCgYIBgAAAA==.Shockostoob:BAABNQAECoEcAAQMAAcKfAglHQBWAQAMAAYKKgglHQBWAQAQAAQKgwuKuwDHAAAIAAIKpgU8/wBVAAAAAA==.',
Si='Sidatas:BAAANQAECgcICQAAAA==.Silverspulse:BAABNQAECoFPAAIBAAgKXSK3EQAmAwABAAgKXSK3EQAmAwAAAA==.Sinequanon:BAABNQAECoEjAAMDAAgKfRVOJADmAQADAAcKQhhOJADmAQABAAgKxBXBWQDlAQAAAA==.Sinfulbeast:BAABNQAECoE2AAQGAAkK7h5SGAAhAwAGAAkK7h5SGAAhAwASAAMK/RJbDADdAAARAAEKrQjqewA0AAAAAA==.Sippycup:BAAANQAECgcICAABNQAECgkJIQAbAGEbAA==.',
Sk='Skrogan:BAAANQAECgMIAwAAAA==.Skulv:BAACNQAFFIEQAAMLAAUKOxopBQDDAQALAAUKOxopBQDDAQATAAEK7AHZGwA3AAA1AAQKgSoAAwsACQrlI9AEAIADAAsACQrlI9AEAIADABMAAgpyFapvAIEAAAAA.',
Sl='Slakzor:BAAANQADCgQIAwAAAA==.Slammed:BAAANQAECgYIEwAAAA==.Sleepyshark:BAABNQAECoEYAAMaAAgKlRg/SwBTAgAaAAgKlRg/SwBTAgAHAAEKzAImfwAjAAAAAA==.Slopain:BAABNQAECoEeAAIUAAcKbR05CABHAgAUAAcKbR05CABHAgAAAA==.Slopflop:BAAANQAECggIBgAAAA==.Slowlearner:BAABNQAECoEcAAIGAAgKZhkePwCJAgAGAAgKZhkePwCJAgAAAA==.Slåppery:BAABNQAECoEvAAIRAAkKHSQmAwCjAwARAAkKHSQmAwCjAwAAAA==.',
Sm='Smashy:BAAANQADCggIGQAAAA==.Smìtty:BAAANQADCgcIDAAAAA==.',
Sn='Snorlax:BAABNQAECoEXAAIIAAgK0B/JKAC8AgAIAAgK0B/JKAC8AgAAAA==.Snort:BAAANQAECgUIDAAAAA==.',
So='Sona:BAAANQAECggIEAAAAA==.Sonotafurry:BAAANQAECgIIAgAAAA==.Soresu:BAAANQAECgUICgAAAA==.Soundwit:BAABNQAECoEkAAIcAAcK3SAoGQCLAgAcAAcK3SAoGQCLAgAAAA==.',
Sp='Sparrowstalk:BAAANQADCgEIAQAAAA==.Spindrift:BAAANQAECgYIEQAAAA==.Spoonyy:BAACNQAFFIEQAAMbAAUK6x7ZDwDSAQAbAAUK6x7ZDwDSAQAhAAEKzRxWDQBOAAA1AAQKgSYAAxsACQodIixEAO0CABsACQqiISxEAO0CACEAAgpvJW4fAMsAAAAA.Spudder:BAAANQABCgIIAgABNQABCgQIAwAEAAAAAA==.',
Sq='Squanchie:BAAANQAECgEIAgABNQAECgcIGAAGAMYVAA==.',
St='Starstorm:BAAANQADCgYJBgAAAA==.Steinlarger:BAAANQAECggIDQAAAA==.Stephen:BAAANQAECgYIDAABNQAECggIHwAQANIeAA==.Storrmbender:BAAANQAECgYJDgAAAA==.Stoutbrew:BAAANQADCggICQAAAA==.Strípe:BAAANQAECgcICgAAAA==.Stuy:BAABNQAECoEtAAIRAAkKAhoZEwC0AgARAAkKAhoZEwC0AgAAAA==.Stãria:BAAANQAECgcIDQAAAA==.Stårlå:BAAANQABCgcIDAAAAA==.Störme:BAAANQADCgcIDwAAAA==.',
Su='Sugarburst:BAAANQAECgMICAAAAA==.Sukmahdisc:BAAANQAECggICgAAAA==.Supl:BAAANQAECgIIAQAAAA==.',
Sw='Swak:BAABNQAECoEzAAIGAAgKeRZhWQA+AgAGAAgKeRZhWQA+AgAAAA==.Sweet:BAAANQAECgMIAQAAAA==.Switchmage:BAAANQADCggJEAAAAA==.Switchskin:BAABNQAECoElAAIWAAkK9B9iEgAfAwAWAAkK9B9iEgAfAwAAAA==.',
Sy='Syvrogue:BAABNQAECoEYAAIdAAkK8Al7GgDyAQAdAAkK8Al7GgDyAQABNQAECgQIBQAEAAAAAA==.',
Ta='Tallinor:BAABNQAECoEiAAMhAAcKqg9eDwCHAQAhAAcKqg9eDwCHAQApAAEKhgZDDAAyAAAAAA==.Tamuka:BAAANQAECggIDQAAAA==.Tanags:BAABNQAECoEbAAIQAAcK3iJOJQCxAgAQAAcK3iJOJQCxAgAAAA==.Tankakus:BAAANQAECgEIAwABNQAECgkJFwAWAHMWAA==.Tardis:BAAANQAECgYIBgAAAA==.Taumast:BAAANQADCgMIAwABNQAECgkJGAABAOQSAA==.Tauter:BAAANQADCgcIFQAAAA==.Tazzee:BAAANQAECgQICAAAAA==.',
Te='Temperature:BAAANQAECgIIBgABNQAECgMIBgAEAAAAAA==.Testaxltesta:BAABNQAECoEkAAMBAAgK5SOxEgAgAwABAAgKfiOxEgAgAwACAAUK6yQNBgAdAgABNQADCggIDgAEAAAAAA==.',
Th='Thael:BAAANQADCgQIBAAAAA==.Thalia:BAABNQAECoElAAIoAAkKTRg8DgCTAgAoAAkKTRg8DgCTAgAAAA==.Thoriatit:BAABNQAECoEUAAIVAAYKchWgUACRAQAVAAYKchWgUACRAQAAAA==.Thottydot:BAAANQAECgEIAQAAAA==.Thox:BAAANQADCgIIAgAAAA==.Throber:BAAANQADCgUJBQAAAA==.Thunderzz:BAAANQADCggIDQABNQADCggIFQAEAAAAAA==.Thyranux:BAAANQADCgMIBAAAAA==.',
Ti='Tienchi:BAABNQAECoEYAAMYAAgKFB1cHQAfAgAYAAgKDhpcHQAfAgAmAAUKfhwKFQByAQAAAA==.Tiendira:BAAANQAECgYIBgAAAA==.Tierk:BAAANQADCggICAABNQAECgkJIwAcAC8WAA==.Tim:BAABNQAECoEWAAIjAAkKaCCGDgBHAwAjAAkKaCCGDgBHAwAAAA==.Timmyy:BAAANQAECgEIAQAAAA==.Tinainverse:BAAANQAECgIIAgAAAA==.',
Tl='Tlo:BAAANQADCgcIBwABNQAFFAUIEgAGAPAbAA==.',
To='Tollmemaybe:BAABNQAECoFYAAMoAAkKByMVAwCGAwAoAAkKByMVAwCGAwAZAAUKLRD+4gAbAQAAAA==.Tormént:BAABNQAECoEqAAIgAAkK+iKuBgBlAwAgAAkK+iKuBgBlAwAAAA==.',
Tr='Transport:BAAANQAECgMIBgAAAA==.Traumatizer:BAAANQADCggJDQAAAA==.Trenbolone:BAAANQADCgIIAwAAAA==.Tronix:BAAANQAECgUICAAAAA==.Trucidario:BAAANQAECgIIAgAAAA==.Trulsdk:BAAANQAECgQIBAABNQAECgkJKQAnAEIgAA==.Truwar:BAABNQAECoEpAAInAAkKQiAhJQAVAwAnAAkKQiAhJQAVAwAAAA==.',
Tu='Tubbquake:BAABNQAECoEYAAIMAAgKDR87CgC8AgAMAAgKDR87CgC8AgAAAA==.Tuffhunts:BAAANQAECgMIBQAAAA==.Tufflock:BAAANQADCgEJAQAAAA==.',
Tw='Twatasaurus:BAAANQAECgQICgAAAA==.Twink:BAAANQAECggIBAABNQAECgMIBQAEAAAAAA==.',
['Tî']='Tîmmeh:BAAANQAECgYIDAABNQAECgEIAQAEAAAAAA==.',
['Tï']='Tïmmeh:BAAANQAECggIDAABNQAECgEIAQAEAAAAAA==.',
Ub='Ubica:BAABNQAECoErAAMcAAkKERKyIABSAgAcAAkKERKyIABSAgAdAAQK1ATnOgC6AAAAAA==.',
Ul='Ultratunee:BAAANQAECgYICwABNQAFFAMIBgAbANQHAA==.',
Un='Unholykníght:BAAANQADCgEIAQAAAA==.Unvoid:BAAANQAECgIICAAAAA==.',
Ur='Urzog:BAAANQADCgUIBQAAAA==.',
Us='Useacooldown:BAAANQAECgYICAABNQAECgcIDAAEAAAAAA==.',
Va='Valaya:BAAANQAECgIIAwAAAA==.Valentine:BAAANQAECgcIDgAAAA==.Valithor:BAAANQAECgMIBAAAAA==.Valkyrion:BAACNQAFFIEFAAIPAAMKpw2dDgDbAAAPAAMKpw2dDgDbAAA1AAQKgSUAAg8ACQq6ISkFAFEDAA8ACQq6ISkFAFEDAAAA.Valysan:BAAANQADCgEIAQAAAA==.Vann:BAAANQADCggIEgAAAA==.Vasaar:BAAANQADCgUIBQAAAA==.',
Ve='Velathri:BAAANQAECgYICgAAAA==.Velenlerolan:BAACNQAFFIEJAAIFAAUKLBzNBQClAQAFAAUKLBzNBQClAQA1AAQKgS0AAgUACQoXJtEFAI0DAAUACQoXJtEFAI0DAAAA.Velrayne:BAABNQAECoEkAAMGAAkKYRd8UwBOAgAGAAcKExx8UwBOAgARAAcKngYWPABCAQAAAA==.Veng:BAAANQABCgQIBAAAAA==.Verailde:BAAANQADCgUICQAAAA==.Verathriel:BAAANQABCgQIBgAAAA==.Verilence:BAABNQAECoEjAAQaAAcKaCMXLQC4AgAaAAcKRSMXLQC4AgAfAAUKJBxYDQBbAQAHAAEK1h3MZABNAAAAAA==.Veventhius:BAAANQADCgIIAgAAAA==.Vext:BAAANQADCgMIAwAAAA==.',
Vi='Vindicor:BAAANQAECgcIEAAAAA==.',
Vo='Voidberg:BAAANQAECgQIBQABNQAECgkJJgAeANoeAA==.Vorndryad:BAAANQAECgEIAgAAAA==.',
Vr='Vras:BAAANQADCgUICAAAAA==.',
Vy='Vynburn:BAABNQAECoEsAAIbAAkK1BhlXAC0AgAbAAkK1BhlXAC0AgAAAA==.',
Wa='Warmon:BAAANQAECgQIBAAAAA==.Watson:BAAANQAECgYIEQAAAA==.Waveryy:BAAANQADCgMIBgAAAA==.',
We='Wemblitz:BAAANQADCgcIEgAAAA==.Wesh:BAACNQAFFIEFAAIFAAIKVgRhGAB1AAAFAAIKVgRhGAB1AAA1AAQKgTQABAUACQoDGkM+AAACAAUACAoBG0M+AAACABUABwoME2ZPAJcBACAABQqTCsFbAOkAAAAA.',
Wh='Whio:BAABNQAECoEeAAIYAAcKNRO/KACnAQAYAAcKNRO/KACnAQAAAA==.Whitetabby:BAABNQAECoEWAAIUAAkKuhYsBwBsAgAUAAkKuhYsBwBsAgAAAA==.Whtclass:BAAANQAECgMIAwAAAA==.',
Wi='Wintersfence:BAAANQADCgYJCAAAAA==.',
Wk='Wkwk:BAAANQAECgQIDgAAAA==.',
Wo='Wozxx:BAAANQAECgcICAAAAA==.',
Wp='Wpd:BAACNQAFFIEGAAIWAAMKCxXnEwDsAAAWAAMKCxXnEwDsAAA1AAQKgTEAAhYACQrpIYkLAGEDABYACQrpIYkLAGEDAAAA.',
['Wî']='Wîngman:BAABNQAECoEjAAIZAAkKHxhKUwByAgAZAAkKHxhKUwByAgAAAA==.',
Xe='Xenarn:BAEBNQAECoEiAAImAAcKHhArFACAAQAmAAcKHhArFACAAQAAAA==.Xenoruin:BAABNQAECoEcAAITAAgKPQUCSABRAQATAAgKPQUCSABRAQAAAA==.Xertzart:BAAANQAECgUICgABNQAECgcIGwAQAN4iAA==.',
Xi='Xiphios:BAAANQADCgYIBgAAAA==.',
Ya='Yarpidk:BAAANQADCgcJCQAAAA==.',
Ye='Yejin:BAAANQAECgMIAwAAAA==.',
Yo='Yorkie:BAACNQAFFIEHAAIbAAQKbhD5HwBFAQAbAAQKbhD5HwBFAQA1AAQKgS8AAhsACQpFIGUkAEIDABsACQpFIGUkAEIDAAAA.Yoyogi:BAAANQADCgYIBwAAAA==.',
Yu='Yui:BAAANQADCggICAABNQAFFAIIAwAEAAAAAA==.Yurarzir:BAABNQAECoErAAIbAAkKLxaobACQAgAbAAkKLxaobACQAgAAAA==.',
Za='Zanisha:BAABNQAECoEaAAIWAAcKFweqXAA2AQAWAAcKFweqXAA2AQAAAA==.Zaris:BAAANQADCgQIBAAAAA==.Zaz:BAAANQADCgYIBwAAAA==.',
Ze='Zelendorm:BAABNQAECoEYAAIZAAgKHhp8ZgA7AgAZAAgKHhp8ZgA7AgAAAA==.',
Zj='Zjathezra:BAAANQADCgcIBwAAAA==.',
Zo='Zorevi:BAAANQAECgEIAQAAAA==.',
Zu='Zula:BAAANQADCggIBwABNQAECgQIBwAEAAAAAA==.',
['Ås']='Åshz:BAAANQADCgIIAgABNQAECgUIEAAEAAAAAA==.',
['ßa']='ßaccycønes:BAAANQADCggIIwAAAA==.',
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
