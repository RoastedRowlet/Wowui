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

local lookup = {'Hunter-BeastMastery','Hunter-Survival','Mage-Frost','Paladin-Retribution','Unknown-Unknown','Priest-Shadow','Priest-Holy','Paladin-Holy','DeathKnight-Unholy','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Druid-Balance','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Mage-Fire','Warrior-Arms','Evoker-Preservation','Rogue-Subtlety','Mage-Arcane','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement','DemonHunter-Devourer','Paladin-Protection','Warlock-Demonology','Warlock-Affliction','Hunter-Marksmanship','Rogue-Assassination','Monk-Mistweaver','DeathKnight-Frost','Priest-Discipline','Warrior-Protection','DemonHunter-Vengeance','Evoker-Augmentation','Druid-Guardian','Warrior-Fury','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aarix:BAABNQAECn8oAAMBAAoKLxbZVgBuAgABAAoKLxbZVgBuAgACAAIKRgbiEABkAAAAAA==.',
Ac='Achmed:BAAANQAECgEIBAAAAA==.Actrise:BAAANQADCgcIBwAAAA==.',
Ad='Addÿ:BAABNQAECn8dAAIDAAYKNxz1DgC7AQADAAYKNxz1DgC7AQAAAA==.',
Ae='Aelasong:BAACNQAFFH8IAAIEAAMKIBUpGADnAAAEAAMKIBUpGADnAAA1AAQKfyYAAgQACgroIFU7AOUCAAQACgroIFU7AOUCAAE1AAMKBQgFAAUAAAAA.Aelinessa:BAAANQAECgYIDgAAAA==.',
Af='Afflíctd:BAAANQADCgcICAAAAA==.',
Al='Aldrîch:BAAANQAECgcIDwAAAA==.Allyra:BAAANQAECgcIDQABNQAECggIDAAFAAAAAA==.Allzerim:BAAANQAECgEIAgABNQAECgcIHAAGAPARAA==.Allzora:BAABNQAECn8cAAMGAAcK8BE4KQDeAQAGAAcK8BE4KQDeAQAHAAUKDCEhJgBnAQAAAA==.Allzorath:BAAANQADCgYIBwABNQAECgcIHAAGAPARAA==.Aloki:BAAANQAECgYICAAAAA==.Alorarose:BAAANQAECgEIAQAAAA==.',
Am='Amberness:BAABNQAECn8pAAIBAAkKFSVLDwBoAwABAAkKFSVLDwBoAwAAAA==.Ametrius:BAAANQADCggIEAAAAA==.Ampd:BAAANQADCgYIEgAAAA==.',
An='Anabanana:BAAANQABCgQIAwABNQAECgoKNgAIADwcAA==.Anastassia:BAABNQAECn82AAIIAAoKPBwkGwAJAwAIAAoKPBwkGwAJAwAAAA==.André:BAABNQAECn8wAAIEAAkKrSDKDAAaAgAEAAkKrSDKDAAaAgAAAA==.Antraxus:BAAANQAECgEIAgAAAA==.Anuke:BAAANQAECgUICAAAAA==.Anástásia:BAAANQADCggICAAAAA==.',
Ar='Arando:BAAANQADCgEIAQAAAA==.Arestoz:BAABNQAECn8YAAIJAAgK6h+IMwBdAgAJAAgK6h+IMwBdAgAAAA==.Arflane:BAAANQAECgEIAQAAAA==.Ariakith:BAAANQADCgEIAQAAAA==.Arkhlight:BAAANQAECggIDQAAAA==.Arkhmonk:BAABNQAECn8qAAIKAAoK1xIdHwA3AgAKAAoK1xIdHwA3AgAAAA==.Arkillos:BAAANQAECgYICwAAAA==.Armerous:BAAANQABCgcIDwAAAA==.Armonos:BAABNQAECn8hAAILAAkKsRRXQgDzAQALAAkKsRRXQgDzAQAAAA==.Arowynn:BAAANQADCgUIBQABNQAECggIEAAFAAAAAA==.Arrowhoof:BAEANQAECgUIEAAAAA==.Arthurian:BAAANQADCgEIAQAAAA==.Artémis:BAAANQADCgEIAgAAAA==.',
As='Ashiri:BAAANQAECgEIAgAAAA==.Ashmage:BAAANQAECgQJBQAAAA==.Ashmorph:BAABNQAECn8YAAQMAAcKeRc/FgCWAQAMAAYKqBc/FgCWAQANAAYKnxImHwDyAAAOAAIK8x5uVAC2AAABNQAECgQJBQAFAAAAAA==.Asterisk:BAABNQAECn8uAAIBAAoKpBEcDQAJAgABAAoKpBEcDQAJAgAAAA==.Asteriøn:BAAANQAECgUIBQAAAA==.Astromo:BAAANQADCgMJBQAAAA==.Asya:BAAANQAECggICwAAAA==.Asymmetric:BAAANQAECggIAwAAAA==.',
At='Attilathepun:BAAANQADCggICAAAAA==.',
Au='Auriêl:BAAANQAECgEIAQAAAA==.',
Ax='Axxiom:BAAANQABCgUIBQAAAA==.Axxium:BAACNQAFFH8JAAIPAAMK+hiuCQDqAAAPAAMK+hiuCQDqAAA1AAQKfzkAAw8ACgrwHlMmAMsCAA8ACgrwHlMmAMsCABAABwpzCESoAEMBAAAA.',
Az='Azastra:BAABNQAECn8bAAIRAAYKRAu0BwD8AAARAAYKRAu0BwD8AAAAAA==.Azorian:BAAANQAECgIIBQAAAA==.',
['Añ']='Aña:BAAANQAECgQIDgAAAA==.Añarchist:BAAANQADCgUJBwABNQAECgQIDgAFAAAAAA==.',
Ba='Babymonstter:BAAANQADCgEIAQAAAA==.Baelzharon:BAABNQAECn8fAAISAAgKSgxhAwDDAQASAAgKSgxhAwDDAQAAAA==.Baericade:BAAANQADCgMIAwABNQADCgYIBgAFAAAAAA==.Bagelpanda:BAAANQAECgMIBQAAAA==.Balgrim:BAABNQAECn8VAAITAAcK6hK4sACjAQATAAcK6hK4sACjAQAAAA==.Balki:BAAANQADCgcIBwABNQAECgoKKwAUAKoTAA==.Bandicoot:BAAANQADCgYIDQAAAA==.Barsch:BAAANQAECgEIAgAAAA==.Basalt:BAABNQAECn8dAAIBAAgKBBWXHgCdAQABAAgKBBWXHgCdAQAAAA==.Bastenwode:BAAANQAECgQIBgAAAA==.Bawce:BAAANQAECgEIAQAAAA==.',
Bb='Bbye:BAAANQADCggIDQAAAA==.',
Be='Beanboi:BAAANQADCgIIAgAAAA==.Bebynoob:BAAANQAECgYIDgAAAA==.Becký:BAAANQAECgQIDgAAAA==.Beedriven:BAAANQAECgYIDAABNQAECgcIKQAFAAAAAQ==.Beroan:BAABNQAECn8WAAIVAAcKNQn6GgAKAQAVAAcKNQn6GgAKAQAAAA==.Bertrille:BAAANQADCgYICQAAAA==.',
Bi='Biabia:BAAANQADCgUIBQABNQAECgcIKQAFAAAAAQ==.Bigcøøkie:BAAANQAECgEIAgAAAA==.Bigolcrities:BAAANQADCggJEgAAAA==.Bigshaft:BAAANQADCgYICgABNQADCggICgAFAAAAAA==.Bigwannabe:BAAANQAECgcIEAAAAA==.Binboi:BAAANQAECgEIAQAAAA==.',
Bl='Blackmagma:BAAANQAECgUIBgABNQAECgcIHgAQAKgbAA==.Blackpinkk:BAABNQAECn8kAAIBAAkKtyI+DgBvAwABAAkKtyI+DgBvAwAAAA==.Blackppinkk:BAABNQAECn8fAAMOAAoKZhylBgDgAQAOAAoKZhylBgDgAQANAAEKAADvywAVAAAAAA==.Bloodbunny:BAAANQAECgQIBgAAAA==.Bloodpack:BAAANQAECgEIAgAAAA==.Blëssed:BAAANQADCgMIBAAAAA==.',
Bo='Boggartt:BAAANQAECgMIAwAAAA==.Bootscoots:BAAANQAECgYICAAAAA==.Bornite:BAAANQADCgUICgAAAA==.Bowme:BAAANQAECgYIEQAAAA==.',
Br='Braedae:BAAANQAECgIIAwAAAA==.Brickaton:BAAANQAECgUIDQAAAA==.Brocknor:BAABNQAECn8sAAITAAgKGxo1ZgBcAgATAAgKGxo1ZgBcAgAAAA==.Broodling:BAAANQABCgEIAQAAAA==.Brookie:BAAANQADCgMIAwAAAA==.',
Bu='Buckeyes:BAAANQAECggIEwAAAA==.Buddhaspalm:BAAANQAECgEIAQAAAA==.Bullets:BAAANQAECgEIAgAAAA==.Butterdtoast:BAEBNQAECn8lAAIKAAcKVxmGEAArAQAKAAcKVxmGEAArAQAAAA==.',
Bw='Bwansamdi:BAAANQAECgEIAQAAAA==.',
Ca='Cabbresoa:BAABNQAECn8YAAILAAcKfwieggDyAAALAAcKfwieggDyAAAAAA==.Caboose:BAABNQAECn8iAAIWAAkKXx/GBACTAgAWAAkKXx/GBACTAgAAAA==.Cadbvucolta:BAAANQADCgUIBwAAAA==.Cadius:BAAANQAECgEIAQAAAA==.Caledor:BAAANQAECggIDgAAAA==.Calet:BAAANQADCggIHAAAAA==.Calindrel:BAABNQAECn8kAAITAAoKFQfeXADfAAATAAoKFQfeXADfAAAAAA==.Caliriya:BAAANQADCggIFAAAAA==.Candren:BAAANQAECgEIAQAAAA==.Caraway:BAAANQAECgUIDAAAAA==.Castiêl:BAAANQAECgMIAwAAAA==.',
Ce='Celaela:BAAANQAECggIAgAAAA==.Celant:BAAANQADCggIHAAAAA==.Celson:BAAANQAECgUIEAAAAA==.Celticlore:BAAANQAECgEIAgAAAA==.Cerrvantes:BAAANQAECgIIAgAAAA==.',
Ch='Charlemange:BAAANQAECgMIBAAAAA==.Chernaboz:BAABNQAECn8lAAIXAAgK7hTvAQBdAQAXAAgK7hTvAQBdAQAAAA==.Chevelot:BAAANQADCgQIBgAAAA==.Chibbo:BAAANQAECgQIBAAAAA==.Chiblet:BAABNQAECn8iAAIGAAgKpQdYNgBxAQAGAAgKpQdYNgBxAQAAAA==.Chioma:BAAANQADCgcIDAABNQAECgoKOAAYAHwWAA==.',
Ci='Ci:BAAANQADCgMIBgAAAA==.',
Cl='Cledwyn:BAAANQADCgMIAwAAAA==.Cloudsinger:BAABNQAECn8tAAIKAAoKQRlpFgCcAgAKAAoKQRlpFgCcAgAAAA==.',
Co='Codysseuz:BAAANQADCgQIBAAAAA==.Columbo:BAAANQADCgUIBQAAAA==.Combustdeez:BAABNQAECn8qAAIWAAoKGib1AQDvAwAWAAoKGib1AQDvAwAAAA==.Convrge:BAAANQAECgEIAQAAAA==.Corenthos:BAABNQAECn81AAMJAAoKNxluDAB+AQAJAAoKjxhuDAB+AQALAAcKjhJZXgB4AQAAAA==.Corlys:BAAANQAECgEIAQAAAA==.Corên:BAAANQAECgEIAQAAAA==.',
Cr='Cranker:BAAANQADCgUIBQAAAA==.Crashed:BAAANQABCgUIBgAAAA==.Crazymoron:BAABNQAECn8UAAIDAAgK6gxuDwCyAQADAAgK6gxuDwCyAQAAAA==.Creepndeath:BAAANQAECggIDAAAAA==.Creselia:BAAANQAECgcIDwAAAA==.Critmaw:BAAANQAECgEIAQABNQAECgkJHgAWAGMgAA==.Crowley:BAAANQADCgYICwAAAA==.Crum:BAAANQAECgYIBgAAAA==.Crumdumpster:BAAANQAECgYIDgABNQAECgYIBgAFAAAAAA==.Crèmefraîche:BAABNQAECn8iAAIZAAgKyBCEBgCQAQAZAAgKyBCEBgCQAQAAAA==.',
Cu='Cuddlerz:BAABNQAECn8ZAAIPAAYKKCCREwC4AQAPAAYKKCCREwC4AQAAAA==.',
Cy='Cypherrellik:BAAANQAECgQIBwABNQAECgYIDAAFAAAAAA==.',
Da='Dagthunderer:BAAANQAECgYIDAAAAA==.Dakkenrahl:BAAANQADCgcIFgAAAA==.Dalatras:BAAANQAECgcIBwABNQAECggIDAAFAAAAAA==.Dalistra:BAAANQAECggIDAAAAA==.Dalweaver:BAAANQADCgUIBQABNQAECggIDAAFAAAAAA==.Damogdem:BAAANQADCgYICAAAAA==.Dangly:BAACNQAFFH8NAAMEAAUKqhMcCQDWAAAEAAQKqhMcCQDWAAAIAAEKyQEuFgA7AAA1AAQKfyIAAwQACgp0Gis2AF8BAAQACgp0Gis2AF8BAAgABwqECJSnADMBAAAA.Dantes:BAAANQADCgcIFgAAAA==.Dar:BAAANQAECgEIAQAAAA==.Darkflame:BAABNQAECn8fAAIBAAgKixKbbAA5AgABAAgKixKbbAA5AgAAAA==.Darklûrker:BAAANQAECgIIAgAAAA==.Darksidedbro:BAAANQADCgUIBQAAAA==.Darkzelda:BAAANQADCggICAAAAA==.Dashen:BAAANQAECgMIAwAAAA==.Dayve:BAABNQAECn8qAAINAAgK5hFIPwAAAgANAAgK5hFIPwAAAgAAAA==.',
Dc='Dcpt:BAAANQAECgIIAwAAAA==.',
De='Deadgeinside:BAAANQAECgQIBQAAAA==.Deadgenah:BAAANQAECgEIBAAAAA==.Deadgnome:BAABNQAECn8ZAAILAAgKkRrpKgBvAgALAAgKkRrpKgBvAgAAAA==.Deadlÿ:BAAANQAECgEIAgABNQAECgoKKgAWABomAA==.Deathgimbo:BAAANQAECggIDwAAAA==.Deathstomper:BAACNQAFFH8JAAITAAUKAA41DADPAAATAAUKAA41DADPAAA1AAQKfxoAAhMACgqfF701AD4BABMACgqfF701AD4BAAAA.Delirious:BAAANQADCgEIAQABNQAECgkJLAAaAOoXAA==.Demondono:BAABNQAECn8uAAIYAAgKgg9SGwAaAQAYAAgKgg9SGwAaAQAAAA==.Dethalas:BAAANQAECgIIBQAAAA==.Dethtoy:BAAANQADCgcIBwABNQAECgkJHgAbABoMAA==.Devomo:BAAANQAECgIIAwAAAA==.Dewight:BAAANQAECgEIAQAAAA==.Deyedora:BAAANQAECgcIDwAAAA==.Dezax:BAABNQAECn8ZAAIcAAkKPhhXVABZAgAcAAkKPhhXVABZAgAAAA==.',
Di='Diaboli:BAAANQADCgQICAAAAA==.Dilligafnope:BAAANQADCgcJBwAAAA==.Dinohunter:BAABNQAECn8aAAIBAAgKsBwURACfAgABAAgKsBwURACfAgAAAA==.Disabler:BAAANQAECgIIAwABNQAECgoKKgAWABomAA==.',
Dj='Djdiddles:BAABNQAECn8nAAIZAAkKrBvIAwDZAQAZAAkKrBvIAwDZAQAAAA==.',
Do='Dorimane:BAAANQAECgcIKQAAAQ==.Dorlock:BAABNQAECn8cAAIdAAgKAQeNBQDkAAAdAAgKAQeNBQDkAAAAAA==.Dorotti:BAAANQAECgUIDAABNQAECggIGQAWAGQWAA==.Doubled:BAAANQADCgIIAgAAAA==.',
Dr='Dragondznuts:BAAANQAECgIIAwAAAA==.Drais:BAAANQADCgIIBQABNQADCgQIBgAFAAAAAA==.Drazgul:BAAANQADCgcIDAAAAA==.Drdukesilver:BAAANQADCgQIBAAAAA==.Dreadpanda:BAACNQAFFH8HAAITAAMKQRHdCwDUAAATAAMKQRHdCwDUAAA1AAQKfz8AAhMACgocIL0oABcDABMACgocIL0oABcDAAAA.Dred:BAAANQAECgQIBAAAAA==.Dredkin:BAAANQADCgQIBAAAAA==.Dredwarrior:BAAANQADCgIIAgAAAA==.Drenleigh:BAAANQAECgMIAwAAAA==.Drosmoke:BAAANQAECgQIBgAAAA==.Drprodigy:BAAANQAECgUICgAAAA==.Drunkbaby:BAAANQAECggIDwAAAA==.',
Dy='Dybuck:BAAANQAECgMIBAAAAA==.Dyrcyn:BAABNQAECn8gAAMEAAgKDw5gWwAOAQAEAAgKtQlgWwAOAQAbAAIKMxRPYABaAAAAAA==.',
['Dà']='Dànger:BAABNQAECn8wAAQBAAkKTiNoFQBHAwABAAkKTiNoFQBHAwACAAYKEhrDAgBqAQAeAAQK3AQJZgCTAAAAAA==.',
Ed='Edroh:BAABNQAECn8hAAMWAAgKdgidQgA3AQAWAAgKHgidQgA3AQADAAEKDQmcRQA4AAAAAA==.',
Ei='Eidur:BAABNQAECn8dAAIfAAkKDxbvIgBvAgAfAAkKDxbvIgBvAgAAAA==.Eightohfive:BAAANQADCgUIBwAAAA==.',
Ek='Ekøh:BAAANQADCgQICAAAAA==.',
El='Elará:BAAANQADCgYIBgAAAA==.Eleannora:BAAANQADCgEIAQAAAA==.Elemane:BAAANQAECgcIDQABNQAECgcIKQAFAAAAAQ==.Elemefayoh:BAABNQAECn8eAAMPAAcKXSRgKQC+AgAPAAcKXSRgKQC+AgAQAAEKAACtIgFMAAAAAA==.Elementlo:BAABNQAECn8iAAIZAAoK0iNrBgAeAwAZAAoK0iNrBgAeAwABNQABCgIIAgAFAAAAAA==.Elf:BAAANQAECgEIAQAAAA==.Elirune:BAAANQAECgEIAQAAAA==.Elonwe:BAAANQAECgEIAQAAAA==.Elsafromtemu:BAABNQAECn8eAAMDAAkK5QqEDwCxAQADAAkK5QqEDwCxAQASAAMKfAAWDABCAAAAAA==.Elspeth:BAABNQAECn8sAAIbAAgKAiEPCgD6AgAbAAgKAiEPCgD6AgAAAA==.',
Em='Emagonarain:BAAANQAFFAIIAgAAAA==.Emagonasooth:BAABNQAECn8ZAAIGAAoKqB3eEQDgAgAGAAoKqB3eEQDgAgABNQAFFAIIAgAFAAAAAA==.Emboar:BAAANQAECgIIAQAAAA==.Emerey:BAAANQADCggIEwAAAA==.',
En='Endknightt:BAAANQADCggIDgAAAA==.Enflamee:BAAANQADCgUIBQAAAA==.Enma:BAAANQAECgMIAwAAAA==.Ennola:BAAANQADCgYIBwAAAA==.',
Ep='Ephriia:BAAANQAECgYIEgAAAA==.',
Er='Erael:BAAANQAECgEIAQAAAA==.Erikprince:BAAANQAECgUIEgAAAA==.Erso:BAAANQAECgQICAAAAA==.',
Et='Eternalpaín:BAABNQAECn85AAIEAAoKLB+cBQCVAgAEAAoKLB+cBQCVAgAAAA==.',
Ev='Evagria:BAAANQAECgEIAQAAAA==.Evanrude:BAAANQAECgIIAgAAAA==.',
Fa='Fal:BAAANQAECgIIAgAAAA==.Falcyon:BAAANQADCgIIAgAAAA==.Falroot:BAABNQAECn8oAAINAAoKRwwWQwDpAQANAAoKRwwWQwDpAQAAAA==.',
Fe='Felfu:BAAANQAECgEIAQAAAA==.Feliché:BAAANQAECggIEQABNQAECgoKIQAHAPkbAA==.Fevirin:BAAANQAECgcIEQAAAA==.',
Fi='Fiddlesticks:BAABNQAECn8UAAIMAAcKgw0cCwDvAAAMAAcKgw0cCwDvAAAAAA==.Firefawkes:BAAANQAECgQJBQAAAA==.Fistbump:BAABNQAECn8aAAIgAAgKfh6EDgCaAgAgAAgKfh6EDgCaAgAAAA==.',
Fl='Fletchling:BAABNQAECn8fAAMBAAkKESLOJQAAAwABAAgKGyLOJQAAAwAeAAUKcyFaLgDZAQAAAA==.Flizrak:BAAANQADCggIEAABNQAFFAcIFgAWAJ8VAA==.',
Fo='Footsteps:BAAANQADCgcIEQAAAA==.',
Fr='Freefallen:BAAANQAECgIIAgAAAA==.Frostclot:BAABNQAECn8nAAILAAgKXyFvHgC+AgALAAgKXyFvHgC+AgAAAA==.Frostsalad:BAAANQAECgQICQAAAA==.Frozoned:BAAANQAECggIDAABNQAFFAEIAQAFAAAAAA==.',
Fu='Fulta:BAABNQAECn8sAAIeAAkKlRa1AwDVAQAeAAkKlRa1AwDVAQAAAA==.',
['Fø']='Føxhound:BAAANQADCgUIBQAAAA==.',
Ga='Gadoon:BAAANQADCgMIAwAAAA==.Garadin:BAAANQAECgIIAwAAAA==.Garen:BAAANQADCgUIBQAAAA==.Garnok:BAAANQAECggIDAAAAA==.Garwa:BAABNQAECn8rAAMBAAoK1iD8HAAkAwABAAoK1iD8HAAkAwAeAAUKfRQaQgBFAQAAAA==.',
Ge='Geniver:BAAANQAECgQIBgAAAA==.Gerla:BAABNQAECn8jAAIEAAgKkQsVYQADAQAEAAgKkQsVYQADAQAAAA==.',
Gi='Gigas:BAABNQAECn85AAQBAAkKKRjEFQDHAQAeAAgKohKmMADIAQABAAcKahrEFQDHAQACAAUKNBOdCgBmAQAAAA==.Gilgameshh:BAABNQAECn8qAAIEAAgKWhFznADqAQAEAAgKWhFznADqAQAAAA==.Girthbrooks:BAABNQAECn8yAAIVAAoKTxtVCACsAQAVAAoKTxtVCACsAQAAAA==.',
Gl='Glimmerfangs:BAAANQAECgYIDAAAAA==.',
Go='Gomory:BAAANQAECgQICAAAAA==.Gondark:BAAANQAECgMICQAAAA==.Gooseblade:BAAANQAECgEIAQAAAA==.Gorgrim:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCggIFgAAAA==.',
Gr='Grantham:BAAANQABCgQIBAAAAA==.Graverael:BAAANQADCgcICQAAAA==.Gretchen:BAACNQAFFH8GAAIJAAQKagwOBQCeAAAJAAQKagwOBQCeAAA1AAQKfzIAAgkACgr8Hq8VAAwDAAkACgr8Hq8VAAwDAAE1AAUUBQgLAB4AGgwA.Greyley:BAAANQAECgQIBQABNQABCgIIAgAFAAAAAQ==.Greywolf:BAABNQAECn8nAAIPAAkKTxonTQAvAgAPAAkKTxonTQAvAgAAAA==.Gricham:BAAANQADCgUIDgAAAA==.Grimlight:BAAANQAECggIEAABNQAFFAUICQAMAGsHAA==.Grymmhain:BAAANQADCggICAAAAA==.',
Gw='Gwawladin:BAAANQADCgcIBwAAAA==.',
['Gä']='Gärry:BAAANQAECgMIBQAAAA==.',
Ha='Hanzoff:BAAANQAECgEIAwAAAA==.Harmonix:BAAANQAECgcIAgAAAA==.Harrow:BAAANQAECgYIDQAAAA==.Havelock:BAAANQAECgEIAQAAAA==.Havulinnaan:BAAANQAECgYICwAAAA==.Haxx:BAABNQAECn8nAAMVAAoKPA7yGQAJAgAVAAoKhwzyGQAJAgAfAAIKuQxxjwB0AAAAAA==.',
He='Healls:BAAANQADCgUIBQAAAA==.Hearge:BAABNQAECn8eAAMbAAkKGgx4KQCRAQAbAAkKGgx4KQCRAQAIAAIKyAKeFQFLAAAAAA==.Hellhawk:BAABNQAECn8gAAIIAAcKIR3wDwDYAQAIAAcKIR3wDwDYAQAAAA==.Hevydevy:BAABNQAECn8cAAIHAAoKtRelOACGAgAHAAoKtRelOACGAgAAAA==.Hexhain:BAABNQAECn8XAAIXAAgKEQleFgC6AQAXAAgKEQleFgC6AQAAAA==.',
Hi='Hiddenhorde:BAAANQAECgEIAQAAAA==.',
Ho='Hockay:BAABNQAECn8WAAMBAAcKgg3vowC+AQABAAcKgg3vowC+AQAeAAUKTgPdXgCrAAAAAA==.Holygun:BAAANQAECgcIEQAAAA==.Holyliight:BAAANQADCgUIBQAAAA==.Holyshiets:BAAANQADCgUIBQAAAA==.Holyshiza:BAAANQAECgQIDgAAAA==.Holysmokess:BAAANQAECgQIBAAAAA==.Holystan:BAABNQAECn8UAAIEAAcKlgp2YwD+AAAEAAcKlgp2YwD+AAAAAA==.Hondoe:BAAANQAECgUIBwAAAA==.Hookjaw:BAAANQADCgEIAQAAAA==.Hopi:BAAANQABCgQIBAAAAA==.',
Ht='Htownglaivez:BAAANQADCgYIBgABNQAECgUIDAAFAAAAAA==.Htownhots:BAAANQAECgUIDAAAAA==.Htownprot:BAAANQADCgMIAwABNQAECgUIDAAFAAAAAA==.Htownshaman:BAAANQADCgcIDgABNQAECgUIDAAFAAAAAA==.',
Hu='Humblepotato:BAAANQAECgcIBwAAAA==.Hungsten:BAAANQAECgUIBQABNQAFFAUIDQAEAKoTAA==.Huntfromhell:BAABNQAECn8lAAIYAAgK/hpvJgBqAgAYAAgK/hpvJgBqAgAAAA==.',
Ic='Iceagaint:BAAANQADCgQIBQAAAA==.Icedpissfox:BAAANQADCgUJBwAAAA==.',
Id='Idonttank:BAAANQADCggIEgAAAA==.',
Il='Illio:BAAANQAECgUIEQAAAA==.',
Im='Imarea:BAABNQAECn8nAAIWAAkKLASBTgAfAQAWAAkKLASBTgAfAQAAAA==.Impirious:BAABNQAECn8rAAILAAkK8BQoTQDBAQALAAkK8BQoTQDBAQAAAA==.Implumz:BAAANQADCgMIAwABNQAECgkJKwALAPAUAA==.Imptard:BAAANQADCgIIAgABNQAECgkJKwALAPAUAA==.Imtryntotank:BAAANQAECgEIAQAAAA==.Imyx:BAABNQAECn8bAAIhAAYKHxBEIwAVAQAhAAYKHxBEIwAVAQAAAA==.',
In='Incubussy:BAAANQADCgcIBwABNQAECgkJKwAiAKsiAA==.Infamuspikel:BAABNQAECn8gAAIJAAkKchzMIQDAAgAJAAkKchzMIQDAAgAAAA==.Infel:BAAANQAECgcIEAAAAA==.Inkkish:BAABNQAECn8YAAINAAcKwAMKcgACAQANAAcKwAMKcgACAQAAAA==.Innovates:BAABNQAECn80AAIbAAoKfRi9DQC+AgAbAAoKfRi9DQC+AgAAAA==.Interstellar:BAAANQAECgQIBQAAAA==.Intervene:BAAANQADCgYJFAABNQAECgoKOQAEACwfAA==.Invictus:BAABNQAECn8yAAIWAAoKjxDlRgAuAQAWAAoKjxDlRgAuAQAAAA==.',
Is='Isaßeau:BAAANQADCgEIAQAAAA==.Ist:BAAANQAECgUIDAAAAA==.',
Iz='Izuael:BAAANQAECgYJBgAAAA==.',
Ja='Jackjr:BAAANQAECggIDAAAAA==.Jadea:BAAANQADCgUIBQAAAA==.Jahdar:BAAANQABCgQIBAAAAA==.Jalim:BAAANQADCgcIBwAAAA==.Jamesy:BAAANQADCgQJBAABNQAFFAcIDgATAJsbAA==.Jandoar:BAABNQAECn8bAAIWAAYKLgNHdQDTAAAWAAYKLgNHdQDTAAAAAA==.Jarlen:BAAANQADCgEIAQAAAA==.Jasminsparks:BAAANQAECgEIAQAAAA==.Jaylea:BAABNQAECn8sAAIXAAoKUgzzEADzAQAXAAoKUgzzEADzAQAAAA==.Jaynee:BAAANQAECgEIAgAAAA==.',
Je='Jegallidin:BAAANQAECgEIAQAAAA==.Jeohr:BAAANQAECgEIAQAAAA==.Jetpilot:BAABNQAECn8WAAIXAAYKuAawCACUAAAXAAYKuAawCACUAAAAAA==.Jeypi:BAABNQAECn8ZAAMPAAYKYgzdrQAUAQAPAAYKYgzdrQAUAQAZAAEKAAA6OwAgAAAAAA==.',
Ji='Jiq:BAABNQAECn8aAAIKAAcKdAj3OgA9AQAKAAcKdAj3OgA9AQAAAA==.',
Jo='Johli:BAAANQADCggICAAAAA==.Jorlath:BAAANQAECgMIBAABNQAECgQICAAFAAAAAA==.',
Ju='Judikai:BAABNQAECn8bAAIKAAYK5BKRDgA9AQAKAAYK5BKRDgA9AQAAAA==.Junesong:BAABNQAECn8VAAMQAAQKtRQYSwCuAAAQAAQKtRQYSwCuAAAPAAEKoQflJAEoAAAAAA==.Justwipeit:BAAANQADCggICAAAAA==.',
Ka='Kabilos:BAAANQADCggJEAAAAA==.Kaedian:BAABNQAECn8YAAIEAAkKNB65CwAnAgAEAAkKNB65CwAnAgAAAA==.Kalesmora:BAABNQAECn8wAAITAAoKaxL2GgCZAQATAAoKaxL2GgCZAQAAAA==.Kamikaze:BAAANQAECgcIEgAAAA==.Karlov:BAAANQAECgcIDwAAAA==.Karthis:BAAANQADCggIDAAAAA==.Kazera:BAAANQADCgMIBAAAAA==.Kazgrim:BAAANQADCgYICgAAAA==.',
Ke='Keanah:BAABNQAECn8gAAIJAAYK3w3LdgA+AQAJAAYK3w3LdgA+AQAAAA==.Kelrosh:BAAANQABCgQIBAAAAA==.Keynn:BAAANQADCgUIBQABNQAECgkJGAAEADQeAA==.',
Kh='Kheil:BAAANQAECgUIBQAAAA==.Kheims:BAAANQAECgQICAAAAA==.Khrom:BAAANQADCgIIAgAAAA==.Khytoem:BAABNQAECn8eAAIZAAgK5RjeAwDVAQAZAAgK5RjeAwDVAQAAAA==.',
Ki='Killduran:BAAANQAECgUIDAAAAA==.Kimaga:BAAANQADCgUICQABNQADCggIFgAFAAAAAA==.Kindle:BAAANQAECgYIDQAAAA==.Kirasha:BAAANQADCgQIBAAAAA==.Kitom:BAABNQAECn8ZAAMdAAgKDhT/BwAVAgAdAAgK9hL/BwAVAgAcAAYK/w0JuABeAQAAAA==.Kiwia:BAABNQAECn8nAAINAAkKMiKuEQA6AwANAAkKMiKuEQA6AwAAAA==.',
Kl='Klunt:BAAANQADCgEIAQABNQAECgoKKgARAGsVAA==.',
Ko='Kochiyo:BAAANQABCgcIDgAAAA==.Kogä:BAAANQAECggIBAAAAA==.Kolaniber:BAAANQABCgEIAQAAAA==.Korelok:BAAANQAECgEIAQAAAA==.Korkrum:BAABNQAECn8UAAMjAAcKDAupIQA+AQAjAAcKDAupIQA+AQATAAUKrgO1ngBqAAAAAA==.',
Kr='Kracked:BAAANQADCgMIAgAAAA==.Krank:BAAANQADCgUIDAABNQAECgUIDQAFAAAAAA==.Krel:BAAANQADCggICAABNQAECgoKKwAUAKoTAA==.Krellyroll:BAAANQAECgEIAgABNQAECgoKKwAUAKoTAA==.Krelthyr:BAABNQAECn8rAAIUAAoKqhO8AgADAgAUAAoKqhO8AgADAgAAAA==.Krumm:BAABNQAECn81AAIjAAoKmw1ODADqAAAjAAoKmw1ODADqAAAAAA==.Kruul:BAAANQAECgEIAwAAAA==.',
Ku='Kuhne:BAAANQAECgUICAAAAA==.Kungfudrew:BAAANQADCggICAAAAA==.',
Ky='Kyber:BAAANQAECgYIDgAAAA==.Kyther:BAAANQAECgQICgAAAA==.',
['Kñ']='Kñightboat:BAABNQAECn8bAAIkAAYKQBXPBQAqAQAkAAYKQBXPBQAqAQAAAA==.',
La='Ladeiene:BAABNQAECn8XAAILAAcKIw4vZgBaAQALAAcKIw4vZgBaAQAAAA==.Laelwyn:BAAANQAECgQIBgAAAA==.Laelynd:BAAANQADCgYICgAAAA==.Laeritides:BAAANQADCgYICQABNQAECgcIHAALAAcTAA==.Laeritidesdk:BAABNQAECn8cAAILAAcKBxMJHQAMAQALAAcKBxMJHQAMAQAAAA==.Lahrnea:BAAANQADCgYIBgAAAA==.Laraondra:BAAANQAECgMIAwAAAA==.Larix:BAAANQADCgYIBwABNQAECgoKIQAHAPkbAA==.Lastditch:BAAANQAECgMIAwAAAA==.Lateralas:BAAANQADCggJEQAAAA==.Laxxium:BAAANQAECgYIBwAAAA==.',
Le='Leafwarden:BAAANQAECgEIAQAAAA==.Leon:BAABNQAECn8VAAMfAAcKmRLrGAACAQAfAAcK+xHrGAACAQAVAAEKqAZmUgAxAAAAAA==.Leonard:BAAANQAECgcICQAAAA==.Leothedog:BAABNQAECn8iAAMIAAkKQRGuZQDnAQAIAAkKQRGuZQDnAQAEAAIKlwEPigFMAAAAAA==.Lethas:BAAANQADCgMIAwAAAA==.Leukheimsia:BAAANQAECgEIAQABNQAECgQICAAFAAAAAA==.',
Li='Lichgibber:BAAANQAECgEIAQAAAA==.Liere:BAAANQAECgEIAQAAAA==.Lightrising:BAAANQAECgMIBAAAAA==.Lilbean:BAAANQAECgQIBAAAAA==.Lilenalol:BAAANQADCgcIEwAAAA==.Lilfiorella:BAAANQADCgYIDAAAAA==.Lilmonstrman:BAABNQAECn8nAAIWAAkK+BbsdQCSAgAWAAkK+BbsdQCSAgAAAA==.Liltree:BAABNQAECn8dAAIBAAgKQBGGcQAuAgABAAgKQBGGcQAuAgAAAA==.Limbbiscuit:BAABNQAECn8mAAMBAAkKWhiTMQBcAQABAAkKWhiTMQBcAQAeAAQKdgUxYACmAAAAAA==.Listmonk:BAAANQAECgIICgAAAA==.',
Ll='Llothae:BAABNQAECn8cAAIWAAcK4xefNwBOAQAWAAcK4xefNwBOAQAAAA==.',
Lo='Lonjick:BAAANQADCgIIAgAAAA==.Lots:BAAANQADCgcIHgAAAA==.Loyalty:BAAANQAFFAEIAQAAAA==.',
Lu='Lucinsia:BAAANQAECgcICwAAAA==.Lul:BAACNQAFFH8OAAITAAQKmR9DBwAGAQATAAQKmR9DBwAGAQA1AAQKfywAAhMACgrrIZomAB8DABMACgrrIZomAB8DAAAA.Luminar:BAAANQAECgEIAwAAAA==.Lunaaru:BAAANQADCgMIAwAAAA==.Luvrstriplet:BAAANQAECgUICwAAAA==.',
['Lð']='Lðvergirl:BAABNQAECn8YAAINAAcKWAaRZwAuAQANAAcKWAaRZwAuAQAAAA==.',
Ma='Madcow:BAAANQAECgYIEAAAAA==.Maelk:BAAANQADCgQIBQABNQAECgcIFAAjAAwLAA==.Magicdar:BAAANQAECgEIAgAAAA==.Magistella:BAAANQAECgIIAgAAAA==.Maisrii:BAEBNQAECn8aAAIPAAcKgRP3cQC2AQAPAAcKgRP3cQC2AQAAAA==.Maivz:BAABNQAECn8dAAMIAAoKwQ1KPQD0AAAIAAkKiwxKPQD0AAAEAAIKfwQiBwEpAAAAAA==.Malignantt:BAABNQAECn8vAAILAAgKSRLIHwD+AAALAAgKSRLIHwD+AAAAAA==.Maloch:BAAANQADCgIIAgAAAA==.Mapletoast:BAAANQADCgQIBAAAAA==.Marthren:BAAANQADCgUICQAAAA==.Marzyna:BAAANQAECgUIDQAAAA==.Maurphious:BAAANQAECgIIAgAAAA==.',
Me='Mekaniker:BAAANQAECgEIAwAAAA==.Melbee:BAABNQAECn8iAAIMAAkKehKNAwChAQAMAAkKehKNAwChAQAAAA==.Melodrama:BAABNQAECn8UAAMNAAgKvA3hawAbAQANAAYKKAzhawAbAQAOAAUKeQcgTQDYAAAAAA==.Metri:BAAANQABCgUIBwAAAA==.',
Mi='Micassa:BAAANQADCgIIAgAAAA==.Michaeljrdan:BAAANQADCgQIBAAAAA==.Mikela:BAAANQAECgQIEAABNQAECggIGQAWAGQWAA==.Milkee:BAAANQADCgEIAQAAAA==.Mirgaree:BAABNQAECn8rAAIJAAgKVRECDACCAQAJAAgKVRECDACCAQAAAA==.Mirjelys:BAAANQAECgQIBgAAAA==.',
Mo='Moarass:BAABNQAECn8nAAIOAAoKghUUBwDVAQAOAAoKghUUBwDVAQAAAA==.Monty:BAAANQAECgUICQAAAA==.Moodswingz:BAAANQADCgIIAwAAAA==.Moondar:BAAANQAECgEIAgAAAA==.Mordos:BAAANQADCgMIAwAAAA==.Moridane:BAAANQAECgcIDwABNQAECgcIKQAFAAAAAQ==.',
Mu='Much:BAAANQAECgMIAwAAAA==.Muffinz:BAAANQAECgQJCAABNQAECggIGQALAJEaAA==.Mugo:BAAANQAECgcICwABNQAECgoKIQAHAPkbAA==.Multiabuse:BAAANQAECgMIBgAAAA==.Multipass:BAAANQAECgEIBAAAAA==.',
My='Myau:BAABNQAECn8dAAMGAAgK8xTEHgBIAgAGAAgK8xTEHgBIAgAHAAMKHwdebgCKAAAAAA==.Mylou:BAAANQAECgYIEwAAAA==.Mynia:BAABNQAECn81AAICAAoKLQgJBAAvAQACAAoKLQgJBAAvAQAAAA==.',
Na='Nano:BAABNQAECn8rAAMcAAgKdhx+GACQAQAcAAgKdhx+GACQAQAXAAIKxA1qXQBrAAAAAA==.Nayroon:BAEANQADCggIGAABNQAECgoKIwABADUgAA==.Nazdreg:BAABNQAECn8YAAMXAAYKeBFKNgDoAAAcAAYKqg5AxgA+AQAXAAQKjg5KNgDoAAAAAA==.',
Ne='Negan:BAAANQABCgUIBQAAAA==.Neotoldir:BAABNQAECn8qAAIhAAgKEBOsOADyAQAhAAgKEBOsOADyAQAAAA==.Nerfdisc:BAAANQAECgUICQAAAA==.Nevershocked:BAABNQAECn8cAAIlAAcK/hcYCgDTAQAlAAcK/hcYCgDTAQAAAA==.Nezziee:BAAANQAECgMIAgAAAA==.',
Ni='Niitefall:BAAANQAECggICgABNQADCgUIBQAFAAAAAA==.Ninjaznpariz:BAAANQADCgQJBAAAAA==.',
No='Noblewrack:BAAANQADCgEIAQAAAA==.Noobles:BAAANQAECgQIBgAAAA==.Nordie:BAAANQADCggICAAAAA==.Northik:BAAANQAECgcIDAAAAA==.Nosredna:BAAANQAECgMIBAAAAA==.Nosrednàx:BAAANQADCgUIBQAAAA==.Notintheface:BAAANQAECgIIAgAAAA==.Novata:BAAANQADCgUIBQABNQAECgIIAgAFAAAAAA==.',
Nu='Nuzz:BAACNQAFFH8SAAITAAcKWiMPBwBPAgATAAcKWiMPBwBPAgA1AAQKfyMAAhMACgrmJYIaAE4DABMACgrmJYIaAE4DAAAA.',
Ny='Nydav:BAABNQAECn8VAAIKAAYK1h9bIgAWAgAKAAYK1h9bIgAWAgABNQAECgkJGAAEADQeAA==.Nyphithys:BAAANQAECgIIAgAAAA==.',
['Ní']='Níítefall:BAAANQAECggICAABNQADCgUIBQAFAAAAAA==.',
Ob='Obalma:BAABNQAECn8iAAMMAAoKYhxHCQC1AgAMAAkKBRpHCQC1AgAmAAYKHRvwDgAbAQAAAA==.',
Od='Odwalla:BAABNQAECn8cAAIBAAkKECKgGQAzAwABAAkKECKgGQAzAwAAAA==.',
Ol='Oleehammer:BAAANQAECggIAgAAAA==.Oleweaver:BAAANQAECggIAgAAAA==.Olmec:BAABNQAECn8aAAIQAAYK7xWZNADuAAAQAAYK7xWZNADuAAAAAA==.Olmek:BAAANQAECgIIAwAAAA==.',
On='Onlydesert:BAABNQAECn8ZAAMWAAgKZBaOvwAFAgAWAAgKZBaOvwAFAgASAAEKKhGEDAA+AAAAAA==.Onranui:BAAANQADCgcIDQAAAA==.',
Oo='Oopsyourdead:BAAANQAECgUIDAAAAA==.',
Op='Optiks:BAABNQAECn8kAAMDAAcK7BxuBQBOAQAWAAcKtBoYtwAVAgADAAUKhhxuBQBOAQAAAA==.',
Or='Orcfan:BAAANQABCgIJAgAAAA==.Orksauce:BAABNQAECn9BAAMVAAoKVyLEAAAOAwAVAAoKVyLEAAAOAwAfAAMKYCGGbwDzAAAAAA==.Orphella:BAAANQAECgEIAQAAAA==.',
Os='Osares:BAABNQAECn8hAAIEAAgKHAuKRQA6AQAEAAgKHAuKRQA6AQAAAA==.Osong:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.',
Ou='Outtamanna:BAAANQADCgUICQAAAA==.',
Ow='Owils:BAAANQADCgYIBgABNQAECgoKNQAJADcZAA==.',
Ox='Oxl:BAAANQAECgEIAgAAAA==.',
['Oß']='Oß:BAAANQAECgEIAgABNQAECgQICgAFAAAAAA==.',
Pa='Pacel:BAAANQAECgEIAQAAAA==.Pagophobia:BAAANQAECgMIAwAAAA==.Pallytree:BAAANQAECgIIBgAAAA==.Papiblanco:BAAANQADCggICgAAAA==.Pariahdruid:BAABNQAECn8VAAImAAgKNhz6DgB0AgAmAAgKNhz6DgB0AgAAAA==.',
Pe='Percepcions:BAAANQAECgYIEAAAAA==.Percksmash:BAABNQAECn8XAAITAAcK/hujlQDmAQATAAcK/hujlQDmAQAAAA==.Perkbane:BAAANQAECggIBwABNQAECggIFwATAP4bAA==.Perkyl:BAAANQAECgYIEQAAAA==.',
Ph='Phage:BAAANQAECgYICAABNQAECgoKKgARAGsVAA==.Philon:BAAANQAECgcIBwABNQAECggIGQALAJEaAA==.Photophobia:BAABNQAECn8aAAIGAAkKch6QFQCzAgAGAAkKch6QFQCzAgAAAA==.',
Pi='Piezo:BAAANQADCgQIBgAAAA==.Pikevarr:BAAANQAECgEIAQAAAA==.Pivy:BAAANQADCgYIBgABNQAECggIGgAgAH4eAA==.',
Pk='Pkfurrie:BAAANQABCgIIAQAAAA==.Pkrage:BAABNQAECn82AAMjAAoKUR5QAgDrAQAjAAoKUR5QAgDrAQATAAMK+QxjFQGxAAAAAA==.',
Pl='Plaugez:BAAANQAECgEIAQAAAA==.Plazlie:BAABNQAECn8rAAMnAAoKoiOaAQCDAwAnAAoK3yKaAQCDAwATAAEKciI6pABiAAAAAA==.Plopp:BAEANQAECggIEAAAAA==.Ploppstein:BAEANQAECgYIEwABNQAECggIEAAFAAAAAA==.',
Po='Polyethylene:BAABNQAECn8hAAIPAAgK9gZrSgDMAAAPAAgK9gZrSgDMAAAAAA==.Poucastranca:BAABNQAECn8pAAMXAAgKtyTjPQDKAAAXAAMKuSTjPQDKAAAcAAcKRiSjJwFwAAAAAA==.',
Pu='Punkpikachu:BAAANQAECgIIAwAAAA==.',
Pw='Pwnman:BAAANQADCgUIBQAAAA==.',
Py='Pyrrhic:BAAANQAECgEIAQAAAA==.',
Qk='Qkoira:BAAANQAECgQIDQAAAA==.',
Qu='Quanlain:BAABNQAECn8YAAIBAAcKqh/+GQCxAQABAAcKqh/+GQCxAQAAAA==.Quillathe:BAABNQAECn8xAAMHAAoKEhuPDAAeAgAHAAoKEhuPDAAeAgAiAAYKHAlPEQASAQAAAA==.',
Ra='Raagh:BAAANQAECgQIBAAAAA==.Rabblle:BAAANQADCggIDgAAAA==.Rancore:BAABNQAECn8YAAInAAcK9hdKAgDBAQAnAAcK9hdKAgDBAQAAAA==.Rashdar:BAABNQAECn8qAAIEAAoKFBvGWACNAgAEAAoKFBvGWACNAgAAAA==.Rasto:BAAANQADCgYICQABNQAECgQJCgAFAAAAAA==.Rattpacck:BAAANQAECgEIAQAAAA==.Rattpack:BAAANQAECgQIDAAAAA==.Raves:BAABNQAECn8ZAAIWAAcKlxDRWAALAQAWAAcKlxDRWAALAQAAAA==.Rayvynn:BAAANQADCgIIBAAAAA==.',
Re='Regilz:BAAANQADCgMIAwAAAA==.',
Rh='Rhys:BAAANQAECgMIAwAAAA==.',
Ri='Ribeyye:BAAANQAECgcIDwAAAA==.Rider:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Rigormortiis:BAAANQAECgEIAQAAAA==.Rilde:BAAANQAECgMIAwAAAA==.Rinjiabri:BAAANQAECgIIAwAAAA==.Rinjipally:BAAANQAECgYIEQAAAA==.',
Ro='Robroy:BAABNQAECn8WAAMcAAcKABPMqwB7AQAcAAcKVQ/MqwB7AQAXAAEK/hPVbwBAAAAAAA==.Robrøy:BAAANQADCggJGQAAAA==.Rokmage:BAAANQAECgMIBQAAAA==.Roniecoleman:BAAANQAECgEIAgAAAA==.Roseclaw:BAEANQAECgUICwABNQAECgoKIwABADUgAA==.Roseclawed:BAEBNQAECn8jAAIBAAoKNSD8KwDqAgABAAoKNSD8KwDqAgAAAA==.Roxso:BAACNQAFFH8WAAMWAAcKnxWVEwDbAQAWAAYKJxWVEwDbAQADAAEKfRfZDABZAAA1AAQKf0IAAxYACgokI1omAEcDABYACgokI1omAEcDAAMABwqhGnYHAB4BAAAA.',
Ru='Rukaiz:BAABNQAECn8gAAITAAgKBxg8PwAlAQATAAgKBxg8PwAlAQAAAA==.',
Ry='Rylen:BAAANQADCgYIBgAAAA==.Rylun:BAAANQAECgEIAQAAAA==.',
['Rë']='Rëdmagma:BAABNQAECn8eAAIQAAcKqBtqYAAAAgAQAAcKqBtqYAAAAgAAAA==.',
['Rò']='Ròbroy:BAAANQAECggJCQAAAA==.',
['Ró']='Rónan:BAAANQAECgcIDAAAAA==.',
['Rû']='Rûsh:BAAANQADCggJEAAAAA==.',
['Rü']='Rüin:BAAANQAECgEIAQAAAA==.',
Sa='Sacrelicious:BAABNQAECn8VAAIEAAYKaAWjGAH2AAAEAAYKaAWjGAH2AAAAAA==.Saennah:BAAANQADCgIJAgAAAA==.Sagewynn:BAAANQAECggIEAAAAA==.Sainei:BAAANQADCgUIBQABNQAECggIHAATAP8bAA==.Salfroc:BAABNQAECn80AAIdAAoKeBW3AgBNAQAdAAoKeBW3AgBNAQAAAA==.Samhain:BAABNQAECn8nAAIaAAkK0RJoLADeAQAaAAkK0RJoLADeAQAAAA==.Sanasianana:BAAANQADCgUIBQABNQAFFAEIAQAFAAAAAA==.Saplo:BAABNQAECn8WAAIBAAcK6AcKSgAfAQABAAcK6AcKSgAfAQAAAA==.Sapphirosa:BAAANQAECgEIAQABNQAECgoKLQAKAEEZAA==.Sarif:BAAANQAECgQIDAAAAA==.Saxel:BAAANQAECgEIAQAAAA==.',
Sc='Scallop:BAAANQADCgQIBAAAAA==.Schwarzenman:BAAANQADCgEIAQAAAA==.',
Se='Segio:BAAANQAECgEIAQAAAA==.Selcia:BAAANQADCggJEAAAAA==.Serenati:BAAANQAECgUIEAAAAA==.Seïya:BAAANQADCggIKAAAAA==.',
Sg='Sgthulka:BAAANQADCgQJBAAAAA==.',
Sh='Shadesmar:BAAANQAECgcIAgAAAA==.Shamawockee:BAABNQAECn8gAAIZAAkK3w3xBgCHAQAZAAkK3w3xBgCHAQABNQAECgoKPgABAMsgAA==.Shango:BAAANQADCgUIBQAAAA==.Sharavia:BAABNQAECn8jAAIYAAgKMwnMGgAeAQAYAAgKMwnMGgAeAQAAAA==.Shasu:BAAANQADCgEIAQAAAA==.Shaundi:BAAANQAECgUICgAAAA==.Shautistic:BAAANQAECgcIDQAAAA==.Shocktuah:BAABNQAECn81AAIQAAoKPSMmFABRAwAQAAoKPSMmFABRAwAAAA==.Shonúff:BAABNQAECn8mAAIKAAkKwhPQIgASAgAKAAkKwhPQIgASAgAAAA==.Shotaru:BAAANQAECgUIDgAAAA==.Shotpace:BAAANQAECgQICAAAAA==.Showerhandle:BAAANQADCgMIAwAAAA==.Shui:BAAANQAECgEIAwABNQAECgYIDQAFAAAAAA==.Shädöw:BAAANQAECgEIAQAAAA==.',
Si='Siddhartha:BAAANQAECgEIAQAAAA==.Silmeria:BAABNQAECn8YAAIgAAkKyRpeEAB5AgAgAAkKyRpeEAB5AgAAAA==.Sinful:BAABNQAECn84AAMnAAkK1A9ICwAPAgAnAAkK1A9ICwAPAgATAAIKIQiuRAFIAAAAAA==.',
Sk='Skalagrim:BAAANQADCggIDwAAAA==.Skeptix:BAAANQAECgUIAgAAAA==.Skeptyk:BAABNQAECn8qAAIHAAgKISF4IQDpAgAHAAgKISF4IQDpAgAAAA==.Sko:BAEBNQAECn8qAAMIAAoKNBjBKwC4AgAIAAoKNBjBKwC4AgAEAAcKZAzBiQC+AAABNQAECgEIAgAFAAAAAA==.Skol:BAABNQAECn8TAAMhAAgKvw3zcQDXAAAhAAQKSRDzcQDXAAALAAUK/AnojwDFAAAAAA==.Skolivermist:BAEANQAECgEIAQABNQAECgEIAgAFAAAAAA==.Skolivia:BAEANQAECgEIAgAAAA==.',
Sm='Smiley:BAAANQAECgMIAwAAAA==.Smitti:BAAANQAECgQIBQABNQAECggIGQAWAGQWAA==.Smokeydabear:BAAANQADCgEIAQAAAA==.Smug:BAABNQAECn8jAAMaAAkK8CSNCQA/AwAaAAkK4SSNCQA/AwAYAAYK+SLPKABZAgAAAA==.',
Sn='Snapee:BAAANQAECgUICwAAAA==.Sniffledoo:BAABNQAECn8fAAIjAAcKxhBHGwCFAQAjAAcKxhBHGwCFAQAAAA==.Snol:BAAANQAECgUIBQAAAA==.Snuwuf:BAAANQADCgcIFgAAAA==.',
So='Sockz:BAABNQAECn8WAAMPAAgKZQqTTQDFAAAPAAgKZQqTTQDFAAAQAAIKowdDGAFeAAAAAA==.Soonmia:BAAANQAECgEIAwAAAA==.Sourfangs:BAABNQAECn8iAAMTAAoKmR5AOgDdAgATAAoKmR5AOgDdAgAnAAEKAAD6KQBhAAAAAA==.',
Sp='Spicypeño:BAABNQAECn8iAAIRAAkKwCAUBgArAwARAAkKwCAUBgArAwABNQAFFAgIIAARAH8dAA==.Spicý:BAACNQAFFH8GAAIWAAMK7BnLFgCmAAAWAAMK7BnLFgCmAAA1AAQKfyEAAhYACgqQInw1AB8DABYACgqQInw1AB8DAAAA.Splack:BAABNQAECn8+AAIBAAoKyyCGAgDTAgABAAoKyyCGAgDTAgAAAA==.Splithoofe:BAEANQADCgUICwABNQAECgUIEAAFAAAAAA==.Sprawl:BAABNQAECn8mAAIoAAkKpg/eCQDmAQAoAAkKpg/eCQDmAQAAAA==.Sprawlher:BAABNQAECn8aAAIeAAcKqA1COgB+AQAeAAcKqA1COgB+AQABNQAECgkJJgAoAKYPAA==.',
Sq='Squrrlydan:BAEANQAECgQJBQAAAA==.',
St='Stabzuplenty:BAAANQAECgIIAgABNQAFFAcIFgAWAJ8VAA==.Stains:BAAANQADCgQIBAABNQAECgoKKgARAGsVAA==.Staint:BAABNQAECn8qAAIRAAoKaxWRAwB0AQARAAoKaxWRAwB0AQAAAA==.Staints:BAAANQAECgMIBQABNQAECgoKKgARAGsVAA==.Starnights:BAAANQAECgcIDwAAAA==.Statman:BAABNQAECn8cAAIjAAcK8gZfEQCuAAAjAAcK8gZfEQCuAAAAAA==.Steelbubble:BAABNQAECn8ZAAMTAAkKxRz2XgBwAgATAAkKFBz2XgBwAgAnAAMKAiHuGwDqAAAAAA==.Stella:BAAANQAECgYIDAAAAA==.Stengah:BAABNQAECn8xAAIUAAoK8x5wAgAYAgAUAAoK8x5wAgAYAgAAAA==.Stonebrew:BAAANQABCgEIAQAAAA==.Strela:BAAANQAFFAIIBAAAAQ==.',
Su='Supershenron:BAAANQADCgEIAQAAAA==.Suraki:BAABNQAECn84AAIYAAoKfBaSBAAfAgAYAAoKfBaSBAAfAgAAAA==.',
Sv='Svetlian:BAAANQAECgUIBwABNQAFFAIIBAAFAAAAAA==.',
Sw='Swtblsphmy:BAABNQAECn8YAAMPAAcK+xuDDwDeAQAPAAcK+xuDDwDeAQAQAAEKAADeWAEgAAAAAA==.',
Sy='Sylverwolf:BAAANQADCgEIAQAAAA==.Sylvestrus:BAAANQAECgcIEQABNQAECgoKIQAHAPkbAA==.',
['Sä']='Säber:BAAANQADCgcIBwAAAA==.',
['Sè']='Sèd:BAACNQAFFH8GAAIHAAIKqA/TFQB3AAAHAAIKqA/TFQB3AAA1AAQKfzYAAgcACQpbHJQdAPsCAAcACQpbHJQdAPsCAAAA.Sèitheach:BAAANQAECgQIBgAAAA==.',
['Sí']='Síd:BAABNQAECn8kAAMdAAkKVBDeBQBaAgAdAAkKhA/eBQBaAgAcAAkKNwoEiQDQAQAAAA==.',
Ta='Tahrin:BAABNQAECn8lAAIBAAkKDR4pJwD7AgABAAkKDR4pJwD7AgAAAA==.Talamon:BAABNQAECn8sAAIpAAgKMxVpDgAOAgApAAgKMxVpDgAOAgAAAA==.Tamerlynn:BAAANQADCgUIBAAAAA==.Tandruid:BAABNQAECn8mAAINAAkKox3HIwCyAgANAAkKox3HIwCyAgAAAA==.Tanize:BAAANQADCggICAAAAA==.Taproot:BAAANQAECgYIAQAAAA==.Tarasis:BAAANQADCgEIAQAAAA==.Tashi:BAABNQAECn8cAAMBAAgKLw7powC+AQABAAgKLw7powC+AQAeAAUKuAL0XgCqAAAAAA==.Tasina:BAAANQADCgUIBgAAAA==.Taurenamos:BAABNQAECn9HAAMNAAkK1RSuNABDAgANAAgKHhWuNABDAgAOAAgKVhiDJAAAAgAAAA==.Taynam:BAAANQAECgQICQABNQAECgcIFAAfACkkAA==.',
Te='Tempëst:BAAANQAECgIJAgAAAA==.Tenchu:BAABNQAECn8eAAMaAAcKCBJ+EwATAQAYAAcKARIgQgCwAQAaAAcKTQx+EwATAQAAAA==.Tendra:BAAANQADCgMIAwAAAA==.Tenseven:BAAANQAECgYIEAAAAA==.Terrørßlade:BAAANQAECgEIAQABNQAECgcIGgAZAKcKAA==.',
Th='Thalorain:BAAANQAECgUIBQABNQAECgcIFAAjAAwLAA==.Thark:BAABNQAECn8UAAIEAAoKTiNNDgCUAwAEAAoKTiNNDgCUAwABNQAECgoKNQAZACklAA==.Thatdruid:BAAANQAECgEIAwAAAA==.Thicknfluffy:BAAANQAECgEIAQAAAA==.Throwd:BAABNQAECn8tAAIVAAoKWxAiFQAxAQAVAAoKWxAiFQAxAQAAAA==.Thundah:BAAANQAECgIIBAAAAA==.Thurk:BAABNQAECn81AAMZAAoKKSV5AADhAwAZAAoKjyR5AADhAwAQAAgKVSXbEgBaAwAAAA==.',
Ti='Tideshunter:BAACNQAFFH8LAAMBAAUKKQ1dCADjAAABAAUK/gxdCADjAAAeAAIKJAT9HwBxAAA1AAQKfyMAAwEACgo3HCcvAN8CAAEACgo0HCcvAN8CAB4ACApGE2kwAMoBAAAA.Tinytony:BAABNQAECn8qAAMbAAoKsho4DwCqAgAbAAoKsho4DwCqAgAEAAIKdQolcgFrAAAAAA==.Tinyweakling:BAAANQAECgIIBAABNQAECgkJHwABABEiAA==.Tinyyzebra:BAAANQADCgcIBwAAAA==.',
To='Tookahxd:BAAANQAECgIIBQAAAA==.Toranis:BAAANQAECgEIAgAAAA==.Torrellan:BAAANQAECgEIAQAAAA==.Torrents:BAABNQAECn8uAAMPAAoKoCSfEQA6AwAPAAoKoCSfEQA6AwAQAAYK3wvUxgAFAQAAAA==.Totemdroppa:BAAANQAECgQICAABNQAECggIGQALAJEaAA==.Totemik:BAAANQAECgEIAQAAAA==.Touchofchaos:BAAANQADCggICAAAAA==.',
Tr='Trailerpark:BAAANQAECggICwAAAA==.Triepas:BAAANQAECgUICQAAAA==.Trillest:BAAANQAECgcIDwAAAA==.Trinytee:BAABNQAECn8YAAIBAAcKQxcMkADpAQABAAcKQxcMkADpAQAAAA==.Trippytotem:BAABNQAECn8rAAMQAAoK+g+hewCwAQAQAAgKtw+hewCwAQAPAAgKWAXypwAiAQAAAA==.Trolltoll:BAAANQADCgEIAQAAAA==.Trollypolly:BAAANQABCgMIAQAAAA==.',
Ty='Tyriäel:BAABNQAECn8lAAMLAAoKMCJvGwDUAgALAAoK1h1vGwDUAgAJAAcK9iIEIwC5AgAAAA==.Tyrrible:BAAANQAECggIAQAAAA==.',
['Tà']='Tàyla:BAAANQADCgQIBAABNQAECgcIGAABAEMXAA==.',
Ug='Ugolino:BAAANQADCgEIAQAAAA==.',
Ul='Ulmec:BAAANQAECgMIAwAAAA==.Ulther:BAAANQADCggJEAAAAA==.',
Ut='Uthookem:BAAANQAECgMIBAAAAA==.',
Va='Vacare:BAAANQADCggJEAAAAA==.Valdyria:BAAANQAECgEIAQAAAA==.Valistar:BAAANQAECgQIDwAAAA==.Valkoienne:BAAANQADCgYIDQAAAA==.Varnashar:BAAANQAECgUIBwAAAA==.Vavictus:BAAANQADCggJEAAAAA==.Vazaenei:BAAANQABCgMIAwAAAA==.',
Ve='Vedronorael:BAAANQADCgcJBgAAAA==.Veinos:BAAANQAECggIEwAAAQ==.Velanthia:BAAANQADCgcIBwAAAA==.Velora:BAAANQAECgIIBAAAAA==.Vengrath:BAABNQAECn8hAAMWAAoKzB2RZgCxAgAWAAoKzB2RZgCxAgADAAEK2hcaQABEAAAAAA==.Verderben:BAAANQAECgUIEAAAAA==.Verind:BAAANQAFFAEIAQAAAA==.',
Vi='Vinhelsin:BAAANQAECgEIAQAAAA==.',
Vo='Voideater:BAAANQADCgEIAQAAAA==.Voron:BAABNQAECn8tAAIEAAcKeRXPrwC/AQAEAAcKeRXPrwC/AQAAAA==.',
Vu='Vulperra:BAABNQAECn8pAAITAAoKqhJ4OAA3AQATAAoKqhJ4OAA3AQAAAA==.',
Vy='Vynessa:BAAANQAECgIIAgAAAA==.',
Wa='Walk:BAAANQADCgYIBgAAAA==.Waq:BAABNQAECn8kAAQdAAkKJhYLBwAzAgAdAAgK3xYLBwAzAgAcAAYKvgtYwQBJAQAXAAUKIxS9LAAbAQAAAA==.Waterwhip:BAABNQAECn8VAAIPAAgKzBneXAD5AQAPAAgKzBneXAD5AQAAAA==.',
We='Wemeo:BAAANQAECgUIEQAAAA==.Westfall:BAABNQAECn8mAAMLAAkKcB5uHgC+AgALAAkKcB5uHgC+AgAJAAIKKAJA2AA+AAAAAA==.',
Wi='Willowweewoo:BAAANQAECggIEgAAAA==.Willrun:BAABNQAECn8VAAMNAAcKIQcobQAWAQANAAcKIQcobQAWAQAMAAEKAAB5SwAjAAAAAA==.Wipeit:BAAANQADCgIIAgAAAA==.Witheredyam:BAAANQAECgIIAgAAAA==.',
Wo='Wolfbayne:BAAANQAECgUIBwAAAA==.Wompeal:BAABNQAECn8kAAMHAAcKvx9JCABkAgAHAAcKvx9JCABkAgAiAAEKIBLAJwA3AAABNQAECggIHQABAPMUAA==.Wonkwonk:BAABNQAECn8lAAMDAAcKHwv6FABcAQADAAcKHwv6FABcAQASAAEKfwEtEAATAAAAAA==.Worth:BAABNQAECn82AAIEAAoKbSILDwCQAwAEAAoKbSILDwCQAwAAAA==.',
Wr='Wrukolas:BAABNQAECn8gAAIcAAoKrQiFVwDTAAAcAAoKrQiFVwDTAAAAAA==.',
Wy='Wystan:BAABNQAECn8nAAIPAAoKch/UKgC4AgAPAAoKch/UKgC4AgAAAA==.',
['Wè']='Wès:BAAANQADCgEIAQAAAA==.',
['Wé']='Wés:BAABNQAECn8tAAMpAAoK9hcUBABVAQApAAoK9hcUBABVAQAgAAMK5AuzPgCBAAAAAA==.',
Xa='Xamsuciteey:BAAANQADCgUIBQAAAA==.Xandritten:BAAANQABCgIIAgAAAA==.Xanthe:BAABNQAECn8jAAMIAAgKXBV1FwCbAQAIAAgKXBV1FwCbAQAEAAEKkQF80wEcAAAAAA==.Xavin:BAAANQADCgcICQAAAA==.',
Xe='Xentow:BAABNQAECn8vAAIBAAgKvQdrXQDxAAABAAgKvQdrXQDxAAAAAA==.',
Xi='Xirin:BAAANQAECgEIAgABNQAECgEIAgAFAAAAAA==.',
Ya='Yamling:BAAANQADCggIHgAAAA==.Yayaka:BAAANQADCgcIEgAAAA==.Yazzik:BAAANQADCggICAABNQAECgoKKwAUAKoTAA==.',
Yi='Yizdano:BAACNQAFFH8IAAMVAAMK7BJaDQDHAAAVAAMKRw1aDQDHAAAfAAIKMwipGACJAAA1AAQKfzMAAx8ACgrYGz0RADsBABUACgq4DEscAPIBAB8ACQoiGz0RADsBAAAA.',
Yu='Yukiina:BAAANQADCggIFQAAAA==.Yungbean:BAAANQAECgQICAAAAA==.',
['Yû']='Yûm:BAAANQADCggICgAAAA==.',
Za='Zaccheus:BAAANQAECgcIEAABNQAECgoKIQAHAPkbAA==.Zambora:BAAANQADCgcICgAAAA==.Zamwi:BAAANQAECgYIEgAAAA==.Zavrix:BAAANQAECggIAgAAAA==.',
Ze='Zeebra:BAABNQAECn8XAAIWAAcKDgos8gCnAQAWAAcKDgos8gCnAQAAAA==.Zeesaw:BAABNQAECn8kAAMTAAgKdBlOJABzAQATAAgKdBlOJABzAQAnAAIKRxgoJQCHAAAAAA==.Zenden:BAAANQAECgQIBgAAAA==.Zerebrand:BAAANQAECgIIAgABNQAECgoKKwAWABMeAA==.Zeretrix:BAABNQAECn8rAAMWAAoKEx5+NAAhAwAWAAoKEx5+NAAhAwADAAQK0AvXJgC8AAAAAA==.Zerospace:BAABNQAECn8dAAIEAAgKiwvjxgCOAQAEAAgKiwvjxgCOAQAAAA==.',
Zi='Ziros:BAAANQAECggICQAAAA==.',
Zl='Zlutar:BAAANQAECgQIDAAAAA==.',
Zy='Zylor:BAAANQAECgEIAQAAAA==.Zynos:BAABNQAECn8oAAIYAAoKpBFTGgAiAQAYAAoKpBFTGgAiAQAAAA==.Zynothrian:BAAANQADCgMIAwAAAA==.Zyraethiel:BAAANQAFFAEIAgAAAA==.',
['Ça']='Çalindrel:BAAANQADCgUIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQADCgYICwAAAA==.',
['Úà']='Úà:BAAANQADCgIIAQABNQAECgQIDQAFAAAAAA==.',
['Üb']='Überhealz:BAABNQAECn8hAAMHAAoK+RsGRABcAgAHAAoK+RsGRABcAgAGAAMKXAnKWwCXAAAAAA==.',
['ßö']='ßöw:BAABNQAECn81AAIBAAoKbR8xKAD3AgABAAoKbR8xKAD3AgAAAA==.',
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
