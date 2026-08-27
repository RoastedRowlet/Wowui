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

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Druid-Feral','Monk-Windwalker','Priest-Holy','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Evoker-Augmentation','Monk-Mistweaver','Paladin-Holy','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Druid-Balance','Rogue-Assassination','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-08-25',data={Ac='Achak:BAAALgAECgEJAQAAAA==.',
Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAACLgAFFH8KAAIBAAMJcxu6DQDRAAABAAMJcxu6DQDRAAAuAAQKf1UABAEACQmYI6wCADcDAAEACQmYI6wCADcDAAIACAmHGVIEAAACAAMAAQlCCGk6ACEAAAAA.Adelethe:BAAALgAECgEJAQAAAA==.Adóra:BAAALgAECgQJCAAAAA==.',
Ae='Aeonis:BAABLgAECn8YAAMEAAUJRRFRCwCrAAAEAAQJhxRRCwCrAAAFAAEJfgcmdQAeAAAAAA==.Aestian:BAABLgAECn84AAIEAAkJ5Rn9DAD1AQAEAAkJ5Rn9DAD1AQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgAECgEJAQABLgAECgUJGAAEAEURAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAABLgAECn8aAAMGAAYJKAdWJACQAAAGAAYJKAdWJACQAAAHAAMJqwDGYwEdAAABLgAECgcJJAAIAIcRAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Aldamojo:BAAALgADCgEJAQAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIHAAkJMguKWwCLAQAHAAkJMguKWwCLAQAAAA==.Aletheia:BAAALgAECgEJAQAAAA==.Alfurn:BAAALgADCgQJBQAAAA==.Aliveknightt:BAAALgAECgEJAQAAAA==.Allanquatre:BAAALgAECgYJBgAAAA==.Alledria:BAACLgAFFH8GAAIFAAQJRQb0dADKAAAFAAQJRQb0dADKAAAuAAQKfxoAAgUACAmaElB5AHwBAAUACAmaElB5AHwBAAAA.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAACLgAFFH8FAAMJAAIJSwgjHQBrAAAJAAIJSwgjHQBrAAAKAAEJxQNZNgAqAAAuAAQKfygAAwoACQlvF5oGAJ4BAAoACQlvF5oGAJ4BAAkACAnQDQUxAFkBAAAA.Altonas:BAAALgAECgMJBAAAAA==.',
Am='Amanara:BAAALgAECgcJEgAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.Amoonia:BAAALgADCgkJEQAAAA==.',
An='Ancientmonk:BAAALgAECgEJAQABLgAECgYJCQALAAAAAA==.Anciientpaw:BAABLgAECn8iAAMMAAkJGyBlHQAvAgAMAAkJGyBlHQAvAgANAAUJbBUZWwDTAAAAAA==.Andramalyus:BAABLgAECn8pAAIHAAgJ3AwtcABaAQAHAAgJ3AwtcABaAQAAAA==.Andrasomnius:BAABLgAECn8bAAIOAAgJRAgwBQD3AAAOAAgJRAgwBQD3AAAAAA==.Angbar:BAABLgAECn8xAAIOAAkJkBYvCQBXAgAOAAkJkBYvCQBXAgAAAA==.Anguirus:BAACLgAFFH8GAAINAAMJjwHgLgBWAAANAAMJjwHgLgBWAAAuAAQKfzwAAw0ACQl8BdVOAPsAAA0ACQlbBdVOAPsAAA8ABgkCA34tAI0AAAAA.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJCAABLgAECgcJDwALAAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.Anuksunàmun:BAAALgAECgkJDQAAAA==.',
Ao='Aoman:BAAALgAECgQJBAAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAFFAMJDQAQABsFAA==.Appynoxusrog:BAABLgAECn8cAAIRAAYJuhguBQCcAQARAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAISAAMJsRNqngDWAAASAAMJsRNqngDWAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAACLgAFFH8NAAITAAMJ5hDKGwDJAAATAAMJ5hDKGwDJAAAuAAQKfzQAAxMACQknHZwQAHMCABMACQknHZwQAHMCABQAAQnMB9REAC8AAAAA.Arcadiann:BAABLgAECn8aAAITAAgJ6xgyLQCdAQATAAgJ6xgyLQCdAQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arceeprime:BAAALgAECgcJDgAAAA==.Arcoyflecha:BAAALgAECggJEwAAAA==.Arextheelder:BAABLgAECn8YAAIGAAgJVg+9BAAkAQAGAAgJVg+9BAAkAQAAAA==.Aridas:BAABLgAECn8dAAMCAAgJJBhuMwAsAgACAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAAUAAcaAA==.Arikdeath:BAACLgAFFH8JAAIIAAMJeAzrOQDEAAAIAAMJeAzrOQDEAAAuAAQKfykAAwgACQmVFwotACgCAAgABwlvGAotACgCABUABwlODN0VAAoBAAAA.Arkros:BAAALgADCgYJBgAAAA==.Armorscales:BAACLgAFFH8gAAIHAAgJKBlGEQC3AQAHAAgJKBlGEQC3AQAuAAQKfy4AAgcACQn4IVgQAPcCAAcACQn4IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQALAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQALAAAAAA==.Arnixx:BAAALgAECgQJDQAAAA==.Arntraz:BAAALgADCgkJVgAAAA==.Aryel:BAAALgAECgQJBAAAAA==.Arçadia:BAAALgAECgMJCAAAAA==.',
As='Ashcaller:BAAALgAECgIJBAAAAA==.Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Asprika:BAABLgAFFH8OAAIJAAUJrhDVDgAEAQAJAAUJrhDVDgAEAQAAAA==.Astayoni:BAAALgAECgEJAQAAAA==.Astrine:BAACLgAFFH8VAAMWAAcJxhShPgBzAQAWAAYJyBahPgBzAQAXAAEJvApNBwBFAAAuAAQKfysAAhYACQlJIAYiAOsCABYACQlJIAYiAOsCAAAA.',
At='Ataraxya:BAAALgAECgEJAQAAAA==.',
Au='Auberon:BAABLgAECn8oAAIYAAkJ/xl6BgCSAgAYAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8wAAIZAAkJPAeYOAAfAQAZAAkJPAeYOAAfAQAAAA==.Aumer:BAAALgAECgQJBQAAAA==.Auranda:BAAALgAECgYJBgAAAA==.',
Av='Avalonia:BAAALgAECgEJAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8dAAIVAAgJJRuWCQDLAQAVAAgJJRuWCQDLAQAuAAQKfykAAhUACQkGIOIDAIUCABUACQkGIOIDAIUCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAABLgAECn8hAAINAAkJWQuPCQA3AQANAAkJWQuPCQA3AQAAAA==.Azurus:BAAALgAECgkJBgAAAA==.',
Ba='Backpedal:BAABLgAECn8lAAIZAAkJMxWvAgD3AQAZAAkJMxWvAgD3AQAAAA==.Badankhadonk:BAACLgAFFH8UAAIMAAUJaCKMEgDSAQAMAAUJaCKMEgDSAQAuAAQKfy0AAgwACQl7JVICAF8DAAwACQl7JVICAF8DAAAA.Balen:BAABLgAECn80AAIEAAkJqhYoCwAWAgAEAAkJqhYoCwAWAgAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn82AAMaAAkJKSIIBgAVAwAaAAkJKSIIBgAVAwAKAAEJYAYKLAAhAAAAAA==.Beliice:BAAALgAECgYJEgABLgAECgkJNgAaACkiAA==.Bellanei:BAAALgAECgEJBAAAAA==.Bellawesome:BAAALgAECgIJAgAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8RAAMHAAUJ+yGIIgDDAQAHAAUJ+yGIIgDDAQAGAAEJ6hDxJwBFAAAuAAQKfysAAgcACQkcJSEMABkDAAcACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJVgAAAA==.',
Bg='Bgpocalypse:BAABLgAFFH8JAAISAAMJggrTUgC1AAASAAMJggrTUgC1AAAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8dAAIGAAkJBRcCBQAnAgAGAAkJBRcCBQAnAgAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8uAAIBAAkJfRjfAwDXAQABAAkJfRjfAwDXAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Blackwing:BAAALgAECgUJBQABLgAFFAMJCAAbAFUVAA==.Bladestriker:BAAALgAFFAMJBAAAAA==.Blessedrayne:BAAALgAECgEJAQAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Blixxkee:BAAALgAECgIJAgABLgAFFAcJHAACAEMaAA==.Bloodache:BAABLgAECn8XAAICAAkJLCBgKQBcAgACAAkJLCBgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAaAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAMAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8mAAIRAAkJuQdiDwATAQARAAkJuQdiDwATAQAAAA==.Bonemarrow:BAABLgAECn8bAAIFAAUJ9BLG1ADtAAAFAAUJ9BLG1ADtAAAAAA==.Boring:BAAALgAECgEJAQAAAA==.Bournx:BAAALgAECgQJBAAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8NAAMBAAQJ2wwkGADgAAABAAQJuQUkGADgAAADAAMJZw/GDAB9AAAuAAQKf14ABAMACQnrG+kEAGUCAAMACQnrG+kEAGUCAAEAAwlkD9lYAFwAAAIAAQmlAcf0ABsAAAAA.Brakeable:BAAALgAECgUJBQAAAA==.Braké:BAABLgAECn8eAAIEAAkJaB1lBQCbAgAEAAkJaB1lBQCbAgAAAA==.Brandrale:BAAALgAECgcJCgAAAA==.Breakthrough:BAABLgAECn8lAAIMAAYJOCPbHgBXAgAMAAYJOCPbHgBXAgAAAA==.Brewskies:BAABLgAECn8nAAIcAAcJDyWVDABtAgAcAAcJDyWVDABtAgABLgAECgkJNQAdAPYiAA==.Brewsli:BAAALgADCgIJAgABLgAECgkJMgAdAGwRAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQACAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Broombolt:BAABLgAECn8UAAIHAAkJHxmTAwBaAgAHAAkJHxmTAwBaAgAAAA==.Brownington:BAACLgAFFH8GAAMYAAMJJRJIFQCGAAAYAAIJFA1IFQCGAAAQAAEJSBz0NgBJAAAuAAQKfxoAAxAACAkzJAkJAFsCABAABwlWJAkJAFsCABgAAgkDFwgNAGkAAAAA.Bruhilda:BAABLgAECn8dAAIWAAkJ7hLuSwD3AQAWAAkJ7hLuSwD3AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brãke:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8fAAMGAAgJEhyvCAAMAQAHAAcJWRlfKwCZAQAGAAQJTx+vCAAMAQAuAAQKfyoAAwYACQkPJL4FAA4CAAYABgkoJb4FAA4CAAcABQkeI4JzAFMBAAAA.',
Bu='Buc:BAAALgAECgEJAQAAAA==.Bufferfish:BAABLgAECn82AAIeAAkJUQxkLwB7AQAeAAkJUQxkLwB7AQAAAA==.',
Ca='Calinnea:BAABLgAECn8VAAMfAAgJDBCjMwCoAQAfAAgJDBCjMwCoAQAZAAIJDgOFiAAnAAAAAA==.Canadaispimp:BAAALgAECgIJAgAAAA==.Cantheartitz:BAABLgAECn8WAAIWAAUJPxmBnQCbAQAWAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8xAAIZAAkJNiKTBAAOAwAZAAkJNiKTBAAOAwAAAA==.Catdav:BAAALgAECgUJCAABLgAECgkJMQAZADYiAA==.',
Ce='Celira:BAAALgADCgMJAwABLgAECgYJDgALAAAAAA==.Celthol:BAABLgAECn8nAAICAAYJnxiWDAA4AQACAAYJnxiWDAA4AQAAAA==.',
Ch='Charana:BAAALgAECgEJAQABLgAECgUJCwALAAAAAA==.Chelraani:BAABLgAECn9AAAIFAAkJMSRfBgA+AwAFAAkJMSRfBgA+AwAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIZAAkJ8CTAAgBtAwAZAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgAECgIJAgAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgAECgYJEgAAAA==.',
Ci='Cigar:BAAALgAECgQJCQABLgAFFAgJHwASADsdAA==.Cinderat:BAAALgADCgEJAQAAAA==.Cinderburn:BAAALgADCgYJBgABLgAFFAIJAQALAAAAAA==.',
Cl='Clambumper:BAAALgAECgEJAQABLgAECgcJDwALAAAAAA==.Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAITAAYJBBYHDwCNAQATAAYJBBYHDwCNAQAuAAQKfxUAAhMACAkMGcscAGcCABMACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8QAAMfAAYJnBQJKAAuAQAfAAUJPxIJKAAuAQAZAAQJbg3ADQCWAAAuAAQKfx8ABBkACQmbFmIeAOUBABkABwlYHGIeAOUBAB8ACAniEYomAH4BABwAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAFFAIJAQALAAAAAA==.Clue:BAAALgAECgcJBwAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAABLgAECn8WAAIgAAgJxxb0AwDuAQAgAAgJxxb0AwDuAQAAAA==.Conjredcukee:BAABLgAECn8WAAIWAAcJ7ANF5wDQAAAWAAcJ7ANF5wDQAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwALAAAAAA==.Coogsayer:BAABLgAECn8UAAIJAAcJyh2aEQBxAgAJAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMMAAgJBBpXKQAYAgAMAAgJBBpXKQAYAgANAAMJoBfKagCnAAAAAA==.',
Cr='Crackstalion:BAAALgAECgQJCAAAAA==.Crimson:BAAALgAECgcJBwAAAA==.Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgAFFAEJAgAAAA==.Crowshadow:BAABLgAECn8cAAIHAAgJ8Bp9KQA1AgAHAAgJ8Bp9KQA1AgAAAA==.',
Cu='Cukeemonster:BAAALgAECgEJAQAAAA==.',
Cy='Cydarr:BAAALgAECgIJAwAAAA==.Cylina:BAAALgADCgcJCAABLgADCgcJFQALAAAAAA==.Cyliya:BAAALgADCgIJAwABLgADCgcJFQALAAAAAA==.Cylore:BAAALgADCgcJBgABLgADCgcJFQALAAAAAA==.Cynight:BAAALgADCgEJAgABLgADCgcJFQALAAAAAA==.Cypherrellik:BAAALgAECgQJBAABLgAECgkJHAABAIUQAA==.Cyrax:BAAALgADCgYJCQAAAA==.Cyther:BAACLgAFFH8jAAITAAgJ8xw6BQAaAgATAAgJ8xw6BQAaAgAuAAQKfykAAhMACQmXIqwHAC4DABMACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAICAAkJ4BzDHAClAgACAAkJ4BzDHAClAgAAAA==.',
Da='Daddylight:BAAALgAECgYJBgAAAA==.Dakk:BAABLgAECn9KAAISAAkJOiNnCgAcAwASAAkJOiNnCgAcAwAAAA==.Dangbor:BAAALgAECgEJAQABLgAECgkJMQAOAJAWAA==.Danoa:BAAALgAECgEJAQAAAA==.Daraghor:BAABLgAECn8bAAIQAAkJoCIMAgAbAwAQAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJCgAAAA==.Darkenstormy:BAABLgAECn8WAAMFAAkJHRI/IQDbAAAFAAcJvRU/IQDbAAAgAAQJlw3tGABXAAAAAA==.Darkmage:BAAALgADCgUJBQAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgAECgEJAQABLgAECgcJDwALAAAAAA==.',
De='Deadlight:BAABLgAECn8xAAMSAAkJzhJzUwDKAQASAAkJOhJzUwDKAQAbAAEJYBKBOQA3AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn84AAITAAkJayXrAwAoAwATAAkJayXrAwAoAwABLgAFFAMJCAAbAFUVAA==.Delkroth:BAAALgAECgQJBAABLgAECgkJMgAdAGwRAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAICAAkJAROqSgCmAQACAAkJAROqSgCmAQAAAA==.Demonknight:BAAALgADCgcJEQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAINAAgJ/xVSIgDSAQANAAgJ/xVSIgDSAQAAAA==.Demonthorx:BAAALgAECgUJBQAAAA==.Demonx:BAABLgAECn8zAAISAAkJ+x1cGgCoAgASAAkJ+x1cGgCoAgAAAA==.Dennis:BAAALgAECgYJCgABLgAECgkJFQAFAAIVAA==.Deranged:BAAALgADCgEJAQAAAA==.Derpsicle:BAAALgAECgEJAQAAAA==.Desolation:BAABLgAECn9SAAIXAAkJ+iUnAABsAwAXAAkJ+iUnAABsAwAAAA==.Despia:BAABLgAECn87AAMaAAkJZCS2AQCbAwAaAAkJZCS2AQCbAwAJAAYJzxH4MgBOAQAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAABLgAFFAgJIAAOAC4bAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8yAAIhAAkJRxPqJgAZAgAhAAkJRxPqJgAZAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Dk='Dkken:BAAALgAECgEJAQAAAA==.',
Do='Dodgey:BAAALgAECgQJBAAAAA==.Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8OAAIHAAMJDQYpjgCoAAAHAAMJDQYpjgCoAAAuAAQKf0MAAwcACAlhE6hfAIEBAAcACAlhE6hfAIEBACIABgnyBUMQACoBAAAA.Dontormenta:BAABLgAFFH8FAAMCAAMJfQ0kNwCaAAACAAMJQgokNwCaAAABAAIJzgcIGQBdAAABLgAFFAQJCQAbAN8PAA==.Donut:BAAALgADCgIJAgABLgAECgkJIQAjAKMiAA==.Dotdaddy:BAAALgAECgYJDQABLgAECggJFQAfAAwQAA==.Doughy:BAAALgAFFAIJAgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8mAAIeAAYJ+xmjGAChAQAeAAYJ+xmjGAChAQAuAAQKfyIAAx4ACQk4H4AMAJMCAB4ACQk4H4AMAJMCAA4AAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8cAAICAAcJKBBVbABLAQACAAcJKBBVbABLAQAAAA==.Dragoncurry:BAABLgAECn8WAAIOAAYJIgZGKACpAAAOAAYJIgZGKACpAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Dragonu:BAABLgAFFH8GAAIOAAMJDBHmDwCgAAAOAAMJDBHmDwCgAAABLgAFFAYJJgAeAPsZAA==.Drakka:BAAALgADCgkJDgABLgAECgkJFQAFAAIVAA==.Draktyr:BAACLgAFFH8GAAITAAMJtRZeFgCyAAATAAMJtRZeFgCyAAAuAAQKfyQAAhMACQn2HncJABYDABMACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAhADkZAA==.Drlovely:BAAALgAECgUJCwAAAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.Druadh:BAAALgADCgYJBgABLgAECggJFQAMAP8ZAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMVAAgJ6xbDMQCpAQAVAAcJ6xXDMQCpAQAIAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgUJCwAAAA==.Dyzhander:BAAALgAECgEJAQAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
Eh='Ehjan:BAAALgAECgQJBAAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellalais:BAAALgAFFAEJAgAAAA==.Ellismom:BAABLgAECn9BAAISAAkJ+SHbDQD9AgASAAkJ+SHbDQD9AgAAAA==.Elosong:BAAALgAECgEJAQAAAA==.Elvea:BAABLgAECn8kAAMeAAgJjRr1GQAHAgAeAAgJjRr1GQAHAgAjAAEJ9QoWQgArAAABLgAFFAgJIAAkAIcUAA==.',
Em='Emeralddemon:BAAALgAECgYJDQAAAA==.Emeraldshade:BAAALgADCgcJEwABLgAECgYJDQALAAAAAA==.Emeråld:BAAALgAECgUJBwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAMAP8ZAA==.',
Eo='Eolyndin:BAAALgADCgQJBAAAAA==.',
Er='Eregon:BAAALgADCgYJBgAAAA==.Ereithelda:BAACLgAFFH8nAAMfAAgJhBVkFwDCAQAfAAgJhBVkFwDCAQAZAAIJOxWFLgCNAAAuAAQKfykAAh8ACQktIhcHAOkCAB8ACQktIhcHAOkCAAAA.Ericka:BAAALgAECgYJEAAAAA==.Erowid:BAABLgAFFH8MAAIKAAUJXhULEABDAQAKAAUJXhULEABDAQABLgAFFAYJJgAeAPsZAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Eu='Euclid:BAAALgAECgEJAQAAAA==.',
Ev='Evildeadd:BAAALgAECgIJAwABLgAECgcJDwALAAAAAA==.Evox:BAABLgAECn8ZAAMNAAkJOhcvBgCSAQANAAkJOhcvBgCSAQAMAAEJEBRl0wA3AAAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgAFFAIJAgAAAA==.Fann:BAABLgAECn8gAAIhAAkJgAT2awDwAAAhAAkJgAT2awDwAAAAAA==.Fauna:BAAALgAECgYJDQAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgQJBwAAAA==.',
Fe='Fel:BAAALgAECgUJCAAAAA==.Felbubu:BAABLgAECn8jAAQDAAkJlyIeBACAAgADAAkJLCIeBACAAgABAAYJOyAmIgCrAQACAAMJNRx2pwDVAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8TAAIWAAcJ7BamGgCcAQAWAAcJ7BamGgCcAQAuAAQKfyQAAhYACQnjITMdAK0CABYACQnjITMdAK0CAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8ZAAIlAAYJAhOgEgASAQAlAAYJAhOgEgASAQAuAAQKfy0AAiUACQkjHJkLAFQCACUACQkjHJkLAFQCAAEuAAUUBwkMAB0AXQoA.Flakov:BAAALgAECgIJAgABLgAFFAcJDAAdAF0KAA==.Flaktop:BAABLgAFFH8MAAIdAAcJXQrHDAAsAQAdAAcJXQrHDAAsAQAAAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8yAAQdAAkJbBFuBwAfAQAbAAkJuQy3FAA1AQAdAAYJVRNuBwAfAQASAAYJgQkA1QDiAAAAAA==.Force:BAABLgAECn8jAAQbAAkJygqwEgBOAQAbAAgJnwuwEgBOAQASAAUJEATFFQGRAAAdAAEJ+wTIZwAaAAAAAA==.Forgeheart:BAAALgAECgIJAgAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Forsaken:BAACLgAFFH8IAAIbAAMJVRUSEQClAAAbAAMJVRUSEQClAAAuAAQKfyAAAxsACQlbIpsAAB4DABsACQlbIpsAAB4DAB0ABQnlH94HABEBAAAA.Fourdragon:BAAALgADCgQJBAABLgAECggJFwANACQXAA==.Fouris:BAABLgAECn8XAAINAAgJJBfnKgCbAQANAAgJJBfnKgCbAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAIIAAUJZhkzBABdAQAIAAUJZhkzBABdAQAuAAQKfyMAAggACQm6Im0PAMACAAgACQm6Im0PAMACAAAA.Froline:BAAALgAFFAEJAQAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8gAAIdAAkJQxxqCwBYAgAdAAkJQxxqCwBYAgAAAA==.Fryea:BAAALgAECgEJAQAAAA==.',
Ft='Ftwiamtank:BAABLgAECn8aAAIlAAYJeBFbKADxAAAlAAYJeBFbKADxAAABLgAFFAMJCAAPACIEAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.Furah:BAAALgAECgEJBAAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8gAAIWAAgJaRQeKADWAQAWAAgJaRQeKADWAQAuAAQKfysAAhYACQm0HW8sAGcCABYACQm0HW8sAGcCAAAA.Gardon:BAAALgAECgYJCgAAAA==.Gaurdinn:BAABLgAECn8uAAQeAAgJMBMiMgBtAQAeAAgJrhIiMgBtAQAjAAYJfxAREQD5AAAOAAIJagI/PAAyAAABLgAECgkJJQANAKgYAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Geddun:BAAALgAECgIJAgAAAA==.Generickk:BAAALgAFFAEJAQAAAA==.Generickmonk:BAACLgAFFH8YAAIZAAUJox14DgBLAQAZAAUJox14DgBLAQAuAAQKfzAAAhkACQnyIsQFAPMCABkACQnyIsQFAPMCAAAA.Generrick:BAAALgAECgEJAQAAAA==.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Ginrai:BAAALgAECgEJAQAAAA==.Giovannucci:BAAALgAECgEJAwAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAABLgAECn8VAAIEAAYJ+Ah9KwCxAAAEAAYJ+Ah9KwCxAAAAAA==.',
Go='Goatshifter:BAAALgAECgYJCAABLgAFFAQJEQAKAEoQAA==.Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAHAHcUAA==.Gonwean:BAAALgAECgEJAQABLgAFFAcJHwAIAEUeAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIcAAIJahEGSgB3AAAcAAIJahEGSgB3AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAFFAIJAgAAAA==.Grimjob:BAAALgADCgIJAgAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgUJBwAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJBAAAAA==.',
Gu='Guino:BAABLgAECn8VAAIFAAcJOQkSNQCDAAAFAAcJOQkSNQCDAAAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.Guinohunter:BAAALgADCgQJBAAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hahla:BAAALgADCgEJAQAAAA==.Hail:BAAALgAECgMJAwAAAA==.Hamncheeks:BAAALgAECgEJAQAAAA==.Hamnqueso:BAAALgAECgcJEgAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgAFFAIJAQAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAABLgAECgYJJQAMADgjAA==.Hazis:BAABLgAECn8rAAIdAAkJEyEbCACkAgAdAAkJEyEbCACkAgAAAA==.',
Hi='Highflyr:BAAALgAECgEJAQAAAA==.Hinala:BAACLgAFFH8JAAIdAAMJ4gacHAB5AAAdAAMJ4gacHAB5AAAuAAQKfywAAx0ACAnRFJsEAJ0BAB0ABwkZF5sEAJ0BABIAAglaBotNADwAAAAA.Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.Hivemind:BAAALgAECgQJCAABLgAFFAQJFwAFAKcVAA==.',
Ho='Holy:BAACLgAFFH8kAAMgAAgJChGQCACdAQAgAAcJAxCQCACdAQAEAAYJ/QhFCAD0AAAuAAQKfywAAgQACQmkFvMQALcBAAQACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIEAAQJzA/qDQCeAAAEAAQJzA/qDQCeAAAuAAQKfywAAgQACAkHIFEKACUCAAQACAkHIFEKACUCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgAECggJCAAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9SAAIaAAkJqBP/GAADAgAaAAkJqBP/GAADAgAAAA==.Holyshock:BAACLgAFFH8iAAIFAAgJkRrPEgDWAQAFAAgJkRrPEgDWAQAuAAQKfykAAgUACQlkJcoIACMDAAUACQlkJcoIACMDAAAA.Holystax:BAAALgAECgEJBAAAAA==.Honeybutter:BAACLgAFFH82AAMTAAgJDCQiAQD/AgATAAgJDCQiAQD/AgAUAAYJ9SWOBQAXAgAuAAQKf08AAxQACQnIJgkAAJgDABMACQmLJhAAAKMDABQACQmiJgkAAJgDAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9OAAIIAAkJ6yNABgAwAwAIAAkJ6yNABgAwAwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIWAAgJER7kOACSAgAWAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJDgAAAA==.',
In='Inanitas:BAAALgAFFAEJAQAAAA==.Ineffectual:BAABLgAECn8fAAIMAAgJvBMeMgC9AQAMAAgJvBMeMgC9AQAAAA==.',
Ir='Irion:BAAALgADCgUJCAAAAA==.Irukox:BAAALgAECgYJDQAAAA==.',
It='Itsfewz:BAAALgAECgEJAQAAAA==.Itty:BAAALgADCgcJBwAAAA==.',
Iv='Ivygrace:BAAALgAECgYJCAAAAA==.',
Ja='Jacques:BAAALgAECgMJAwAAAA==.Jadaveon:BAAALgAECgQJBQAAAA==.Jadefleur:BAAALgAECgIJAgAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAABLgAECn8UAAIFAAYJJBR2wwAEAQAFAAYJJBR2wwAEAQAAAA==.Janewayy:BAABLgAECn8yAAICAAkJGA13YgBjAQACAAkJGA13YgBjAQAAAA==.Jazmean:BAABLgAECn8bAAIKAAcJThIZCABuAQAKAAcJThIZCABuAQAAAA==.',
Jb='Jbournz:BAAALgAECgUJCAAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJIAAMANwXAA==.Jellied:BAAALgAECgYJCwAAAA==.Jemma:BAABLgAECn8wAAIGAAkJFBWDBgD4AQAGAAkJFBWDBgD4AQAAAA==.Jerikos:BAAALgADCgYJBgAAAA==.Jettadari:BAACLgAFFH8SAAICAAgJKBIXEABNAQACAAgJKBIXEABNAQAuAAQKfyYAAwIACQlsIO0WAM0CAAIACQlsIO0WAM0CAAMAAQlADks1ADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAgJEgACACgSAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAgJEgACACgSAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAgJEgACACgSAA==.',
Ju='Jubba:BAABLgAECn8fAAIWAAkJ1xTWSAABAgAWAAkJ1xTWSAABAgAAAA==.Juderius:BAAALgADCgYJCwABLgAECgcJJAAIAIcRAA==.Junk:BAABLgAECn81AAIdAAkJ9iLwAgAWAwAdAAkJ9iLwAgAWAwAAAA==.Juzu:BAABLgAFFH8GAAIfAAQJagwVIQC6AAAfAAQJagwVIQC6AAAAAA==.',
['Jë']='Jëks:BAACLgAFFH8gAAIMAAcJ3BdLDgD8AQAMAAcJ3BdLDgD8AQAuAAQKfykAAwwACQlhJXEDAEEDAAwACQlhJXEDAEEDAA8AAgkvDsozAGEAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJKAAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn85AAMYAAkJ4SJpAwDdAgAYAAkJ4SJpAwDdAgAmAAEJrQ5kkAAvAAAAAA==.Kalamiti:BAABLgAECn8sAAMGAAkJ5RjaCgCUAQAGAAkJ5RjaCgCUAQAiAAcJzBPdDACOAQAAAA==.Kalid:BAAALgAECgUJBwAAAA==.Kallar:BAABLgAECn84AAMaAAkJRCCVBgAJAwAaAAkJRCCVBgAJAwAJAAIJUQZ/egBKAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Karuon:BAAALgADCgQJBAAAAA==.Katween:BAAALgAECgQJBAAAAA==.Kayeera:BAABLgAECn8kAAMaAAkJYxQ0HADlAQAaAAkJYxQ0HADlAQAJAAQJ8RCnDwDJAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAABLgAECn8rAAIWAAcJfQXLKwCnAAAWAAcJfQXLKwCnAAAAAA==.Kazarath:BAAALgAECgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgYJEAAAAA==.Keeper:BAAALgAECgUJBQABLgAFFAMJCAAbAFUVAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAFAKodAA==.Keladas:BAAALgAECgYJBgAAAA==.Kennethv:BAABLgAECn8XAAMKAAkJJhW6BADlAQAKAAgJNRa6BADlAQAaAAIJvQ2YYwBRAAAAAA==.Keny:BAAALgAECgQJBAABLgAECgYJEAALAAAAAA==.Kenze:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.Kethra:BAAALgADCggJEwAAAA==.Kev:BAAALgAECggJCAAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgYJBgAAAA==.Khiell:BAACLgAFFH8MAAITAAUJgQ8ULQD+AAATAAUJgQ8ULQD+AAAuAAQKfyIAAhMACQkmGkMbABMCABMACQkmGkMbABMCAAAA.Khrominius:BAAALgAECgcJBwAAAA==.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAABLgAFFH8HAAIUAAQJ0xTRGAAdAQAUAAQJ0xTRGAAdAQABLgAFFAgJJQAmAGscAA==.Kiraen:BAAALgAECgMJAwAAAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAAALgAECgIJAgABLgAECgkJEQALAAAAAA==.Kitarazen:BAAALgAECgkJEQAAAA==.Kizli:BAAALgAECgUJBQABLgAECgkJagAaAAcmAA==.',
Kn='Knghtmre:BAAALgAECgEJAQAAAA==.Knoway:BAAALgAECgMJAwAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgYJBwAAAA==.',
Kr='Kragon:BAAALgAECgkJEQAAAA==.Krátos:BAABLgAECn8oAAMUAAkJBxr7CABhAgAUAAkJBxr7CABhAgATAAgJaRE/MwB+AQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIlAAgJ7BvSEQDrAQAlAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAABLgAECn8kAAMIAAcJhxE0EwBOAQAIAAcJhxE0EwBOAQAVAAQJaATMJwB6AAAAAA==.Kurulak:BAABLgAECn82AAICAAkJHxOEOADkAQACAAkJHxOEOADkAQAAAA==.Kuzcotopiajr:BAAALgADCgMJAwAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.Kynigoshanta:BAAALgADCgEJAQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJEgAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAACLgAFFH8GAAIIAAQJkAeBKgD6AAAIAAQJkAeBKgD6AAAuAAQKfzgAAhUACQlrCOMRADwBABUACQlrCOMRADwBAAAA.Lalalalala:BAAALgAECgcJCgAAAA==.Lalaura:BAAALgAECgEJAQAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAYJEQAHAI8NAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leemoo:BAAALgAECgQJBAABLgAECgkJIQAjAKMiAA==.Leriope:BAACLgAFFH8KAAIHAAQJRwV2NgCwAAAHAAQJRwV2NgCwAAAuAAQKf1oAAgcACQmHGhMcAHwCAAcACQmHGhMcAHwCAAAA.Leàf:BAABLgAECn8cAAIMAAgJMxlKHwBVAgAMAAgJMxlKHwBVAgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihpfu:BAAALgAFFAIJAwABLgAFFAQJIAATAJclAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJIAATAJclAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgAECgIJAgAAAA==.Listenlinda:BAAALgAECgMJCQABLgAECgYJDgALAAAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAABLgAECn8WAAIQAAYJIAd4RwCLAAAQAAYJIAd4RwCLAAAAAA==.',
Lj='Lj:BAABLgAECn9TAAIgAAkJDB8MCwDcAgAgAAkJDB8MCwDcAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lorethy:BAAALgAECgMJAwAAAA==.Lovecrafft:BAABLgAECn8VAAMGAAUJUQtOCgCTAAAGAAUJUQtOCgCTAAAHAAMJYgIBGwFNAAAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMdAAMJzxc9QQAsAAASAAIJzxcZ4ACEAAAdAAIJtA49QQAsAAABLgAFFAYJEAAfAJwUAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSJlFwC3AgAFAAgJ8CNlFwC3AgAgAAkJQR+TDAC1AgAEAAUJkB2vHAAwAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgkJDAAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
['Lí']='Líghtmóón:BAAALgAECgUJBQAAAA==.',
Ma='Machamp:BAAALgAECgYJDAAAAA==.Madammìm:BAAALgAECgYJBgAAAA==.Maegan:BAABLgAECn8nAAIFAAkJFA2sEwBDAQAFAAkJFA2sEwBDAQAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAABLgAECn8dAAMlAAcJ0Ab+CQCvAAAlAAcJjwb+CQCvAAAUAAEJWgOEIgAPAAAAAA==.Magerhunter:BAAALgAECgYJCgAAAA==.Magolock:BAAALgAECgUJEgAAAA==.Mahll:BAAALgAECgMJAwABLgAFFAMJCgAWAMgbAA==.Maidrim:BAACLgAFFH8aAAInAAcJ3xYsAQD3AQAnAAcJ3xYsAQD3AQAuAAQKfx8AAicACQmrIfICALICACcACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJDwAAAA==.Makavelli:BAAALgAECgEJAQABLgAECgcJDwALAAAAAA==.Mamajumbo:BAABLgAECn8gAAIIAAkJexwZFwCdAgAIAAkJexwZFwCdAgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAFFAMJBgAFALEdAA==.Mariag:BAAALgADCgYJEAAAAA==.Marikel:BAABLgAECn8dAAISAAYJiwn3JACpAAASAAYJiwn3JACpAAAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Meatshields:BAAALgADCgEJAQAAAA==.Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melichotic:BAAALgADCgEJAQAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Merinda:BAAALgAECgMJAwAAAA==.Metahorfasis:BAAALgAECgYJBgAAAA==.',
Mi='Michaelken:BAABLgAECn8jAAMgAAkJDhckFgBaAgAgAAkJDhckFgBaAgAFAAEJsAd0mgEvAAAAAA==.Micromager:BAAALgAECgUJCwAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Might:BAAALgAECgcJBwABLgAFFAMJCAAbAFUVAA==.Migrains:BAABLgAECn9bAAIEAAkJQCXyAABUAwAEAAkJQCXyAABUAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn9RAAMEAAkJoRZSAgD4AQAEAAkJahVSAgD4AQAFAAkJdhPTRQD1AQAAAA==.Missusgrey:BAAALgAECgUJBQABLgAECgkJagAaAAcmAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn88AAMMAAkJhhzBEwCuAgAMAAkJhhzBEwCuAgANAAQJxgiwegB/AAAAAA==.Modarku:BAAALgADCgYJCgAAAA==.Mogral:BAAALgADCgEJAQAAAA==.Moist:BAAALgAECgQJBAAAAA==.Mojodaddy:BAAALgAECgIJAgAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Monsart:BAAALgAECgEJBQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJCwAAAA==.Moonpetals:BAAALgAECgMJBgAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Moralizdormi:BAAALgAECgQJBQAAAA==.Moregana:BAAALgADCgMJAwAAAA==.Mortiis:BAABLgAECn8UAAMPAAcJ6gubFgBWAQAPAAcJ6gubFgBWAQAMAAIJowc0kABYAAAAAA==.Motako:BAABLgAECn8gAAIMAAcJRCCfFQBoAgAMAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAABLgAECn8iAAIYAAcJOx3WAwBYAQAYAAcJOx3WAwBYAQAAAA==.',
Mu='Munkster:BAAALgAECgMJAwAAAA==.',
My='Mybizël:BAABLgAECn8pAAIIAAcJwR7oIABAAgAIAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgkJFQAFAAIVAA==.Myrlìfax:BAAALgAECgIJAgABLgAECgkJFQAFAAIVAA==.Mystique:BAABLgAECn8jAAIDAAkJqg+8AgBbAQADAAkJqg+8AgBbAQAAAA==.Mythdaraghma:BAABLgAECn8WAAIBAAYJNQiyPQC/AAABAAYJNQiyPQC/AAAAAA==.Mythun:BAAALgADCgIJAgAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8jAAIoAAgJ7xcAAwCnAQAoAAgJ7xcAAwCnAQAuAAQKfzcAAygACQnBJWMCACQDACgACQnBJWMCACQDAAgABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgQJCAAAAA==.',
Na='Naama:BAAALgAECgMJAwAAAA==.Nadaar:BAABLgAECn8bAAIXAAgJWhlaAwDyAQAXAAgJWhlaAwDyAQAAAA==.Naelih:BAABLgAECn8tAAIVAAkJ+Q1PDQCLAQAVAAkJ+Q1PDQCLAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJDAABLgAECggJFQAfAAwQAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Natzu:BAAALgAECgYJCwAAAA==.Naushan:BAAALgAECgMJBAAAAA==.Nazari:BAAALgAECgEJAQABLgAFFAcJEQAhAKcNAA==.Nazeer:BAAALgADCgcJCAABLgAFFAcJEQAhAKcNAA==.Nazgrim:BAACLgAFFH8RAAMhAAcJpw2zFADXAAAhAAYJPgqzFADXAAAmAAIJxQMTMgAwAAAuAAQKfz4AAiEACAnIFlsvAO8BACEACAnIFlsvAO8BAAAA.',
Ne='Necronu:BAACLgAFFH8MAAISAAMJDBemmADdAAASAAMJDBemmADdAAAuAAQKfxkAAxIACQlQIGgXALoCABIACQkFIGgXALoCABsABAmuHZMRAF8BAAEuAAUUBgkmAB4A+xkA.',
Ni='Nicolletti:BAAALgADCgMJAwAAAA==.Nikkolos:BAABLgAECn8hAAIBAAgJ/RKoCAAlAQABAAgJ/RKoCAAlAQAAAA==.Ninjastax:BAAALgAECgEJAwAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAFFAEJAwABLgAFFAQJDgASALsVAA==.',
No='Nogusta:BAACLgAFFH8ZAAITAAYJNxxBDwCLAQATAAYJNxxBDwCLAQAuAAQKfykAAhMACQloH2kLAP8CABMACQloH2kLAP8CAAAA.Norberta:BAABLgAECn8jAAMeAAkJBAiwOABLAQAeAAkJ8AewOABLAQAjAAYJWAbxIwAIAQAAAA==.Nossellia:BAAALgAECgQJBwABLgAFFAEJAgALAAAAAA==.Nosselra:BAAALgAECgIJAgAAAA==.',
Nu='Nuggetssham:BAAALgAECgIJAgAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgYJDgAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAFFAIJBAAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Oneyejack:BAAALgAECgUJCAAAAA==.Onlyshams:BAABLgAECn8hAAIMAAgJtBgvGQBNAgAMAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMMAAkJ2SPlBwD2AgAMAAkJ2SPlBwD2AgANAAcJXRiAHwAUAgABLgAFFAcJHgAhAH4bAA==.Onu:BAABLgAFFH8HAAMmAAMJfQr7HACaAAAmAAMJfQr7HACaAAAhAAEJ6hD2MQAwAAABLgAFFAYJJgAeAPsZAA==.Onubis:BAACLgAFFH8QAAMIAAUJriGILwBRAQAIAAUJriGILwBRAQAoAAIJ5yBLJQCnAAAuAAQKfx8ABAgACQmaHw8MAOECAAgACQmOHw8MAOECABUABgnGHdk0AJcBACgAAQmkI7ZUAFsAAAEuAAUUBgkmAB4A+xkA.Onublue:BAABLgAFFH8GAAMNAAYJ8g8ZIgCYAAANAAQJqQcZIgCYAAAMAAIJ4QauTAA/AAABLgAFFAYJJgAeAPsZAA==.Onuchi:BAABLgAFFH8PAAMZAAYJghbvGAD+AAAZAAUJKRPvGAD+AAAfAAYJ3AQaNgDRAAABLgAFFAYJJgAeAPsZAA==.Onudk:BAAALgAFFAMJBAABLgAFFAYJJgAeAPsZAA==.Onulight:BAABLgAFFH8MAAMFAAYJhxwNFABaAQAFAAUJWR8NFABaAQAgAAIJ4hWnGwB6AAABLgAFFAYJJgAeAPsZAA==.Onulite:BAABLgAFFH8HAAMJAAYJkQgvEQDmAAAJAAUJVgovEQDmAAAKAAIJSQkCKgBXAAABLgAFFAYJJgAeAPsZAA==.Onulock:BAAALgAECgYJCgABLgAFFAYJJgAeAPsZAA==.Onux:BAABLgAFFH8SAAICAAYJOBs5JACeAQACAAYJOBs5JACeAQABLgAFFAYJJgAeAPsZAA==.',
Oo='Oorggtejedor:BAAALgADCgIJAgAAAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Os='Ospfiend:BAAALgAFFAIJAwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAcJFQALAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAABLgAECn8UAAMKAAYJeBOpNABDAQAKAAYJ7hCpNABDAQAaAAQJLxPjVgDaAAAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJJgAIAIsgAA==.Pallyoop:BAABLgAECn8WAAIgAAcJMg83VgDfAAAgAAcJMg83VgDfAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgcJDgABLgAECgkJGwASAAYdAA==.Pathaviendha:BAAALgAECgUJAwABLgAECgkJGwASAAYdAA==.Patherion:BAAALgADCgEJAQABLgAECgkJGwASAAYdAA==.Patheros:BAAALgAECgcJCAABLgAECgkJGwASAAYdAA==.Patholans:BAABLgAECn8bAAISAAkJBh1JGwCjAgASAAkJBh1JGwCjAgAAAA==.Pathology:BAAALgAECgYJCgABLgAECgkJGwASAAYdAA==.Paxman:BAAALgAECgcJCgAAAA==.Paxmansigh:BAAALgAECgEJAQAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwADAJciAA==.Peanutsuckr:BAACLgAFFH8iAAIdAAgJBCB6BwAQAgAdAAgJBCB6BwAQAgAuAAQKfykAAh0ACQnGJSQCADEDAB0ACQnGJSQCADEDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAANANoPAA==.',
Ph='Phantöm:BAAALgAFFAEJAgAAAA==.Phosphate:BAABLgAECn8QAAICAAYJNxKvbgBYAQACAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwALAAAAAA==.',
Pl='Placcid:BAABLgAECn9MAAIIAAkJIh3yFgCeAgAIAAkJIh3yFgCeAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAFFAEJAQAAAA==.',
Po='Pockett:BAABLgAECn8iAAMNAAcJKBGUPwA2AQANAAcJKBGUPwA2AQAPAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8RAAIKAAQJShD6KQD/AAAKAAQJShD6KQD/AAAuAAQKfzwAAgoACQmYFg4VADMCAAoACQmYFg4VADMCAAAA.',
Pr='Prestoh:BAABLgAECn8zAAINAAkJvxFTJQC+AQANAAkJvxFTJQC+AQAAAA==.Prismclaw:BAABLgAECn9SAAIWAAkJhhV/OwAsAgAWAAkJhhV/OwAsAgAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Puk:BAAALgAECgYJBgAAAA==.Purplehaze:BAAALgAECgUJBQAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIaAAkJ3QpDMACAAQAaAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJCgAAAA==.',
Py='Pyous:BAAALgAECgMJAwAAAA==.Pyrada:BAABLgAECn8XAAMDAAkJxRZlCQDVAQACAAgJhxUQOwDbAQADAAgJAhdlCQDVAQAAAA==.Pyrewolf:BAAALgADCgUJBQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8qAAIIAAkJNw0jFwAqAQAIAAkJNw0jFwAqAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8pAAIaAAkJGRedFgAcAgAaAAkJGRedFgAcAgAAAA==.Quilue:BAAALgAECgEJAQAAAA==.Quintin:BAABLgAECn8kAAIjAAkJGhfjAAAEAgAjAAkJGhfjAAAEAgAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBwAAAA==.Ragetotem:BAACLgAFFH8GAAMNAAIJzhANLQBcAAANAAIJzhANLQBcAAAMAAIJywb2cABbAAAuAAQKfyQAAw0ABgmZHCAoANIBAA0ABgmZHCAoANIBAAwAAwkABY+4AFsAAAAA.Ragewarg:BAAALgAFFAIJAgAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Raizel:BAAALgAECgEJAQAAAA==.Rajaion:BAAALgAECgEJAQAAAA==.Ralvarr:BAABLgAECn8aAAIfAAgJIBimGwDbAQAfAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgUJBgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAABLgAECn8cAAIWAAkJgRgtBwAbAgAWAAkJgRgtBwAbAgABLgAECgUJCwALAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAACLgAFFH8OAAMFAAYJ1xGwFgBCAQAFAAYJ1xGwFgBCAQAgAAMJAh1gOwB3AAAuAAQKfxkAAyAACAn8IFwIAOgCACAACAn8IFwIAOgCAAUABgnHHRdhAMEBAAAA.Relik:BAACLgAFFH8GAAMTAAMJnQa5IQCnAAATAAMJBQa5IQCnAAAlAAEJoQQZMAAnAAAuAAQKfyQAAiUACQmPDI8aAGUBACUACQmPDI8aAGUBAAAA.Resith:BAAALgAECgYJCAAAAA==.Retpaladin:BAAALgAECgEJAQAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQlVwgAFAQAFAAcJFQlVwgAFAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8nAAIHAAkJsxQIOAD5AQAHAAkJsxQIOAD5AQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAABLgAECn8ZAAIMAAYJRA6WZgAoAQAMAAYJRA6WZgAoAQAAAA==.Risky:BAAALgAECgEJAQABLgAECgcJGAAhAMYEAA==.',
Ro='Robïn:BAAALgAECgIJAgABLgAECggJFQAfAAwQAA==.Rondon:BAABLgAECn88AAIIAAkJXCY2AQCHAwAIAAkJXCY2AQCHAwAAAA==.Rookdh:BAACLgAFFH8QAAMBAAYJAAbwGADaAAABAAQJUQTwGADaAAACAAYJ6wV0XgDUAAAuAAQKfykAAwIACQnkFuBcAHIBAAIACAk+GOBcAHIBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFQAAAA==.Rosey:BAABLgAECn8sAAIFAAkJcxXvPgAKAgAFAAkJcxXvPgAKAgAAAA==.Rotmaxxer:BAAALgAFFAQJBAAAAA==.Rovayas:BAAALgAECgEJAQAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAABLgAECn8aAAIIAAkJOxfCBgAvAgAIAAkJOxfCBgAvAgAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMHAAgJCQyznAAEAQAHAAYJhw2znAAEAQAGAAIJFQOvRgAfAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIWAAMJCwkqjgC8AAAWAAMJCwkqjgC8AAAuAAQKfycAAhYACQn1HPM0AJ8CABYACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIcAAMJqwvqPQCvAAAcAAMJqwvqPQCvAAAuAAQKfx8AAhwACQmxF4wFAAUBABwACQmxF4wFAAUBAAAA.Rustedshield:BAAALgAECgIJAgABLgAFFAMJCAAcAKsLAA==.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAIQAAcJPRTbDQClAQAQAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8hAAMDAAkJyhwoBACGAgADAAkJyhwoBACGAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgAECgcJDAAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAABLgAFFH8IAAMSAAIJ+x7UugCzAAASAAIJ+x7UugCzAAAbAAIJ1hWQHQCXAAAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8qAAIFAAkJrxHxDgB7AQAFAAkJrxHxDgB7AQAAAA==.Santaclaaws:BAACLgAFFH8cAAICAAcJQxqVDgDQAQACAAcJQxqVDgDQAQAuAAQKfzUABAIACQmkIo4UAJ4CAAIACQmkIo4UAJ4CAAMAAwldFlUcALgAAAEAAgk1GY5bAHIAAAAA.Santapal:BAACLgAFFH8SAAMFAAQJnwhSKwDdAAAFAAQJnwhSKwDdAAAgAAQJZRk3EgDaAAAuAAQKfy4ABCAACAkcGm0oAMgBACAABwmxGm0oAMgBAAUAAgl6BVtxAUcAAAQAAglpEqFOADUAAAEuAAUUBwkcAAIAQxoA.Santatumblr:BAACLgAFFH8GAAMfAAMJdh23LQAFAQAfAAMJdh23LQAFAQAZAAEJLgztQwA3AAAuAAQKfxoABB8ACAlRG0sWAGcCAB8ACAlRG0sWAGcCABkABAlyEABxAG4AABwAAQlNAzWqABoAAAEuAAUUBwkcAAIAQxoA.Santhin:BAAALgAECgkJCwAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMJAAcJ2xEWPwAUAQAJAAYJAhIWPwAUAQAKAAYJIQxSPgATAQAAAA==.Sarmenti:BAAALgAECgEJAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJEAABLgAECgkJOAAaAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn9IAAIMAAkJBBsABABgAgAMAAkJBBsABABgAgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMfAAcJWhx+EwAvAgAfAAcJWhx+EwAvAgAZAAUJZwibWwCmAAAAAA==.Septiria:BAAALgAECgMJAwAAAA==.Sergio:BAAALgAECgcJCgAAAA==.Sesy:BAAALgAECgMJAwAAAA==.Seyren:BAABLgAFFH8NAAIUAAMJTg9VEwCyAAAUAAMJTg9VEwCyAAAAAA==.',
Sh='Shamiska:BAABLgAECn8UAAIPAAgJKgn1HQALAQAPAAgJKgn1HQALAQAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgYJCwABLgAECgcJGAAhAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMMAAkJiSH+BwAvAwAMAAkJiSH+BwAvAwAPAAcJuwpPGwAmAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn9CAAIQAAkJ+Bh4CgA9AgAQAAkJ+Bh4CgA9AgAAAA==.Shieldee:BAABLgAECn82AAMFAAkJ1RxPJAB0AgAFAAkJ1RxPJAB0AgAgAAEJTgOwnQAiAAAAAA==.Shiftystax:BAAALgAECgEJAQAAAA==.Shlectrinell:BAABLgAECn9LAAMkAAkJ7A7xGADSAQAkAAkJ7A7xGADSAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8eAAMWAAYJACHlDgCiAQAWAAYJACHlDgCiAQApAAEJ6g/TBwA5AAAuAAQKfykABBYACQkqJXAJAC8DABYACQkqJXAJAC8DACkAAwlSGHcJALkAABcAAQnWIOsSAFYAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shortebread:BAAALgAFFAIJAgAAAA==.Shortebus:BAAALgAECgkJCwABLgAFFAIJAgALAAAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIkAAgJXRgLGwAoAgAkAAgJXRgLGwAoAgABLgAFFAgJIgAmAAQZAA==.Sighh:BAAALgAECgcJCgAAAA==.Sighhi:BAAALgAECgEJAQAAAA==.Sighhy:BAABLgAECn8ZAAMKAAcJ4RFXCQBQAQAKAAcJ4RFXCQBQAQAJAAUJYgytFQCNAAAAAA==.Siixx:BAAALgAFFAEJAQAAAA==.Sijth:BAACLgAFFH8XAAIFAAQJpxXgQwAjAQAFAAQJpxXgQwAjAQAuAAQKf1gAAgUACQlKIgoPAO4CAAUACQlKIgoPAO4CAAAA.Siks:BAAALgADCgcJBwAAAA==.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silvereyes:BAAALgAECgUJBgAAAA==.Silverwar:BAABLgAECn9FAAMTAAkJ3R5iCQDMAgATAAkJjh5iCQDMAgAlAAkJSBqrAQBhAgAAAA==.Simmi:BAECLgAFFH8eAAIhAAcJfhtcCQBiAgAhAAcJfhtcCQBiAgAuAAQKfykAAiEACQnBJVIGAFIDACEACQnBJVIGAFIDAAAA.Sinanestesia:BAAALgAECgIJBgAAAA==.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAABLgAECn8kAAIFAAkJjxJ7CgDEAQAFAAkJjxJ7CgDEAQAAAA==.Six:BAACLgAFFH8EAAMNAAMJ1BN2KQBqAAANAAIJeRN2KQBqAAAPAAEJihSyFABGAAAuAAQKfzgAAw0ACQnEHwQJAM0CAA0ACQkWHwQJAM0CAA8AAQm0IlMPAGMAAAAA.Sixior:BAAALgAECgkJDgAAAA==.Sixti:BAAALgAECgUJBQAAAA==.Sixx:BAAALgAECgcJBwAAAA==.',
Sk='Skarredd:BAAALgADCgkJGQAAAA==.Skellington:BAAALgAECgEJAQAAAA==.Skepti:BAABLgAECn8xAAIIAAkJZhuvIgBZAgAIAAkJZhuvIgBZAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECggJEgAAAA==.',
Sm='Smeeta:BAACLgAFFH8JAAISAAMJ4BnujwDrAAASAAMJ4BnujwDrAAAuAAQKf2YABBIACQmHJH8PAPACABIACQkxJH8PAPACABsACAldI4ADAK4CAB0ABwmME9cGADIBAAAA.Smoak:BAAALgAECgUJBQAAAA==.Smolderlight:BAACLgAFFH8SAAIgAAQJDhozEAD7AAAgAAQJDhozEAD7AAAuAAQKf0AAAiAACQnVF1kWAFgCACAACQnVF1kWAFgCAAAA.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
Sn='Sneakerbaby:BAAALgADCgMJAwAAAA==.',
So='Socks:BAAALgAECgYJBgABLgAFFAYJJgAeAPsZAA==.Solaace:BAAALgAECgQJBQABLgAECgkJKQAdAGMVAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Sosa:BAABLgAFFH8FAAIlAAUJrxkkEAAxAQAlAAUJrxkkEAAxAQABLgAFFAkJLAAcAFojAA==.Sosrs:BAAALgAECgQJBAABLgAECgYJCwALAAAAAA==.Soulreaver:BAAALgAECgcJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAABLgAECn8dAAMWAAkJUhJmaACrAQAWAAkJAQ9maACrAQAXAAMJyhURBgDJAAAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spike:BAAALgAFFAEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Stabystâb:BAAALgAECgEJAQAAAA==.Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAABLgAECn8YAAIIAAkJgBbdDgCFAQAIAAkJgBbdDgCFAQAAAA==.Stonecrab:BAAALgADCgIJAgAAAA==.Stormcontrol:BAAALgAECgYJCwAAAA==.Stormii:BAABLgAECn8jAAMMAAkJKA6SVABiAQAMAAgJTQySVABiAQANAAMJfhQcZQC2AAAAAA==.Stormtotem:BAAALgAFFAEJAQAAAA==.Strangelock:BAAALgAFFAEJAQAAAA==.Strangerdk:BAABLgAECn8yAAISAAkJug2EXwCqAQASAAkJug2EXwCqAQABLgAFFAEJAQALAAAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBwAAAA==.Superfatbaby:BAABLgAECn8dAAITAAkJKhP4JwC7AQATAAkJKhP4JwC7AQAAAA==.',
Sw='Swiftstroker:BAAALgAECgEJAQABLgAECgcJDwALAAAAAA==.Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAACLgAFFH8NAAIQAAMJGwVCHABeAAAQAAMJGwVCHABeAAAuAAQKfzoAAhAACQkWCq4LAMUAABAACQkWCq4LAMUAAAAA.Swordfish:BAABLgAECn8hAAIjAAkJoyK9AgCKAgAjAAkJoyK9AgCKAgAAAA==.',
Sy='Syannae:BAAALgAECgEJAQAAAA==.Sybelyda:BAAALgADCgYJBgAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBwAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAICAAkJ9wfzigAKAQACAAkJ9wfzigAKAQAAAA==.Syrinne:BAAALgAECgMJAwAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAHAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9SAAIWAAkJ5yHiCwAaAwAWAAkJ5yHiCwAaAwAAAA==.Tadokof:BAAALgADCgkJQgAAAA==.Talanth:BAABLgAECn8eAAInAAkJ7g/IAQBlAQAnAAkJ7g/IAQBlAQAAAA==.Talbott:BAAALgADCgMJAwAAAA==.Talya:BAAALgAECggJCAABLgAECgkJQgAQAPgYAA==.Tandisong:BAAALgAECgcJCwAAAA==.Tanknhammerm:BAAALgAECgUJBQAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8lAAIFAAkJZxb4QgD+AQAFAAkJZxb4QgD+AQAAAA==.Tarma:BAAALgADCgEJAQAAAA==.Tayon:BAABLgAECn8bAAMcAAkJEAhvBgDjAAAcAAkJEAhvBgDjAAAfAAEJTgan0QAfAAAAAA==.Tayvin:BAABLgAECn8WAAMhAAcJeBXUPwCSAQAhAAYJ6RbUPwCSAQAmAAEJOAYlLgAXAAAAAA==.Tazanath:BAAALgADCgEJAgABLgADCgcJFQALAAAAAA==.',
Te='Tempest:BAAALgAECgUJCgAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8iAAIlAAcJZB/rAgBxAQAlAAcJZB/rAgBxAQAuAAQKfygAAiUACQmCJMgCABQDACUACQmCJMgCABQDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Thanlel:BAAALgAECgMJAgAAAA==.Tharja:BAABLgAECn8bAAIWAAkJXhvvNACfAgAWAAkJXhvvNACfAgAAAA==.Theodyn:BAAALgAECgQJDgAAAA==.Theogar:BAAALgAECgEJAQAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgIJAgAAAA==.Thug:BAABLgAECn8WAAMTAAcJ0R/RJQArAgATAAcJ0R/RJQArAgAlAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.Thuneredor:BAAALgADCgYJBgAAAA==.',
Ti='Tiamara:BAAALgAECgQJBAAAAA==.Tiferet:BAACLgAFFH8HAAMaAAMJyReqFAB4AAAaAAIJMBaqFAB4AAAJAAIJVAaNHQBoAAAuAAQKfzwABBoACQn6IXoEADoDABoACQn6IXoEADoDAAoABAnPF6pMANEAAAkACAkuEWgPAMwAAAAA.Tigiw:BAAALgAECgYJDAAAAA==.Tinysunshine:BAABLgAECn8dAAIZAAkJqx8qAgApAgAZAAkJqx8qAgApAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgYJCwAAAA==.Tismtwo:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
Tm='Tmdragon:BAAALgAECgIJAgAAAA==.',
To='Toasted:BAAALgAECgUJBQAAAA==.Tolenkar:BAABLgAECn8mAAIIAAkJiyCcBgA0AgAIAAkJiyCcBgA0AgAAAA==.Tomato:BAACLgAFFH8ZAAMGAAcJ8Q7aBwDxAAAHAAYJ7Q+3UwAfAQAGAAQJxA3aBwDxAAAuAAQKfyMAAwYACQlpHaYFAHoCAAYACAkIHKYFAHoCAAcABQlZFwOdAAQBAAAA.Tomhanks:BAABLgAECn8VAAIFAAkJAhVbOwAWAgAFAAkJAhVbOwAWAgAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9dAAIFAAkJvRt9HwCKAgAFAAkJvRt9HwCKAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Trollfu:BAAALgAECgMJAwAAAA==.Truthslayer:BAABLgAECn8cAAMTAAkJKAmMSgAcAQATAAkJKAmMSgAcAQAUAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIJAAgJxBBMIwC9AQAJAAgJxBBMIwC9AQAAAA==.',
Tt='Tteinfante:BAAALgAECggJCAAAAA==.',
Tu='Tugzug:BAAALgAECgEJAQABLgAECgcJDwALAAAAAA==.Turdyl:BAABLgAECn8sAAIFAAkJuhHKawCXAQAFAAkJuhHKawCXAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgYJCwAAAA==.Twowheels:BAAALgAECgUJDQAAAA==.',
Ty='Tyfelsion:BAAALgAECgUJBQAAAA==.Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8eAAQmAAcJ0hFWDgDWAAAmAAYJ2BNWDgDWAAAYAAUJcQoiNwB/AAAQAAIJgAmGcQA2AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8bAAMNAAkJyhpYLQCwAQANAAgJRBpYLQCwAQAMAAMJuhW0IwB2AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAFFAEJAQAAAA==.',
Un='Unheardjp:BAAALgAECgMJDAAAAA==.Unholy:BAAALgAECgIJBgAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgAECgQJBwAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn83AAIeAAkJBhIfCQDjAAAeAAkJBhIfCQDjAAAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhalr:BAAALgAECgYJCgAAAA==.Valhals:BAABLgAECn84AAMcAAkJSAsJKwBfAQAcAAkJGQkJKwBfAQAZAAMJUQ4AeABhAAAAAA==.Valydrin:BAABLgAECn9aAAIaAAkJnx73CQDIAgAaAAkJnx73CQDIAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Velilla:BAAALgAECgQJBQAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8aAAQKAAQJrA1VLQDoAAAKAAQJcgxVLQDoAAAaAAIJ1AwHDgCOAAAJAAMJKguLGgCDAAAuAAQKf2AABAkACQlCIOcIAL8CAAkACQlCIOcIAL8CAAoACQmUFW0SAFACABoACQlPG4cSAEwCAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8gAAIZAAkJUgtlLQBXAQAZAAkJUgtlLQBXAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJEgABLgAECgkJJQAZADMVAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgYJCgAAAA==.',
Wi='Wickèr:BAACLgAFFH8WAAQcAAQJ7A/jEADMAAAcAAQJqA/jEADMAAAZAAIJuBEdFQCCAAAfAAEJCQvGaAAsAAAuAAQKfzgAAxwACQkHHk0JAJ0CABwACQkHHk0JAJ0CABkAAQnIF1WNAEQAAAAA.Widgit:BAAALgADCgEJAQAAAA==.Wieldblade:BAACLgAFFH8PAAIFAAMJjRi6KgDgAAAFAAMJjRi6KgDgAAAuAAQKf0AAAwUACQn/H84QAOACAAUACQn/H84QAOACAAQACAmIFsgPAMcBAAAA.Wieldblades:BAAALgAECgEJAQAAAA==.Wigdrag:BAAALgAECgkJDgAAAA==.Wilholm:BAAALgAECgMJAwAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Woggo:BAAALgAECgEJAQAAAA==.Wolfemoon:BAABLgAECn8UAAIIAAgJwwo2egBLAQAIAAgJwwo2egBLAQAAAA==.Worganlefey:BAAALgAFFAEJAQABLgAFFAQJCgAHAEcFAA==.',
Wr='Wrexd:BAABLgAECn8qAAIHAAgJChtRRADOAQAHAAgJChtRRADOAQAAAA==.',
Wu='Wunderbar:BAABLgAECn9CAAMNAAkJOyLIBAAUAwANAAkJOyLIBAAUAwAMAAkJ5xjKGQB8AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8lAAQmAAgJaxxJBgDuAQAmAAcJFBxJBgDuAQAhAAEJ/AYKawBEAAAQAAEJHgobRAAkAAAuAAQKfy8AAyYACQleI/kLANgCACYACQleI/kLANgCACEAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIfAAYJcBaKOQCLAQAfAAYJcBaKOQCLAQAAAA==.',
Xa='Xanagoo:BAAALgAECgUJCQAAAA==.Xanith:BAABLgAECn8tAAITAAgJehhGIQDnAQATAAgJehhGIQDnAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgAECgkJDgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgUJCQABLgAECgUJEgALAAAAAA==.Yilnara:BAABLgAECn8bAAICAAkJDgdifgAjAQACAAkJDgdifgAjAQAAAA==.',
Yo='Yondo:BAAALgAECgMJAwAAAA==.',
Ys='Ysa:BAACLgAFFH8FAAIZAAMJPSMsEwAjAQAZAAMJPSMsEwAjAQAuAAQKfyIAAxkACQmmJIwDALQBABkACQmmJIwDALQBAB8AAQmUDZRsACkAAAAA.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgUJEgABLgAECgkJKAAaAAUhAA==.Zogula:BAEBLgAECn8oAAQaAAkJBSHiCwCpAgAaAAkJ0iDiCwCpAgAJAAQJXxZVQQAKAQAKAAEJaiOKZwBgAAAAAA==.',
Zu='Zu:BAAALgAECgcJEQABLgAFFAIJAQALAAAAAA==.Zullthornp:BAAALgADCgYJCwAAAA==.',
Zy='Zynara:BAAALgAECgYJCAAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAIoAAgJwB23DQBMAgAoAAgJwB23DQBMAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Év']='Évélýn:BAAALgAECgEJAQAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECggJFQAfAAwQAA==.',
['Ða']='Ðante:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðelusion:BAAALgAECgMJCAAAAA==.Ðemented:BAAALgAECgEJAQAAAA==.',
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
