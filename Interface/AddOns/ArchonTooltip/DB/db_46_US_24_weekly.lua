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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Druid-Feral','Monk-Windwalker','Priest-Holy','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Paladin-Holy','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Warrior-Protection','Druid-Balance','Rogue-Assassination','Hunter-Survival','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Achak:BAAALgAECgEJAQAAAA==.',
Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAACLgAFFH8KAAIBAAMJcxubBwDvAAABAAMJcxubBwDvAAAuAAQKf0MAAwEACQloI6wCADcDAAEACQloI6wCADcDAAIAAQlCCGk6ACEAAAAA.Adóra:BAAALgAECgMJBAAAAA==.',
Ae='Aeonis:BAABLgAECn8YAAMDAAUJRRGhBQCyAAADAAQJhxShBQCyAAAEAAEJfge3RgAiAAAAAA==.Aestian:BAABLgAECn8xAAIDAAkJ5Rn9DAD1AQADAAkJ5Rn9DAD1AQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgUJBQABLgAECgUJGAADAEURAA==.Airees:BAABLgAECn8iAAIEAAcJOx7oQQAfAgAEAAcJOx7oQQAfAgAAAA==.Aispere:BAABLgAECn8aAAMFAAYJKAdWJACQAAAFAAYJKAdWJACQAAAGAAMJqwDGYwEdAAAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIGAAkJMguKWwCLAQAGAAkJMguKWwCLAQAAAA==.Alfurn:BAAALgADCgIJAwAAAA==.Allanquatre:BAAALgAECgYJBgAAAA==.Alledria:BAACLgAFFH8FAAIEAAQJBwT0dADKAAAEAAQJBwT0dADKAAAuAAQKfxoAAgQACAmaElB5AHwBAAQACAmaElB5AHwBAAAA.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8hAAMHAAkJ/gwFMQBZAQAHAAgJ0A0FMQBZAQAIAAcJoxNkMQBWAQAAAA==.Altonas:BAAALgAECgMJBAAAAA==.',
Am='Amanara:BAAALgAECgcJEgAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.',
An='Ancientmonk:BAAALgAECgEJAQABLgAECgYJCQAJAAAAAA==.Anciientpaw:BAABLgAECn8iAAMKAAkJGyBlHQAvAgAKAAkJGyBlHQAvAgALAAUJbBUZWwDTAAAAAA==.Andramalyus:BAABLgAECn8pAAIGAAgJ3AwtcABaAQAGAAgJ3AwtcABaAQAAAA==.Andrasomnium:BAABLgAECn8bAAIMAAgJRAhxAgD0AAAMAAgJRAhxAgD0AAAAAA==.Angbar:BAABLgAECn8xAAIMAAkJkBYvCQBXAgAMAAkJkBYvCQBXAgAAAA==.Anguirus:BAACLgAFFH8GAAILAAMJjwF5HQBkAAALAAMJjwF5HQBkAAAuAAQKfzwAAwsACQl8BdVOAPsAAAsACQlbBdVOAPsAAA0ABgkCA34tAI0AAAAA.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJCAABLgAECgcJDwAJAAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.Anuksunàmun:BAAALgAECgkJBgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAFFAMJBgAOABsFAA==.Appynoxusrog:BAABLgAECn8cAAIPAAYJuhguBQCcAQAPAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAIQAAMJsRNqngDWAAAQAAMJsRNqngDWAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAACLgAFFH8GAAIRAAMJOg21OADQAAARAAMJOg21OADQAAAuAAQKfzMAAxEACQkcHZwQAHMCABEACQkcHZwQAHMCABIAAQnMB9REAC8AAAAA.Arcadiann:BAABLgAECn8XAAIRAAcJ3xYyLQCdAQARAAcJ3xYyLQCdAQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJDAAAAA==.Arextheelder:BAAALgAFFAEJAQAAAA==.Aridas:BAABLgAECn8dAAMTAAgJJBhuMwAsAgATAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAASAAcaAA==.Arikdeath:BAACLgAFFH8GAAIUAAMJeAyZJADZAAAUAAMJeAyZJADZAAAuAAQKfykAAxQACQmVFwotACgCABQABwlvGAotACgCABUABwlODN0VAAoBAAAA.Armorscales:BAACLgAFFH8aAAIGAAcJMxg5DgB5AQAGAAcJMxg5DgB5AQAuAAQKfy0AAgYACQm/IVgQAPcCAAYACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAJAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAJAAAAAA==.Arnixx:BAAALgAECgQJDQAAAA==.Arntraz:BAAALgADCgkJTgAAAA==.Aryel:BAAALgADCgkJDwAAAA==.Arçadia:BAAALgAECgMJBwAAAA==.',
As='Ashcaller:BAAALgAECgIJAwAAAA==.Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Asprika:BAABLgAFFH8JAAIHAAQJQgvoDADHAAAHAAQJQgvoDADHAAAAAA==.Astayoni:BAAALgADCgEJAQAAAA==.Astrine:BAACLgAFFH8VAAMWAAcJxhShPgBzAQAWAAYJyBahPgBzAQAXAAEJvAoyAwBOAAAuAAQKfysAAhYACQlJIAYiAOsCABYACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIYAAkJ/xl6BgCSAgAYAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8wAAIZAAkJPAeYOAAfAQAZAAkJPAeYOAAfAQAAAA==.Aumer:BAAALgAECgQJBAAAAA==.Auranda:BAAALgAECgYJBgAAAA==.',
Av='Avalonia:BAAALgAECgEJAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8dAAIVAAgJJRuWCQDLAQAVAAgJJRuWCQDLAQAuAAQKfykAAhUACQkGIOIDAIUCABUACQkGIOIDAIUCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAABLgAECn8XAAILAAkJgwgtCgCwAAALAAkJgwgtCgCwAAAAAA==.Azurus:BAAALgAECgkJBgAAAA==.',
Ba='Backpedal:BAABLgAECn8gAAIZAAkJzxRiAQD0AQAZAAkJzxRiAQD0AQAAAA==.Badankhadonk:BAACLgAFFH8UAAIKAAUJaCKMEgDSAQAKAAUJaCKMEgDSAQAuAAQKfy0AAgoACQl7JVICAF8DAAoACQl7JVICAF8DAAAA.Balen:BAABLgAECn80AAIDAAkJqhYoCwAWAgADAAkJqhYoCwAWAgAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8zAAIaAAkJKSIIBgAVAwAaAAkJKSIIBgAVAwAAAA==.Beliice:BAAALgAECgUJCAABLgAECgkJMwAaACkiAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8RAAMGAAUJ+yGIIgDDAQAGAAUJ+yGIIgDDAQAFAAEJ6hDxJwBFAAAuAAQKfysAAgYACQkcJSEMABkDAAYACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJUAAAAA==.',
Bg='Bgpocalypse:BAAALgAFFAMJAwAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8dAAIFAAkJBRcCBQAnAgAFAAkJBRcCBQAnAgAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8nAAIBAAkJqRUgFADxAQABAAkJqRUgFADxAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAFFAEJAQAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAITAAcJKSFgKQBcAgATAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAaAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAKAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8mAAIPAAkJuQdiDwATAQAPAAkJuQdiDwATAQAAAA==.Bonemarrow:BAABLgAECn8bAAIEAAUJ9BLG1ADtAAAEAAUJ9BLG1ADtAAAAAA==.Boring:BAAALgAECgEJAQAAAA==.Bournx:BAAALgAECgQJBAAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8NAAMBAAQJ2wwkGADgAAABAAQJuQUkGADgAAACAAMJZw/GDAB9AAAuAAQKf14ABAIACQnrG+kEAGUCAAIACQnrG+kEAGUCAAEAAwlkD9lYAFwAABMAAQmlAcf0ABsAAAAA.Brakeable:BAAALgAECgUJBQAAAA==.Braké:BAABLgAECn8eAAIDAAkJaB1lBQCbAgADAAkJaB1lBQCbAgAAAA==.Brandrale:BAAALgAECgcJCQAAAA==.Breakthrough:BAABLgAECn8lAAIKAAYJOCPbHgBXAgAKAAYJOCPbHgBXAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIbAAcJDyWVDABtAgAbAAcJDyWVDABtAgABLgAECgkJNQAcAPYiAA==.Brewsli:BAAALgADCgIJAgABLgAECgkJKAAdAIgMAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQATAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Broombolt:BAAALgAECggJCgAAAA==.Brownington:BAACLgAFFH8GAAMYAAMJJRJIFQCGAAAYAAIJFA1IFQCGAAAOAAEJSBz0NgBJAAAuAAQKfxkAAw4ABwlWJAkJAFsCAA4ABwlWJAkJAFsCABgAAQmjCrFXACsAAAAA.Bruhilda:BAABLgAECn8dAAIWAAkJ7hLuSwD3AQAWAAkJ7hLuSwD3AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brãke:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8fAAMFAAgJEhyvCAAMAQAGAAcJWRlfKwCZAQAFAAQJTx+vCAAMAQAuAAQKfyoAAwUACQkPJL4FAA4CAAUABgkoJb4FAA4CAAYABQkeI4JzAFMBAAAA.',
Bu='Buc:BAAALgAECgEJAQAAAA==.Bufferfish:BAABLgAECn82AAIeAAkJUQxkLwB7AQAeAAkJUQxkLwB7AQAAAA==.',
Ca='Calinnea:BAABLgAECn8VAAMfAAgJDBCjMwCoAQAfAAgJDBCjMwCoAQAZAAIJDgOFiAAnAAAAAA==.Canadaispimp:BAAALgAECgIJAgAAAA==.Cantheartitz:BAABLgAECn8WAAIWAAUJPxmBnQCbAQAWAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8uAAIZAAkJJSKTBAAOAwAZAAkJJSKTBAAOAwAAAA==.',
Ce='Celira:BAAALgADCgMJAwABLgAECgQJCQAJAAAAAA==.Celthol:BAABLgAECn8nAAITAAYJnxiABgBCAQATAAYJnxiABgBCAQAAAA==.',
Ch='Chelraani:BAABLgAECn9AAAIEAAkJMSRfBgA+AwAEAAkJMSRfBgA+AwAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIZAAkJ8CTAAgBtAwAZAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgAECgYJCAAAAA==.',
Ci='Cigar:BAAALgAECgQJCQABLgAFFAgJHgAQADsdAA==.Cinderat:BAAALgADCgEJAQAAAA==.Cinderburn:BAAALgADCgYJBgABLgAECgcJEAAJAAAAAA==.',
Cl='Clambumper:BAAALgAECgEJAQABLgAECgcJDwAJAAAAAA==.Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAIRAAYJBBYHDwCNAQARAAYJBBYHDwCNAQAuAAQKfxUAAhEACAkMGcscAGcCABEACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8QAAMfAAYJnBQJKAAuAQAfAAUJPxIJKAAuAQAZAAQJbg3ADQCWAAAuAAQKfx8ABBkACQmbFmIeAOUBABkABwlYHGIeAOUBAB8ACAniEYomAH4BABsAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgcJEAAJAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAABLgAECn8WAAIgAAgJxxbeAQDnAQAgAAgJxxbeAQDnAQAAAA==.Conjredcukee:BAABLgAECn8WAAIWAAcJ7ANF5wDQAAAWAAcJ7ANF5wDQAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAJAAAAAA==.Coogsayer:BAABLgAECn8UAAIHAAcJyh2aEQBxAgAHAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMKAAgJBBpXKQAYAgAKAAgJBBpXKQAYAgALAAMJoBfKagCnAAAAAA==.',
Cr='Crackstalion:BAAALgAECgEJAQAAAA==.Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAABLgAECn8cAAIGAAgJ8Bp9KQA1AgAGAAgJ8Bp9KQA1AgAAAA==.',
Cu='Cukeemonster:BAAALgAECgEJAQAAAA==.',
Cy='Cylina:BAAALgADCgcJCAABLgADCgcJFAAJAAAAAA==.Cyliya:BAAALgADCgIJAwABLgADCgcJFAAJAAAAAA==.Cylore:BAAALgADCgcJBgABLgADCgcJFAAJAAAAAA==.Cynight:BAAALgADCgEJAQABLgADCgcJFAAJAAAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyrax:BAAALgADCgYJCQAAAA==.Cyther:BAACLgAFFH8jAAIRAAgJ8xw6BQAaAgARAAgJ8xw6BQAaAgAuAAQKfykAAhEACQmXIqwHAC4DABEACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAITAAkJ4BzDHAClAgATAAkJ4BzDHAClAgAAAA==.',
Da='Daddylight:BAAALgAECgYJBgAAAA==.Dakk:BAABLgAECn9KAAIQAAkJOiNnCgAcAwAQAAkJOiNnCgAcAwAAAA==.Dangbor:BAAALgAECgEJAQABLgAECgkJMQAMAJAWAA==.Daraghor:BAABLgAECn8bAAIOAAkJoCIMAgAbAwAOAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJCQAAAA==.Darkenstormy:BAABLgAECn8WAAMEAAkJHRKiEgDcAAAEAAcJvRWiEgDcAAAgAAQJlw1wDQBXAAAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgAECgEJAQABLgAECgcJDwAJAAAAAA==.',
De='Deadlight:BAABLgAECn8xAAMQAAkJzhJzUwDKAQAQAAkJOhJzUwDKAQAdAAEJYBKBOQA3AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8yAAIRAAkJMSTrAwAoAwARAAkJMSTrAwAoAwABLgAFFAMJCAAdAFUVAA==.Delkroth:BAAALgAECgQJBAABLgAECgkJKAAdAIgMAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAITAAkJAROqSgCmAQATAAkJAROqSgCmAQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAILAAgJ/xVSIgDSAQALAAgJ/xVSIgDSAQAAAA==.Demonthorx:BAAALgAECgUJBQAAAA==.Demonx:BAABLgAECn8zAAIQAAkJ+x1cGgCoAgAQAAkJ+x1cGgCoAgAAAA==.Dennis:BAAALgAECgYJCgABLgAECgkJFQAEAAIVAA==.Derpsicle:BAAALgAECgEJAQAAAA==.Desolation:BAABLgAECn9SAAIXAAkJ+iUnAABsAwAXAAkJ+iUnAABsAwAAAA==.Despia:BAABLgAECn87AAMaAAkJZCS2AQCbAwAaAAkJZCS2AQCbAwAHAAYJzxH4MgBOAQAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAABLgAFFAcJHwAMAH0cAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8yAAIhAAkJRxPqJgAZAgAhAAkJRxPqJgAZAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8OAAIGAAMJDQY1OQBrAAAGAAMJDQY1OQBrAAAuAAQKf0IAAwYACAnwEqhfAIEBAAYACAnwEqhfAIEBACIABgnyBUMQACoBAAAA.Dontormenta:BAAALgAECgcJDwAAAA==.Donut:BAAALgADCgIJAgABLgAECggJHwAjAJkhAA==.Dotdaddy:BAAALgAECgUJCwABLgAECggJFQAfAAwQAA==.Doughy:BAAALgAFFAIJAgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8mAAIeAAYJ+xmjGAChAQAeAAYJ+xmjGAChAQAuAAQKfyIAAx4ACQk4H4AMAJMCAB4ACQk4H4AMAJMCAAwAAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8cAAITAAcJKBBVbABLAQATAAcJKBBVbABLAQAAAA==.Dragoncurry:BAABLgAECn8WAAIMAAYJIgZGKACpAAAMAAYJIgZGKACpAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgkJFQAEAAIVAA==.Draktyr:BAACLgAFFH8GAAIRAAMJtRZeFgCyAAARAAMJtRZeFgCyAAAuAAQKfyQAAhEACQn2HncJABYDABEACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAhADkZAA==.Drlovely:BAAALgADCgkJCQAAAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.Druadh:BAAALgADCgYJBgABLgAECggJFQAKAP8ZAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMVAAgJ6xbDMQCpAQAVAAcJ6xXDMQCpAQAUAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgUJBwAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn9BAAIQAAkJ+SHbDQD9AgAQAAkJ+SHbDQD9AgAAAA==.Elosong:BAAALgAECgEJAQAAAA==.Elvea:BAABLgAECn8kAAMeAAgJjRr1GQAHAgAeAAgJjRr1GQAHAgAjAAEJ9QoWQgArAAAAAA==.',
Em='Emeralddemon:BAAALgAECgYJDQAAAA==.Emeraldshade:BAAALgADCgcJEwABLgAECgYJDQAJAAAAAA==.Emeråld:BAAALgAECgUJBwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAKAP8ZAA==.',
Eo='Eolyndin:BAAALgADCgQJBAAAAA==.',
Er='Eregon:BAAALgADCgYJBgAAAA==.Ereithelda:BAACLgAFFH8lAAMfAAgJhBVkFwDCAQAfAAgJhBVkFwDCAQAZAAIJOxWFLgCNAAAuAAQKfyYAAh8ACAm2IhcHAOkCAB8ACAm2IhcHAOkCAAAA.Ericka:BAAALgAECgYJDAAAAA==.Erowid:BAABLgAFFH8MAAIIAAUJYBXjCQBgAQAIAAUJYBXjCQBgAQABLgAFFAYJJgAeAPsZAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Eu='Euclid:BAAALgAECgEJAQAAAA==.',
Ev='Evildeadd:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Evox:BAABLgAECn8ZAAMLAAkJOhcAAwCUAQALAAkJOhcAAwCUAQAKAAEJEBRl0wA3AAAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgAFFAIJAgAAAA==.Fann:BAABLgAECn8gAAIhAAkJgAT2awDwAAAhAAkJgAT2awDwAAAAAA==.Fauna:BAAALgAECgYJCAAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgQJBwAAAA==.',
Fe='Fel:BAAALgAECgUJBgAAAA==.Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQATAAMJNRx2pwDVAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8SAAIWAAYJXhhlFABxAQAWAAYJXhhlFABxAQAuAAQKfyQAAhYACQnjITMdAK0CABYACQnjITMdAK0CAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8ZAAIkAAYJAhOgEgASAQAkAAYJAhOgEgASAQAuAAQKfy0AAiQACQkjHJkLAFQCACQACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAYJGQAkAAITAA==.Flaktop:BAABLgAFFH8GAAIcAAYJoAptCQAGAQAcAAYJoAptCQAGAQABLgAFFAYJGQAkAAITAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8oAAMdAAkJiAy3FAA1AQAdAAkJVgy3FAA1AQAQAAYJgQkA1QDiAAAAAA==.Force:BAABLgAECn8jAAQdAAkJygqwEgBOAQAdAAgJnwuwEgBOAQAQAAUJEATFFQGRAAAcAAEJ+wTIZwAaAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Forsaken:BAACLgAFFH8IAAIdAAMJVRUUCgC2AAAdAAMJVRUUCgC2AAAuAAQKfx8AAx0ACQkLIlUAAB0DAB0ACQkLIlUAAB0DABwABQnlH/gDABkBAAAA.Fourdragon:BAAALgADCgQJBAABLgAECggJFwALACQXAA==.Fouris:BAABLgAECn8XAAILAAgJJBfnKgCbAQALAAgJJBfnKgCbAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAIUAAUJZhkzBABdAQAUAAUJZhkzBABdAQAuAAQKfyMAAhQACQm6Im0PAMACABQACQm6Im0PAMACAAAA.Froline:BAAALgAFFAEJAQAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8gAAIcAAkJQxxqCwBYAgAcAAkJQxxqCwBYAgAAAA==.Fryea:BAAALgAECgEJAQAAAA==.',
Ft='Ftwiamtank:BAABLgAECn8ZAAIkAAYJrw9bKADxAAAkAAYJrw9bKADxAAABLgAECgkJLQANAIIMAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.Furah:BAAALgAECgEJBAAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8gAAIWAAgJaRQeKADWAQAWAAgJaRQeKADWAQAuAAQKfysAAhYACQm0HW8sAGcCABYACQm0HW8sAGcCAAAA.Gardon:BAAALgAECgYJCgAAAA==.Gaurdinn:BAABLgAECn8uAAQeAAgJMBMiMgBtAQAeAAgJrhIiMgBtAQAjAAYJfxAREQD5AAAMAAIJagI/PAAyAAABLgAECgkJJQALAKgYAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickk:BAAALgAFFAEJAQAAAA==.Generickmonk:BAACLgAFFH8YAAIZAAUJox14DgBLAQAZAAUJox14DgBLAQAuAAQKfzAAAhkACQnyIsQFAPMCABkACQnyIsQFAPMCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAwAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAABLgAECn8VAAIDAAYJ+Ah9KwCxAAADAAYJ+Ah9KwCxAAAAAA==.',
Go='Goatshifter:BAAALgAECgIJAgABLgAFFAQJEAAIAEoQAA==.Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAGAHcUAA==.Gonwean:BAAALgAECgEJAQABLgAFFAcJGgAUAHscAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIbAAIJahEGSgB3AAAbAAIJahEGSgB3AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAFFAIJAgAAAA==.Grimjob:BAAALgADCgIJAgAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgUJBwAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJBAAAAA==.',
Gu='Guino:BAAALgAECgcJDwAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.Guinohunter:BAAALgADCgQJBAAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hahla:BAAALgADCgEJAQAAAA==.Hail:BAAALgAECgMJAwAAAA==.Hamncheeks:BAAALgAECgEJAQAAAA==.Hamnqueso:BAAALgAECgQJBwAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAABLgAECgYJJQAKADgjAA==.Hazis:BAABLgAECn8rAAIcAAkJEyEbCACkAgAcAAkJEyEbCACkAgAAAA==.',
Hi='Highflyr:BAAALgAECgEJAQAAAA==.Hinala:BAACLgAFFH8FAAIcAAMJ0ALfEwB0AAAcAAMJ0ALfEwB0AAAuAAQKfxQAAxwABwnCC4wEAPoAABwABwnCC4wEAPoAABAAAQmQBWQ8ACEAAAAA.Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.Hivemind:BAAALgAECgQJCAABLgAFFAQJDQAEAEMUAA==.',
Ho='Holy:BAACLgAFFH8eAAMgAAcJWQ9QBgBrAQAgAAYJ3w1QBgBrAQADAAYJ/QhFCAD0AAAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA/qDQCeAAADAAQJzA/qDQCeAAAuAAQKfywAAgMACAkHIFEKACUCAAMACAkHIFEKACUCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgAECggJCAAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9RAAIaAAkJqBP/GAADAgAaAAkJqBP/GAADAgAAAA==.Holyshock:BAACLgAFFH8iAAIEAAgJkRrPEgDWAQAEAAgJkRrPEgDWAQAuAAQKfykAAgQACQlkJcoIACMDAAQACQlkJcoIACMDAAAA.Holystax:BAAALgAECgEJBAAAAA==.Honeybutter:BAACLgAFFH8hAAMSAAYJByaOBQAXAgASAAYJ9SWOBQAXAgARAAUJ2SUzCgC9AQAuAAQKfzsAAxIACQkzJgkBAGgDABIACQkzJgkBAGgDABEABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9OAAIUAAkJ6yNABgAwAwAUAAkJ6yNABgAwAwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIWAAgJER7kOACSAgAWAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJDgAAAA==.',
In='Inanitas:BAAALgAECgEJAQAAAA==.Ineffectual:BAABLgAECn8fAAIKAAgJvBMeMgC9AQAKAAgJvBMeMgC9AQAAAA==.',
Ir='Irion:BAAALgADCgMJAwAAAA==.Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgAECgQJBAAAAA==.Jadefleur:BAAALgAECgEJAQAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJEgAAAA==.Janewayy:BAABLgAECn8yAAITAAkJGA13YgBjAQATAAkJGA13YgBjAQAAAA==.Jazmean:BAABLgAECn8UAAIIAAcJsw4fLQBwAQAIAAcJsw4fLQBwAQAAAA==.',
Jb='Jbournz:BAAALgAECgUJCAAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJIAAKANwXAA==.Jemma:BAABLgAECn8wAAIFAAkJFBWDBgD4AQAFAAkJFBWDBgD4AQAAAA==.Jerikos:BAAALgADCgYJBgAAAA==.Jettadari:BAACLgAFFH8SAAITAAgJKBIXEABNAQATAAgJKBIXEABNAQAuAAQKfyYAAxMACQlsIO0WAM0CABMACQlsIO0WAM0CAAIAAQlADks1ADAAAAAA.Jettadin:BAABLgAECn8aAAIEAAgJ9yGnDwARAwAEAAgJ9yGnDwARAwABLgAFFAgJEgATACgSAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAgJEgATACgSAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAgJEgATACgSAA==.',
Ju='Jubba:BAABLgAECn8fAAIWAAkJ1xTWSAABAgAWAAkJ1xTWSAABAgAAAA==.Juderius:BAAALgADCgUJBwABLgAECgYJGgAFACgHAA==.Junk:BAABLgAECn81AAIcAAkJ9iLwAgAWAwAcAAkJ9iLwAgAWAwAAAA==.Juzu:BAAALgAFFAMJAwAAAA==.',
['Jë']='Jëks:BAACLgAFFH8gAAIKAAcJ3BdLDgD8AQAKAAcJ3BdLDgD8AQAuAAQKfykAAwoACQlhJXEDAEEDAAoACQlhJXEDAEEDAA0AAgkvDsozAGEAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJKAAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMYAAkJMSJpAwDdAgAYAAkJMSJpAwDdAgAlAAEJrQ5kkAAvAAAAAA==.Kalamiti:BAABLgAECn8sAAMFAAkJ5RiRAQBrAQAiAAcJzBPdDACOAQAFAAkJ5RiRAQBrAQAAAA==.Kallar:BAABLgAECn84AAMaAAkJRCCVBgAJAwAaAAkJRCCVBgAJAwAHAAIJUQZ/egBKAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Katween:BAAALgAECgQJBAAAAA==.Kayeera:BAABLgAECn8eAAMaAAgJdRY0HADlAQAaAAgJdRY0HADlAQAHAAQJBQUDTwCWAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAABLgAECn8cAAIWAAcJSwM6IQBwAAAWAAcJSwM6IQBwAAAAAA==.Kazarath:BAAALgAECgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgYJCwAAAA==.Keeper:BAAALgAECgUJBQABLgAFFAMJCAAdAFUVAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAEAKodAA==.Keladas:BAAALgAECgYJBgAAAA==.Kennethv:BAABLgAECn8VAAMIAAkJ1xOzAgC/AQAIAAgJvBSzAgC/AQAaAAIJvQ2YYwBRAAAAAA==.Kenze:BAAALgAECgEJAQABLgAECgQJCQAJAAAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgYJBgAAAA==.Khiell:BAACLgAFFH8LAAIRAAQJgQ8ULQD+AAARAAQJgQ8ULQD+AAAuAAQKfyIAAhEACQkmGkMbABMCABEACQkmGkMbABMCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAABLgAFFH8HAAISAAQJ0xQjCQDnAAASAAQJ0xQjCQDnAAABLgAFFAcJHwAlANobAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAAALgAECgIJAgABLgAECgkJEQAJAAAAAA==.Kitarazen:BAAALgAECgkJEQAAAA==.Kizli:BAAALgAECgUJBQABLgAECgkJXAAaAPAlAA==.',
Kn='Knghtmre:BAAALgAECgEJAQAAAA==.Knoway:BAAALgAECgMJAwAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgYJBwAAAA==.',
Kr='Kragon:BAAALgAECgkJEQAAAA==.Krátos:BAABLgAECn8oAAMSAAkJBxr7CABhAgASAAkJBxr7CABhAgARAAgJaRE/MwB+AQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIkAAgJ7BvSEQDrAQAkAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAABLgAECn8XAAMUAAYJIwZ6FQDLAAAUAAYJGwZ6FQDLAAAVAAQJaATMJwB6AAABLgAECgYJGgAFACgHAA==.Kurulak:BAABLgAECn82AAITAAkJHxOEOADkAQATAAkJHxOEOADkAQAAAA==.Kuzcotopiajr:BAAALgADCgMJAwAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.Kynigoshanta:BAAALgADCgEJAQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJEQAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn84AAIVAAkJawjjEQA8AQAVAAkJawjjEQA8AQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAYJEQAGAI8NAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAACLgAFFH8GAAIGAAIJNwbzNwBwAAAGAAIJNwbzNwBwAAAuAAQKf1oAAgYACQmHGhMcAHwCAAYACQmHGhMcAHwCAAAA.Leàf:BAABLgAECn8cAAIKAAgJMxlKHwBVAgAKAAgJMxlKHwBVAgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihpfu:BAAALgAFFAIJAwABLgAFFAQJIAARAJclAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJIAARAJclAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEwAAAA==.Lilpooch:BAAALgAFFAIJAgAAAA==.Listenlinda:BAAALgAECgMJBwABLgAECgQJCQAJAAAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAABLgAECn8WAAIOAAYJIAd4RwCLAAAOAAYJIAd4RwCLAAAAAA==.',
Lj='Lj:BAABLgAECn9TAAIgAAkJDB8MCwDcAgAgAAkJDB8MCwDcAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAABLgAECn8VAAMFAAUJUQtwBQCVAAAFAAUJUQtwBQCVAAAGAAMJYgIBGwFNAAAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMcAAMJzxc9QQAsAAAQAAIJzxcZ4ACEAAAcAAIJtA49QQAsAAABLgAFFAYJEAAfAJwUAA==.Lucinà:BAABLgAECn8+AAQEAAkJeSJlFwC3AgAEAAgJ8CNlFwC3AgAgAAkJQR+TDAC1AgADAAUJkB2vHAAwAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgkJCQAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgYJDAAAAA==.Madammìm:BAAALgAECgYJBgAAAA==.Maegan:BAABLgAECn8lAAIEAAkJMwvIDQARAQAEAAkJMwvIDQARAQAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAABLgAECn8cAAMkAAcJ0AYcBQC9AAAkAAcJjwYcBQC9AAASAAEJWgPiEQAMAAAAAA==.Magerhunter:BAAALgAECgYJCgAAAA==.Magolock:BAAALgAECgUJEgAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8aAAImAAcJ3xYsAQD3AQAmAAcJ3xYsAQD3AQAuAAQKfx8AAiYACQmrIfICALICACYACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJDwAAAA==.Makavelli:BAAALgAECgEJAQABLgAECgcJDwAJAAAAAA==.Mamajumbo:BAABLgAECn8gAAIUAAkJexwZFwCdAgAUAAkJexwZFwCdAgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAFFAMJBgAEALEdAA==.Mariag:BAAALgADCgYJCgAAAA==.Marikel:BAABLgAECn8XAAIQAAYJxgjd0wDjAAAQAAYJxgjd0wDjAAAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Meatshields:BAAALgADCgEJAQAAAA==.Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Merinda:BAAALgAECgEJAQAAAA==.Metahorfasis:BAAALgAECgUJBQAAAA==.',
Mi='Michaelken:BAABLgAECn8jAAMgAAkJDhckFgBaAgAgAAkJDhckFgBaAgAEAAEJsAd0mgEvAAAAAA==.Micromager:BAAALgAECgQJBAAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9bAAIDAAkJQCXyAABUAwADAAkJQCXyAABUAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn9HAAMDAAkJBBYpAQD1AQADAAkJ3BMpAQD1AQAEAAkJFRPTRQD1AQAAAA==.Missusgrey:BAAALgADCgkJDQABLgAECgkJXAAaAPAlAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn88AAMKAAkJhhzBEwCuAgAKAAkJhhzBEwCuAgALAAQJxgiwegB/AAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgMJBgAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAABLgAECn8UAAMNAAcJ6gubFgBWAQANAAcJ6gubFgBWAQAKAAIJowc0kABYAAAAAA==.Motako:BAABLgAECn8gAAIKAAcJRCCfFQBoAgAKAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAABLgAECn8iAAIYAAcJOx3KAQBtAQAYAAcJOx3KAQBtAQAAAA==.',
My='Mybizël:BAABLgAECn8pAAIUAAcJwR7oIABAAgAUAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgkJFQAEAAIVAA==.Myrlìfax:BAAALgAECgIJAgABLgAECgkJFQAEAAIVAA==.Mystique:BAABLgAECn8dAAICAAkJGAvCEABAAQACAAkJGAvCEABAAQAAAA==.Mythdaraghma:BAABLgAECn8WAAIBAAYJNQiyPQC/AAABAAYJNQiyPQC/AAAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8dAAInAAcJTRvmAQCHAQAnAAcJTRvmAQCHAQAuAAQKfzcAAycACQnBJWMCACQDACcACQnBJWMCACQDABQABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgQJCAAAAA==.',
Na='Naama:BAAALgADCgkJKwAAAA==.Nadaar:BAABLgAECn8bAAIXAAgJWhlaAwDyAQAXAAgJWhlaAwDyAQAAAA==.Naelih:BAABLgAECn8tAAIVAAkJ+Q1PDQCLAQAVAAkJ+Q1PDQCLAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwABLgAECggJFQAfAAwQAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Natzu:BAAALgAECgYJCwAAAA==.Naushan:BAAALgAECgMJAwAAAA==.Nazari:BAAALgAECgEJAQAAAA==.Nazeer:BAAALgADCgcJCAABLgAFFAUJDwAhAMMLAA==.Nazgrim:BAACLgAFFH8PAAMhAAUJwwu7MgDjAAAhAAUJwwu7MgDjAAAlAAEJAAB6JQAAAAAuAAQKfz4AAiEACAnIFlsvAO8BACEACAnIFlsvAO8BAAAA.',
Ne='Necronu:BAACLgAFFH8MAAIQAAMJDBdGRwCXAAAQAAMJDBdGRwCXAAAuAAQKfxgAAxAACQlQIGgXALoCABAACQkFIGgXALoCAB0ABAmuHZMRAF8BAAEuAAUUBgkmAB4A+xkA.',
Ni='Nicolletti:BAAALgADCgMJAwAAAA==.Nikkolos:BAABLgAECn8cAAIBAAgJ5gz1JQBKAQABAAgJ5gz1JQBKAQAAAA==.Ninjastax:BAAALgAECgEJAwAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAFFAEJAwABLgAFFAQJDgAQALsVAA==.',
No='Nogusta:BAACLgAFFH8ZAAIRAAYJNxxBDwCLAQARAAYJNxxBDwCLAQAuAAQKfykAAhEACQloH2kLAP8CABEACQloH2kLAP8CAAAA.Norberta:BAABLgAECn8jAAMeAAkJBAiwOABLAQAeAAkJ8AewOABLAQAjAAYJWAbxIwAIAQAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nuggetssham:BAAALgAECgIJAgAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgQJCQAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAFFAIJBAAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIKAAgJtBgvGQBNAgAKAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMKAAkJ2SPlBwD2AgAKAAkJ2SPlBwD2AgALAAcJXRiAHwAUAgABLgAFFAcJHgAhAH4bAA==.Onu:BAABLgAFFH8FAAMlAAMJGxBVFgBuAAAlAAIJlwdVFgBuAAAhAAEJ6hC9JQA1AAABLgAFFAYJJgAeAPsZAA==.Onubis:BAACLgAFFH8QAAMUAAUJriGILwBRAQAUAAUJriGILwBRAQAnAAIJ5yBLJQCnAAAuAAQKfx8ABBQACQmaHw8MAOECABQACQmOHw8MAOECABUABgnGHdk0AJcBACcAAQmkI7ZUAFsAAAEuAAUUBgkmAB4A+xkA.Onublue:BAABLgAFFH8GAAMLAAYJ8g8SFgCoAAALAAQJqQcSFgCoAAAKAAIJ4QaHNwBGAAABLgAFFAYJJgAeAPsZAA==.Onuchi:BAABLgAFFH8PAAMZAAYJghZiCADaAAAZAAUJKRNiCADaAAAfAAYJ3AQaNgDRAAABLgAFFAYJJgAeAPsZAA==.Onulight:BAABLgAFFH8MAAMEAAYJhxwiCgB2AQAEAAUJWR8iCgB2AQAgAAIJ4hXEEgCGAAABLgAFFAYJJgAeAPsZAA==.Onulite:BAABLgAFFH8HAAMHAAYJkQhUCQAIAQAHAAUJVgpUCQAIAQAIAAIJSQmJHABkAAABLgAFFAYJJgAeAPsZAA==.Onulock:BAAALgAECgYJCgABLgAFFAYJJgAeAPsZAA==.Onux:BAABLgAFFH8SAAITAAYJOBs5JACeAQATAAYJOBs5JACeAQABLgAFFAYJJgAeAPsZAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAcJFQAJAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAABLgAECn8UAAMIAAYJeBOpNABDAQAIAAYJ7hCpNABDAQAaAAQJLxPjVgDaAAAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJHwAUAHUdAA==.Pallyoop:BAABLgAECn8WAAIgAAcJMg83VgDfAAAgAAcJMg83VgDfAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgYJBwABLgAECgkJGQAQAAYdAA==.Pathaviendha:BAAALgAECgUJAgABLgAECgkJGQAQAAYdAA==.Patherion:BAAALgADCgEJAQABLgAECgkJGQAQAAYdAA==.Patheros:BAAALgAECgYJBwABLgAECgkJGQAQAAYdAA==.Patholans:BAABLgAECn8ZAAIQAAkJBh1JGwCjAgAQAAkJBh1JGwCjAgAAAA==.Pathology:BAAALgAECgMJAwABLgAECgkJGQAQAAYdAA==.Paxman:BAAALgAECgcJCgAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8iAAIcAAgJBCB6BwAQAgAcAAgJBCB6BwAQAgAuAAQKfykAAhwACQnGJSQCADEDABwACQnGJSQCADEDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAALANoPAA==.',
Ph='Phantöm:BAAALgAFFAEJAgAAAA==.Phosphate:BAABLgAECn8QAAITAAYJNxKvbgBYAQATAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAJAAAAAA==.',
Pl='Placcid:BAABLgAECn9MAAIUAAkJIh3yFgCeAgAUAAkJIh3yFgCeAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAFFAEJAQAAAA==.',
Po='Pockett:BAABLgAECn8iAAMLAAcJKBGUPwA2AQALAAcJKBGUPwA2AQANAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8QAAIIAAQJShD6KQD/AAAIAAQJShD6KQD/AAAuAAQKfzsAAggACQmYFtIDAHoBAAgACQmYFtIDAHoBAAAA.',
Pr='Prestoh:BAABLgAECn8zAAILAAkJvxFTJQC+AQALAAkJvxFTJQC+AQAAAA==.Prismclaw:BAABLgAECn9SAAIWAAkJhhV/OwAsAgAWAAkJhhV/OwAsAgAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Puk:BAAALgAECgEJAQAAAA==.Purplehaze:BAAALgAECgUJBQAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIaAAkJ3QpDMACAAQAaAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJCgAAAA==.',
Py='Pyrada:BAABLgAECn8XAAMCAAkJxRZlCQDVAQATAAgJhxUQOwDbAQACAAgJAhdlCQDVAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8jAAIUAAkJ5AhbXACQAQAUAAkJ5AhbXACQAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8iAAIaAAkJGRedFgAcAgAaAAkJGRedFgAcAgAAAA==.Quilue:BAAALgAECgEJAQAAAA==.Quintin:BAABLgAECn8kAAIjAAkJGhdPAAAbAgAjAAkJGhdPAAAbAgAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBwAAAA==.Ragetotem:BAABLgAECn8kAAMLAAYJmRwgKADSAQALAAYJmRwgKADSAQAKAAMJAAWPuABbAAAAAA==.Ragewarg:BAAALgAFFAIJAgAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIfAAgJIBimGwDbAQAfAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgUJBgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAABLgAECn8VAAIWAAkJChVWBgChAQAWAAkJChVWBgChAQABLgAECgUJCwAJAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAACLgAFFH8IAAMEAAUJJg4gFgAJAQAEAAUJJg4gFgAJAQAgAAMJAh1gOwB3AAAuAAQKfxkAAyAACAn8IFwIAOgCACAACAn8IFwIAOgCAAQABgnHHRdhAMEBAAAA.Relik:BAABLgAECn8kAAIkAAkJjwyPGgBlAQAkAAkJjwyPGgBlAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.Retpaladin:BAAALgADCgcJDAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIEAAcJFQlVwgAFAQAEAAcJFQlVwgAFAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8nAAIGAAkJsxQIOAD5AQAGAAkJsxQIOAD5AQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAABLgAECn8ZAAIKAAYJRA6WZgAoAQAKAAYJRA6WZgAoAQAAAA==.Risky:BAAALgAECgEJAQABLgAECgcJGAAhAMYEAA==.',
Ro='Robïn:BAAALgAECgIJAgABLgAECggJFQAfAAwQAA==.Rondon:BAABLgAECn88AAIUAAkJXCY2AQCHAwAUAAkJXCY2AQCHAwAAAA==.Rookdh:BAACLgAFFH8QAAMBAAYJAAbwGADaAAABAAQJUQTwGADaAAATAAYJ6wV0XgDUAAAuAAQKfykAAxMACQnkFuBcAHIBABMACAk+GOBcAHIBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8sAAIEAAkJcxXvPgAKAgAEAAkJcxXvPgAKAgAAAA==.Rotmaxxer:BAAALgAFFAQJBAAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgAECgcJDAAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMGAAgJCQyznAAEAQAGAAYJhw2znAAEAQAFAAIJFQOvRgAfAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIWAAMJCwkqjgC8AAAWAAMJCwkqjgC8AAAuAAQKfycAAhYACQn1HPM0AJ8CABYACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIbAAMJqwvqPQCvAAAbAAMJqwvqPQCvAAAuAAQKfx8AAhsACQmxFwcDABkBABsACQmxFwcDABkBAAAA.Rustedshield:BAAALgAECgIJAgABLgAFFAMJCAAbAKsLAA==.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAIOAAcJPRTbDQClAQAOAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8hAAMCAAkJyhwoBACGAgACAAkJyhwoBACGAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAABLgAFFH8IAAMQAAIJ+x7UugCzAAAQAAIJ+x7UugCzAAAdAAIJ1hWQHQCXAAAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8jAAIEAAkJvQk6igBcAQAEAAkJvQk6igBcAQAAAA==.Santaclaaws:BAACLgAFFH8TAAITAAUJVRk4PQAyAQATAAUJVRk4PQAyAQAuAAQKfzUABBMACQmkIo4UAJ4CABMACQmkIo4UAJ4CAAIAAwldFlUcALgAAAEAAgk1GY5bAHIAAAAA.Santapal:BAACLgAFFH8LAAMgAAQJ6xYLIQAWAQAgAAQJ6xYLIQAWAQAEAAEJ3gGoygA2AAAuAAQKfy4ABCAACAkcGm0oAMgBACAABwmxGm0oAMgBAAQAAgl6BVtxAUcAAAMAAglpEqFOADUAAAEuAAUUBQkTABMAVRkA.Santatumblr:BAACLgAFFH8GAAMfAAMJdh23LQAFAQAfAAMJdh23LQAFAQAZAAEJLgztQwA3AAAuAAQKfxoABB8ACAlRG0sWAGcCAB8ACAlRG0sWAGcCABkABAlyEABxAG4AABsAAQlNAzWqABoAAAEuAAUUBQkTABMAVRkA.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMHAAcJ2xEWPwAUAQAHAAYJAhIWPwAUAQAIAAYJIQxSPgATAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJOAAaAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn8/AAIKAAkJBBuJAwDhAQAKAAkJBBuJAwDhAQAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMfAAcJWhx+EwAvAgAfAAcJWhx+EwAvAgAZAAUJZwibWwCmAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.Seyren:BAABLgAFFH8MAAISAAMJTg/wCwC+AAASAAMJTg/wCwC+AAAAAA==.',
Sh='Shamiska:BAABLgAECn8UAAINAAgJKgn1HQALAQANAAgJKgn1HQALAQAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJCAABLgAECgcJGAAhAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMKAAkJiSH+BwAvAwAKAAkJiSH+BwAvAwANAAcJuwpPGwAmAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn9CAAIOAAkJ+Bh4CgA9AgAOAAkJ+Bh4CgA9AgAAAA==.Shieldee:BAABLgAECn82AAMEAAkJ1RxPJAB0AgAEAAkJ1RxPJAB0AgAgAAEJTgOwnQAiAAAAAA==.Shiftystax:BAAALgAECgEJAQAAAA==.Shlectrinell:BAABLgAECn9LAAMoAAkJ7A7xGADSAQAoAAkJ7A7xGADSAQAmAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8eAAMWAAYJACHlDgCiAQAWAAYJACHlDgCiAQApAAEJ6g/TBwA5AAAuAAQKfykABBYACQkqJXAJAC8DABYACQkqJXAJAC8DACkAAwlSGHcJALkAABcAAQnWIOsSAFYAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shortebread:BAAALgAFFAIJAgAAAA==.Shortebus:BAAALgAECgEJAQAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIoAAgJXRgLGwAoAgAoAAgJXRgLGwAoAgABLgAFFAgJIgAlAAQZAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgAECgYJCAAAAA==.Sighhi:BAAALgADCgEJAQAAAA==.Sighhy:BAABLgAECn8YAAMIAAcJ4RKwBQAsAQAIAAYJBxOwBQAsAQAHAAUJYgwWCwCeAAAAAA==.Sijth:BAACLgAFFH8NAAIEAAQJQxTgQwAjAQAEAAQJQxTgQwAjAQAuAAQKf1YAAgQACQlGIgoPAO4CAAQACQlGIgoPAO4CAAAA.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn86AAMRAAkJlh5iCQDMAgARAAkJjh5iCQDMAgAkAAYJ+BkGAgB7AQAAAA==.Simmi:BAECLgAFFH8eAAIhAAcJfhtcCQBiAgAhAAcJfhtcCQBiAgAuAAQKfykAAiEACQnBJVIGAFIDACEACQnBJVIGAFIDAAAA.Sinanestesia:BAAALgAECgIJAwAAAA==.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAAALgAECgYJEAAAAA==.Six:BAAALgAECgUJBQAAAA==.Sixte:BAAALgAECgcJCwAAAA==.Sixtea:BAABLgAECn82AAMLAAkJoR8ECQDNAgALAAkJ9B4ECQDNAgANAAEJtCJrCABmAAAAAA==.',
Sk='Skarredd:BAAALgADCgkJGQAAAA==.Skellington:BAAALgAECgEJAQAAAA==.Skepti:BAABLgAECn8uAAIUAAkJ9hqvIgBZAgAUAAkJ9hqvIgBZAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECggJEgAAAA==.',
Sm='Smeeta:BAACLgAFFH8JAAIQAAMJ4BnujwDrAAAQAAMJ4BnujwDrAAAuAAQKf2AABBAACQmHJH8PAPACABAACQkxJH8PAPACAB0ACAldI4ADAK4CABwABQlQETY5AK8AAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAACLgAFFH8SAAIgAAQJDhq1CQAPAQAgAAQJDhq1CQAPAQAuAAQKf0AAAiAACQnVF1kWAFgCACAACQnVF1kWAFgCAAAA.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQABLgAECgkJJwAcAC0TAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Sosa:BAABLgAFFH8FAAIkAAUJrxkkEAAxAQAkAAUJrxkkEAAxAQABLgAFFAgJKwAbAO0jAA==.Sosrs:BAAALgAECgQJBAABLgAECgYJCwAJAAAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAABLgAECn8XAAIWAAkJAQ9maACrAQAWAAkJAQ9maACrAQAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAABLgAECn8VAAIUAAkJcRY7CgBRAQAUAAkJcRY7CgBRAQAAAA==.Stormii:BAABLgAECn8jAAMKAAkJKA6SVABiAQAKAAgJTQySVABiAQALAAMJfhQcZQC2AAAAAA==.Stormtotem:BAAALgAECgQJBAAAAA==.Strangelock:BAAALgAECggJDwABLgAECgkJMgAQALoNAA==.Strangerdk:BAABLgAECn8yAAIQAAkJug2EXwCqAQAQAAkJug2EXwCqAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBwAAAA==.Superfatbaby:BAABLgAECn8dAAIRAAkJKhP4JwC7AQARAAkJKhP4JwC7AQAAAA==.',
Sw='Swiftstroker:BAAALgAECgEJAQABLgAECgcJDwAJAAAAAA==.Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAACLgAFFH8GAAIOAAMJGwXrLABnAAAOAAMJGwXrLABnAAAuAAQKfzIAAg4ACQkWCuIoABMBAA4ACQkWCuIoABMBAAAA.Swordfish:BAABLgAECn8fAAIjAAgJmSG9AgCKAgAjAAgJmSG9AgCKAgAAAA==.',
Sy='Syannae:BAAALgAECgEJAQAAAA==.Sybelyda:BAAALgADCgYJBgAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBwAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAITAAkJ9wfzigAKAQATAAkJ9wfzigAKAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAGAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9SAAIWAAkJ5yHiCwAaAwAWAAkJ5yHiCwAaAwAAAA==.Tadokof:BAAALgADCgkJOwAAAA==.Talanth:BAABLgAECn8XAAImAAkJ0AjXCgCGAQAmAAkJ0AjXCgCGAQAAAA==.Talya:BAAALgAECggJCAABLgAECgkJQgAOAPgYAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8hAAIEAAkJeBP4QgD+AQAEAAkJeBP4QgD+AQAAAA==.Tayon:BAABLgAECn8bAAMbAAkJEAiOAwD3AAAbAAkJEAiOAwD3AAAfAAEJTgan0QAfAAAAAA==.Tayvin:BAABLgAECn8VAAMhAAcJeBXUPwCSAQAhAAYJ6RbUPwCSAQAlAAEJOAaaGQASAAAAAA==.Tazanath:BAAALgADCgEJAgABLgADCgcJFAAJAAAAAA==.',
Te='Tempest:BAAALgAECgUJBQAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8iAAIkAAcJZB/rAgBxAQAkAAcJZB/rAgBxAQAuAAQKfygAAiQACQmCJMgCABQDACQACQmCJMgCABQDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Thanlel:BAAALgAECgMJAgAAAA==.Tharja:BAABLgAECn8bAAIWAAkJXhvvNACfAgAWAAkJXhvvNACfAgAAAA==.Theodyn:BAAALgAECgQJCgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMRAAcJ0R/RJQArAgARAAcJ0R/RJQArAgAkAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.',
Ti='Tiferet:BAABLgAECn85AAQaAAkJ+iF6BAA6AwAaAAkJ+iF6BAA6AwAHAAgJQAs+MgBSAQAIAAQJzxeqTADRAAAAAA==.Tigiw:BAAALgAECgMJBAAAAA==.Tinysunshine:BAABLgAECn8WAAIZAAgJMRwtEgAwAgAZAAgJMRwtEgAwAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgYJCwAAAA==.Tismtwo:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
Tm='Tmdragon:BAAALgAECgIJAgAAAA==.',
To='Toasted:BAAALgAECgUJBQAAAA==.Tolenkar:BAABLgAECn8fAAIUAAkJdR0lHgBxAgAUAAkJdR0lHgBxAgAAAA==.Tomato:BAACLgAFFH8ZAAMFAAcJ8Q7aBwDxAAAGAAYJ7Q+3UwAfAQAFAAQJxA3aBwDxAAAuAAQKfyMAAwUACQlpHaYFAHoCAAUACAkIHKYFAHoCAAYABQlZFwOdAAQBAAAA.Tomhanks:BAABLgAECn8VAAIEAAkJAhVbOwAWAgAEAAkJAhVbOwAWAgAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9dAAIEAAkJvRt9HwCKAgAEAAkJvRt9HwCKAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Trollfu:BAAALgAECgMJAwAAAA==.Truthslayer:BAABLgAECn8cAAMRAAkJKAmMSgAcAQARAAkJKAmMSgAcAQASAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIHAAgJxBBMIwC9AQAHAAgJxBBMIwC9AQAAAA==.',
Tt='Tteinfante:BAAALgAECggJCAAAAA==.',
Tu='Tugzug:BAAALgAECgEJAQABLgAECgcJDwAJAAAAAA==.Turdyl:BAABLgAECn8sAAIEAAkJuhHKawCXAQAEAAkJuhHKawCXAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgYJCwAAAA==.Twowheels:BAAALgAECgQJCQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8eAAQlAAcJ0hG5BgDkAAAlAAYJ2BO5BgDkAAAYAAUJcQoiNwB/AAAOAAIJgAmGcQA2AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMLAAcJWB1YLQCwAQALAAcJWB1YLQCwAQAKAAIJRhQk1QA1AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAFFAEJAQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgAECgIJBgAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgAECgEJAQAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8wAAIeAAkJrhBnLQCGAQAeAAkJrhBnLQCGAQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn84AAMbAAkJSAsJKwBfAQAbAAkJGQkJKwBfAQAZAAMJUQ4AeABhAAAAAA==.Valydrin:BAABLgAECn9aAAIaAAkJnx73CQDIAgAaAAkJnx73CQDIAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Velilla:BAAALgAECgQJBQAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8aAAQIAAQJrA1VLQDoAAAIAAQJcgxVLQDoAAAHAAMJKgtAEACWAAAaAAIJ1AwHDgCOAAAuAAQKf1oABAcACQkbH+cIAL8CAAcACQkbH+cIAL8CAAgACQmUFW0SAFACABoACQlPG4cSAEwCAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8gAAIZAAkJUgtlLQBXAQAZAAkJUgtlLQBXAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgkJIAAZAM8UAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgYJCgAAAA==.',
Wi='Wickèr:BAACLgAFFH8NAAQZAAMJ/g83DQCMAAAbAAMJpA+DOADEAAAZAAIJuBE3DQCMAAAfAAEJCQvGaAAsAAAuAAQKfzgAAxsACQkHHk0JAJ0CABsACQkHHk0JAJ0CABkAAQnIF1WNAEQAAAAA.Wieldblade:BAACLgAFFH8GAAIEAAMJNg/GMgCLAAAEAAMJNg/GMgCLAAAuAAQKfz8AAwQACQn/H84QAOACAAQACQn/H84QAOACAAMACAmIFsgPAMcBAAAA.Wigdrag:BAAALgAECgMJBQAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Woggo:BAAALgAECgEJAQAAAA==.Wolfemoon:BAABLgAECn8UAAIUAAgJwwo2egBLAQAUAAgJwwo2egBLAQAAAA==.Worganlefey:BAAALgAFFAEJAQABLgAFFAIJBgAGADcGAA==.',
Wr='Wrexd:BAABLgAECn8qAAIGAAgJChtRRADOAQAGAAgJChtRRADOAQAAAA==.',
Wu='Wunderbar:BAABLgAECn9CAAMLAAkJOyLIBAAUAwALAAkJOyLIBAAUAwAKAAkJ5xjKGQB8AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8fAAQlAAcJ2hukBAC3AQAlAAYJVBukBAC3AQAhAAEJ/AYKawBEAAAOAAEJHgobRAAkAAAuAAQKfy8AAyUACQleI/kLANgCACUACQleI/kLANgCACEAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIfAAYJcBaKOQCLAQAfAAYJcBaKOQCLAQAAAA==.',
Xa='Xanith:BAABLgAECn8tAAIRAAgJehhGIQDnAQARAAgJehhGIQDnAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAJAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgAECgUJBQAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgUJCQABLgAECgUJEgAJAAAAAA==.Yilnara:BAABLgAECn8bAAITAAkJDgdifgAjAQATAAkJDgdifgAjAQAAAA==.',
Yo='Yondo:BAAALgAECgMJAwAAAA==.',
Ys='Ysa:BAACLgAFFH8FAAIZAAMJPSMsEwAjAQAZAAMJPSMsEwAjAQAuAAQKfx4AAxkABwm4JKEQAHcCABkABwm4JKEQAHcCAB8AAQmUDZRsACkAAAAA.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgUJEgABLgAECgkJKAAaAAUhAA==.Zogula:BAEBLgAECn8oAAQaAAkJBSHiCwCpAgAaAAkJ0iDiCwCpAgAHAAQJXxZVQQAKAQAIAAEJaiOKZwBgAAAAAA==.',
Zu='Zu:BAAALgAECgcJEAAAAA==.',
Zy='Zynara:BAAALgAECgYJCAAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAInAAgJwB23DQBMAgAnAAgJwB23DQBMAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
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
