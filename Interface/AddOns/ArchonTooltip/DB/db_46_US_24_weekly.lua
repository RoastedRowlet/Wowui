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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Restoration','Mage-Frost','Mage-Arcane','Druid-Feral','Monk-Windwalker','Priest-Holy','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Paladin-Holy','Warlock-Affliction','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Druid-Balance','Rogue-Assassination','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-06-27',data={Ac='Achak:BAAALgAECgEJAQAAAA==.',
Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAACLgAFFH8HAAIBAAMJWhi9FgDtAAABAAMJWhi9FgDtAAAuAAQKf0MAAwEACQloI6wCADcDAAEACQloI6wCADcDAAIAAQlCCGk6ACEAAAAA.Adóra:BAAALgAECgEJAQAAAA==.',
Ae='Aeonis:BAAALgAECgUJEwAAAA==.Aestian:BAABLgAECn8xAAIDAAkJ5Rn9DAD1AQADAAkJ5Rn9DAD1AQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgUJBQABLgAECgUJEwAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAABLgAECn8ZAAMGAAYJKAdWJACQAAAGAAYJKAdWJACQAAAHAAMJqwDGYwEdAAAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIHAAkJMguKWwCLAQAHAAkJMguKWwCLAQAAAA==.Allanquatre:BAAALgAECgYJBgAAAA==.Alledria:BAACLgAFFH8FAAIFAAQJBwT0dADKAAAFAAQJBwT0dADKAAAuAAQKfxoAAgUACAmaElB5AHwBAAUACAmaElB5AHwBAAAA.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8hAAMIAAkJ/gwFMQBZAQAIAAgJ0A0FMQBZAQAJAAcJoxNkMQBWAQAAAA==.Altonas:BAAALgAECgMJBAAAAA==.',
Am='Amanara:BAAALgAECgcJEgAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.',
An='Ancientmonk:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.Anciientpaw:BAABLgAECn8iAAMKAAkJGyBlHQAvAgAKAAkJGyBlHQAvAgALAAUJbBUZWwDTAAAAAA==.Andramalyus:BAABLgAECn8pAAIHAAgJ3AwtcABaAQAHAAgJ3AwtcABaAQAAAA==.Andrasomnium:BAABLgAECn8bAAIMAAgJSAhaAQAUAQAMAAgJSAhaAQAUAQAAAA==.Angbar:BAABLgAECn8xAAIMAAkJkBYvCQBXAgAMAAkJkBYvCQBXAgAAAA==.Anguirus:BAABLgAECn88AAMLAAkJfAXVTgD7AAALAAkJWwXVTgD7AAANAAYJAgN+LQCNAAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJCAABLgAECgcJDwAEAAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.Anuksunàmun:BAAALgAECgkJBgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAFFAMJBgAOABsFAA==.Appynoxusrog:BAABLgAECn8cAAIPAAYJuhguBQCcAQAPAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAIQAAMJsRNqngDWAAAQAAMJsRNqngDWAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAACLgAFFH8GAAIRAAMJOg2CFQBqAAARAAMJOg2CFQBqAAAuAAQKfzMAAxEACQkcHZwQAHMCABEACQkcHZwQAHMCABIAAQnMB9REAC8AAAAA.Arcadiann:BAABLgAECn8XAAIRAAcJ3xYyLQCdAQARAAcJ3xYyLQCdAQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJCwAAAA==.Arextheelder:BAAALgAFFAEJAQAAAA==.Aridas:BAABLgAECn8dAAMTAAgJJBhuMwAsAgATAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAASAAcaAA==.Arikdeath:BAACLgAFFH8GAAIUAAMJeAyeGADeAAAUAAMJeAyeGADeAAAuAAQKfykAAxQACQmVFwotACgCABQABwlvGAotACgCABUABwlODN0VAAoBAAAA.Armorscales:BAACLgAFFH8VAAIHAAcJFxi4LACSAQAHAAcJFxi4LACSAQAuAAQKfy0AAgcACQm/IVgQAPcCAAcACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixx:BAAALgAECgQJDQAAAA==.Arntraz:BAAALgADCgkJTgAAAA==.Aryel:BAAALgADCgkJDwAAAA==.Arçadia:BAAALgAECgMJBgAAAA==.',
As='Asaya:BAAALgADCgIJAgABLgAFFAUJDQAWAMMLAA==.Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Asprika:BAABLgAFFH8IAAIIAAQJqwi0CQC8AAAIAAQJqwi0CQC8AAAAAA==.Astayoni:BAAALgADCgEJAQAAAA==.Astrine:BAACLgAFFH8VAAMXAAcJLhWhPgBzAQAXAAYJyBahPgBzAQAYAAEJKw0aAgBRAAAuAAQKfysAAhcACQlJIAYiAOsCABcACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIZAAkJ/xl6BgCSAgAZAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8wAAIaAAkJPAeYOAAfAQAaAAkJPAeYOAAfAQAAAA==.Aumer:BAAALgAECgEJAQAAAA==.Auranda:BAAALgAECgMJAwAAAA==.',
Av='Avalonia:BAAALgAECgEJAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8dAAIVAAgJJRuWCQDLAQAVAAgJJRuWCQDLAQAuAAQKfykAAhUACQkGIOIDAIUCABUACQkGIOIDAIUCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAABLgAECn8WAAILAAkJkgcUBwCvAAALAAkJkgcUBwCvAAAAAA==.',
Ba='Backpedal:BAABLgAECn8fAAIaAAkJ8RTWAAADAgAaAAkJ8RTWAAADAgAAAA==.Badankhadonk:BAACLgAFFH8UAAIKAAUJaCKMEgDSAQAKAAUJaCKMEgDSAQAuAAQKfy0AAgoACQl7JVICAF8DAAoACQl7JVICAF8DAAAA.Balen:BAABLgAECn80AAIDAAkJqhYoCwAWAgADAAkJqhYoCwAWAgAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8zAAIbAAkJJiIIBgAVAwAbAAkJJiIIBgAVAwAAAA==.Beliice:BAAALgAECgUJBQABLgAECgkJMwAbACYiAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8RAAMHAAUJ+yGIIgDDAQAHAAUJ+yGIIgDDAQAGAAEJ6hDxJwBFAAAuAAQKfysAAgcACQkcJSEMABkDAAcACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJUAAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8dAAIGAAkJBRcCBQAnAgAGAAkJBRcCBQAnAgAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8nAAIBAAkJqRUgFADxAQABAAkJqRUgFADxAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAFFAEJAQAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAITAAcJKSFgKQBcAgATAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAbAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAKAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8mAAIPAAkJuQdiDwATAQAPAAkJuQdiDwATAQAAAA==.Bonemarrow:BAABLgAECn8bAAIFAAUJ9BLG1ADtAAAFAAUJ9BLG1ADtAAAAAA==.Bournx:BAAALgAECgQJBAAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8LAAMBAAQJ2wwkGADgAAABAAQJuQUkGADgAAACAAIJWRTGDAB9AAAuAAQKf14ABAIACQnrG+kEAGUCAAIACQnrG+kEAGUCAAEAAwlkD9lYAFwAABMAAQmlAcf0ABsAAAAA.Brakeable:BAAALgAECgUJBQAAAA==.Braké:BAABLgAECn8eAAIDAAkJaB1lBQCbAgADAAkJaB1lBQCbAgAAAA==.Brandrale:BAAALgAECgcJCQAAAA==.Breakthrough:BAABLgAECn8lAAIKAAYJOCPbHgBXAgAKAAYJOCPbHgBXAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIcAAcJDyWVDABtAgAcAAcJDyWVDABtAgABLgAECgkJNQAdAPYiAA==.Brewsli:BAAALgADCgIJAgABLgAECgkJJwAeABQMAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQATAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Broombolt:BAAALgAECgIJAgAAAA==.Brownington:BAACLgAFFH8GAAMZAAMJJRJIFQCGAAAZAAIJFA1IFQCGAAAOAAEJSBz0NgBJAAAuAAQKfxkAAw4ABwlWJAkJAFsCAA4ABwlWJAkJAFsCABkAAQmjCrFXACsAAAAA.Bruhilda:BAABLgAECn8dAAIXAAkJ7hLuSwD3AQAXAAkJ7hLuSwD3AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brãke:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8fAAMGAAgJEhyvCAAMAQAHAAcJWRlfKwCZAQAGAAQJTx+vCAAMAQAuAAQKfyoAAwYACQkPJL4FAA4CAAYABgkoJb4FAA4CAAcABQkeI4JzAFMBAAAA.',
Bu='Buc:BAAALgAECgEJAQAAAA==.Bufferfish:BAABLgAECn82AAIfAAkJUQxkLwB7AQAfAAkJUQxkLwB7AQAAAA==.',
Ca='Calinnea:BAABLgAECn8VAAMgAAgJDBCjMwCoAQAgAAgJDBCjMwCoAQAaAAIJDgOFiAAnAAAAAA==.Canadaispimp:BAAALgAECgIJAgAAAA==.Cantheartitz:BAABLgAECn8WAAIXAAUJPxmBnQCbAQAXAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8rAAIaAAkJJSKTBAAOAwAaAAkJJSKTBAAOAwAAAA==.',
Ce='Celira:BAAALgADCgMJAwAAAA==.Celthol:BAABLgAECn8nAAITAAYJnxhHBABFAQATAAYJnxhHBABFAQAAAA==.',
Ch='Chelraani:BAABLgAECn9AAAIFAAkJMSRfBgA+AwAFAAkJMSRfBgA+AwAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIaAAkJ8CTAAgBtAwAaAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgADCgcJEAAAAA==.',
Ci='Cigar:BAAALgAECgQJCQABLgAFFAgJHgAQADsdAA==.Cinderat:BAAALgADCgEJAQAAAA==.Cinderburn:BAAALgADCgYJBgABLgAECgkJDQAEAAAAAA==.',
Cl='Clambumper:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAIRAAYJBBYHDwCNAQARAAYJBBYHDwCNAQAuAAQKfxUAAhEACAkMGcscAGcCABEACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8QAAMgAAYJmhQJKAAuAQAgAAUJPxIJKAAuAQAaAAQJPw4NDQBYAAAuAAQKfx8ABBoACQmbFmIeAOUBABoABwlYHGIeAOUBACAACAniEYomAH4BABwAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgkJDQAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAAALgAECgcJEAAAAA==.Conjredcukee:BAABLgAECn8WAAIXAAcJ7ANF5wDQAAAXAAcJ7ANF5wDQAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIIAAcJyh2aEQBxAgAIAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMKAAgJBBpXKQAYAgAKAAgJBBpXKQAYAgALAAMJoBfKagCnAAAAAA==.',
Cr='Crackstalion:BAAALgAECgEJAQAAAA==.Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAABLgAECn8cAAIHAAgJ8Bp9KQA1AgAHAAgJ8Bp9KQA1AgAAAA==.',
Cu='Cukeemonster:BAAALgAECgEJAQAAAA==.',
Cy='Cylina:BAAALgADCgcJCAABLgADCgcJFAAEAAAAAA==.Cyliya:BAAALgADCgIJAwABLgADCgcJFAAEAAAAAA==.Cylore:BAAALgADCgcJBgABLgADCgcJFAAEAAAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyrax:BAAALgADCgYJCQAAAA==.Cyther:BAACLgAFFH8jAAIRAAgJ8xw6BQAaAgARAAgJ8xw6BQAaAgAuAAQKfykAAhEACQmXIqwHAC4DABEACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAITAAkJ4BzDHAClAgATAAkJ4BzDHAClAgAAAA==.',
Da='Dakk:BAABLgAECn9KAAIQAAkJOiNnCgAcAwAQAAkJOiNnCgAcAwAAAA==.Dangbor:BAAALgAECgEJAQABLgAECgkJMQAMAJAWAA==.Daraghor:BAABLgAECn8bAAIOAAkJoCIMAgAbAwAOAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJCQAAAA==.Darkenstormy:BAABLgAECn8WAAMFAAkJPhI6DADjAAAFAAcJ6hU6DADjAAAhAAQJlw3CCQBbAAAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.',
De='Deadlight:BAABLgAECn8xAAMQAAkJzhJzUwDKAQAQAAkJOhJzUwDKAQAeAAEJYBKBOQA3AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgAFFAEJAQAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8yAAIRAAkJMSTrAwAoAwARAAkJMSTrAwAoAwABLgAFFAMJBgAeAJQSAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAITAAkJAROqSgCmAQATAAkJAROqSgCmAQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAILAAgJ/xVSIgDSAQALAAgJ/xVSIgDSAQAAAA==.Demonthorx:BAAALgAECgUJBQAAAA==.Demonx:BAABLgAECn8zAAIQAAkJ+x1cGgCoAgAQAAkJ+x1cGgCoAgAAAA==.Dennis:BAAALgAECgYJCQABLgAECgkJFQAFAAIVAA==.Derpsicle:BAAALgAECgEJAQAAAA==.Desolation:BAABLgAECn9SAAIYAAkJ+iUnAABsAwAYAAkJ+iUnAABsAwAAAA==.Despia:BAABLgAECn87AAMbAAkJZCS2AQCbAwAbAAkJZCS2AQCbAwAIAAYJzxH4MgBOAQAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAABLgAFFAcJGgAMAIkcAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8yAAIWAAkJRxPqJgAZAgAWAAkJRxPqJgAZAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8OAAIHAAMJDQa2KQBrAAAHAAMJDQa2KQBrAAAuAAQKf0EAAwcACAlCEKhfAIEBAAcACAlCEKhfAIEBACIABgnyBUMQACoBAAAA.Dontormenta:BAAALgAECgcJDgAAAA==.Donut:BAAALgADCgIJAgABLgAECggJHwAjAJkhAA==.Dotdaddy:BAAALgAECgQJBwABLgAECggJFQAgAAwQAA==.Doughy:BAAALgAECgYJBgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8mAAIfAAYJ+xmjGAChAQAfAAYJ+xmjGAChAQAuAAQKfyIAAx8ACQk4H4AMAJMCAB8ACQk4H4AMAJMCAAwAAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8cAAITAAcJKBBVbABLAQATAAcJKBBVbABLAQAAAA==.Dragoncurry:BAABLgAECn8WAAIMAAYJIgZGKACpAAAMAAYJIgZGKACpAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgkJFQAFAAIVAA==.Draktyr:BAACLgAFFH8GAAIRAAMJtRZeFgCyAAARAAMJtRZeFgCyAAAuAAQKfyQAAhEACQn2HncJABYDABEACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAWADkZAA==.Drlovely:BAAALgADCgkJCQAAAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.Druadh:BAAALgADCgYJBgABLgAECggJFQAKAP8ZAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMVAAgJ6xbDMQCpAQAVAAcJ6xXDMQCpAQAUAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgUJBwAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn9BAAIQAAkJ+SHbDQD9AgAQAAkJ+SHbDQD9AgAAAA==.Elosong:BAAALgAECgEJAQAAAA==.Elvea:BAABLgAECn8kAAMfAAgJjRr1GQAHAgAfAAgJjRr1GQAHAgAjAAEJ9QoWQgArAAABLgAFFAYJGAAkADMUAA==.',
Em='Emeralddemon:BAAALgAECgYJDQAAAA==.Emeraldshade:BAAALgADCgcJEwABLgAECgYJDQAEAAAAAA==.Emeråld:BAAALgAECgUJBwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAKAP8ZAA==.',
Eo='Eolyndin:BAAALgADCgQJBAAAAA==.',
Er='Eregon:BAAALgADCgYJBgAAAA==.Ereithelda:BAACLgAFFH8lAAMgAAgJhBVkFwDCAQAgAAgJhBVkFwDCAQAaAAIJOxWFLgCNAAAuAAQKfyYAAiAACAm2IhcHAOkCACAACAm2IhcHAOkCAAAA.Ericka:BAAALgAECgUJBwAAAA==.Erowid:BAABLgAFFH8IAAIJAAUJTRX5BgBgAQAJAAUJTRX5BgBgAQABLgAFFAYJJgAfAPsZAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Eu='Euclid:BAAALgAECgEJAQAAAA==.',
Ev='Evildeadd:BAAALgAECgIJAgABLgAECgcJDwAEAAAAAA==.Evox:BAABLgAECn8ZAAMLAAkJdxfkAQCeAQALAAkJdxfkAQCeAQAKAAEJEBRl0wA3AAAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgAECgQJCgAAAA==.Fann:BAABLgAECn8gAAIWAAkJgAT2awDwAAAWAAkJgAT2awDwAAAAAA==.Fauna:BAAALgAECgYJCAAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgMJAwAAAA==.',
Fe='Fel:BAAALgAECgUJBgAAAA==.Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQATAAMJNRx2pwDVAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8NAAIXAAUJfxRLdgDvAAAXAAUJfxRLdgDvAAAuAAQKfyQAAhcACQnjITMdAK0CABcACQnjITMdAK0CAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8ZAAIlAAYJAhOgEgASAQAlAAYJAhOgEgASAQAuAAQKfy0AAiUACQkjHJkLAFQCACUACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAYJGQAlAAITAA==.Flaktop:BAAALgAFFAEJAQABLgAFFAYJGQAlAAITAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8nAAMeAAkJFAy3FAA1AQAeAAkJ4gu3FAA1AQAQAAYJgQkA1QDiAAAAAA==.Force:BAABLgAECn8jAAQeAAkJygqwEgBOAQAeAAgJnwuwEgBOAQAQAAUJEATFFQGRAAAdAAEJ+wTIZwAaAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Forsaken:BAACLgAFFH8GAAIeAAMJlBJUBwCzAAAeAAMJlBJUBwCzAAAuAAQKfxcAAx4ABwlfIZoAAO4BAB4ABgk2IZoAAO4BAB0ABQn6H6sCABoBAAAA.Fourdragon:BAAALgADCgQJBAABLgAECggJFwALACQXAA==.Fouris:BAABLgAECn8XAAILAAgJJBfnKgCbAQALAAgJJBfnKgCbAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAIUAAUJZhkzBABdAQAUAAUJZhkzBABdAQAuAAQKfyMAAhQACQm6Im0PAMACABQACQm6Im0PAMACAAAA.Froline:BAAALgAECgYJEgAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8gAAIdAAkJQxxqCwBYAgAdAAkJQxxqCwBYAgAAAA==.Fryea:BAAALgAECgEJAQAAAA==.',
Ft='Ftwiamtank:BAABLgAECn8ZAAIlAAYJrw9bKADxAAAlAAYJrw9bKADxAAABLgAECgkJLQANAIIMAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.Furah:BAAALgAECgEJAwAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8gAAIXAAgJaRQeKADWAQAXAAgJaRQeKADWAQAuAAQKfysAAhcACQm0HW8sAGcCABcACQm0HW8sAGcCAAAA.Gardon:BAAALgAECgYJCgAAAA==.Gaurdinn:BAABLgAECn8uAAQfAAgJMBMiMgBtAQAfAAgJrhIiMgBtAQAjAAYJfxAREQD5AAAMAAIJagI/PAAyAAABLgAECgkJJQALAKgYAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickk:BAAALgAFFAEJAQAAAA==.Generickmonk:BAACLgAFFH8YAAIaAAUJox14DgBLAQAaAAUJox14DgBLAQAuAAQKfy8AAhoACQnyIsQFAPMCABoACQnyIsQFAPMCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAwAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAABLgAECn8VAAIDAAYJ+Ah9KwCxAAADAAYJ+Ah9KwCxAAAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAHAHcUAA==.Gonwean:BAAALgAECgEJAQABLgAFFAcJFQAUAO0WAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIcAAIJahEGSgB3AAAcAAIJahEGSgB3AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAFFAIJAgAAAA==.Grimjob:BAAALgADCgIJAgAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgUJBwAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJBAAAAA==.',
Gu='Guino:BAAALgAECgcJDwAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.Guinohunter:BAAALgADCgQJBAAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hahla:BAAALgADCgEJAQAAAA==.Hail:BAAALgAECgMJAwAAAA==.Hamncheeks:BAAALgAECgEJAQAAAA==.Hamnqueso:BAAALgAECgMJAwAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgAECgkJDQAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAAAAA==.Hazis:BAABLgAECn8rAAIdAAkJEyEbCACkAgAdAAkJEyEbCACkAgAAAA==.',
Hi='Highflyr:BAAALgAECgEJAQAAAA==.Hinala:BAAALgAFFAIJAgAAAA==.Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.Hivemind:BAAALgAECgQJCAABLgAFFAQJCwAFAHETAA==.',
Ho='Holy:BAACLgAFFH8ZAAMDAAcJvgpFCAD0AAADAAYJ/QhFCAD0AAAhAAEJtRfTEQBYAAAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA/qDQCeAAADAAQJzA/qDQCeAAAuAAQKfywAAgMACAkHIFEKACUCAAMACAkHIFEKACUCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgAECggJCAAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9QAAIbAAkJqBP/GAADAgAbAAkJqBP/GAADAgAAAA==.Holyshock:BAACLgAFFH8iAAIFAAgJkRrPEgDWAQAFAAgJkRrPEgDWAQAuAAQKfykAAgUACQlkJcoIACMDAAUACQlkJcoIACMDAAAA.Holystax:BAAALgAECgEJBAAAAA==.Honeybutter:BAACLgAFFH8hAAMSAAYJByaOBQAXAgASAAYJ9SWOBQAXAgARAAUJ2SUzCgC9AQAuAAQKfzsAAxIACQkzJgkBAGgDABIACQkzJgkBAGgDABEABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9OAAIUAAkJ6yNABgAwAwAUAAkJ6yNABgAwAwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIXAAgJER7kOACSAgAXAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJDgAAAA==.',
In='Inanitas:BAAALgAECgEJAQAAAA==.Ineffectual:BAABLgAECn8fAAIKAAgJvBMeMgC9AQAKAAgJvBMeMgC9AQAAAA==.',
Ir='Irion:BAAALgADCgMJAwAAAA==.Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgAECgQJBAAAAA==.Jadefleur:BAAALgAECgEJAQAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJDwAAAA==.Janewayy:BAABLgAECn8yAAITAAkJGA13YgBjAQATAAkJGA13YgBjAQAAAA==.Jazmean:BAABLgAECn8UAAIJAAcJsw4fLQBwAQAJAAcJsw4fLQBwAQAAAA==.',
Jb='Jbournz:BAAALgAECgMJAwAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJIAAKANwXAA==.Jemma:BAABLgAECn8vAAIGAAkJ6hSDBgD4AQAGAAkJ6hSDBgD4AQAAAA==.Jerikos:BAAALgADCgYJBgAAAA==.Jettadari:BAACLgAFFH8SAAITAAgJKBIXEABNAQATAAgJKBIXEABNAQAuAAQKfyYAAxMACQlsIO0WAM0CABMACQlsIO0WAM0CAAIAAQlADks1ADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAgJEgATACgSAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAgJEgATACgSAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAgJEgATACgSAA==.',
Ju='Jubba:BAABLgAECn8fAAIXAAkJ1xTWSAABAgAXAAkJ1xTWSAABAgAAAA==.Juderius:BAAALgADCgQJBAABLgAECgYJGQAGACgHAA==.Junk:BAABLgAECn81AAIdAAkJ9iLwAgAWAwAdAAkJ9iLwAgAWAwAAAA==.',
['Jë']='Jëks:BAACLgAFFH8gAAIKAAcJ3BdLDgD8AQAKAAcJ3BdLDgD8AQAuAAQKfykAAwoACQlhJXEDAEEDAAoACQlhJXEDAEEDAA0AAgkvDsozAGEAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJKAAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMZAAkJMSJpAwDdAgAZAAkJMSJpAwDdAgAmAAEJrQ5kkAAvAAAAAA==.Kalamiti:BAABLgAECn8sAAMGAAkJ5RgIAQBuAQAiAAcJzBPdDACOAQAGAAkJ5RgIAQBuAQAAAA==.Kallar:BAABLgAECn84AAMbAAkJRCCVBgAJAwAbAAkJRCCVBgAJAwAIAAIJUQZ/egBKAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Katween:BAAALgAECgQJBAAAAA==.Kayeera:BAABLgAECn8eAAMbAAgJdRY0HADlAQAbAAgJdRY0HADlAQAIAAQJBQUDTwCWAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAABLgAECn8cAAIXAAcJSwNxFwBzAAAXAAcJSwNxFwBzAAAAAA==.Kazarath:BAAALgAECgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgYJCwAAAA==.Keeper:BAAALgAECgUJBQABLgAFFAMJBgAeAJQSAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAFAKodAA==.Keladas:BAAALgAECgYJBgAAAA==.Kennethv:BAABLgAECn8VAAMJAAkJ2BOxAQDEAQAJAAgJvRSxAQDEAQAbAAIJvQ2YYwBRAAAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgYJBgAAAA==.Khiell:BAACLgAFFH8LAAIRAAQJgQ8ULQD+AAARAAQJgQ8ULQD+AAAuAAQKfyIAAhEACQkmGkMbABMCABEACQkmGkMbABMCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAFFAQJBAABLgAFFAcJGgAmAMcWAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAAALgAECgIJAgABLgAECgkJEQAEAAAAAA==.Kitarazen:BAAALgAECgkJEQAAAA==.Kizli:BAAALgAECgUJBQAAAA==.',
Kn='Knghtmre:BAAALgAECgEJAQAAAA==.Knoway:BAAALgAECgMJAwAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgYJBwAAAA==.',
Kr='Kragon:BAAALgAECgkJEQAAAA==.Krátos:BAABLgAECn8oAAMSAAkJBxr7CABhAgASAAkJBxr7CABhAgARAAgJaRE/MwB+AQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIlAAgJ7BvSEQDrAQAlAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAABLgAECn8VAAMUAAYJIwYSDgDbAAAUAAYJGwYSDgDbAAAVAAQJaATMJwB6AAABLgAECgYJGQAGACgHAA==.Kurulak:BAABLgAECn82AAITAAkJHxOEOADkAQATAAkJHxOEOADkAQAAAA==.Kuzcotopiajr:BAAALgADCgMJAwAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.Kynigoshanta:BAAALgADCgEJAQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJEQAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn84AAIVAAkJawjjEQA8AQAVAAkJawjjEQA8AQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAYJEQAHAI8NAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAACLgAFFH8FAAIHAAIJNwalKABxAAAHAAIJNwalKABxAAAuAAQKf1oAAgcACQmHGhMcAHwCAAcACQmHGhMcAHwCAAAA.Leàf:BAABLgAECn8cAAIKAAgJMxlKHwBVAgAKAAgJMxlKHwBVAgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihpfu:BAAALgAFFAIJAwABLgAFFAQJIAARAJclAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJIAARAJclAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEwAAAA==.Lilpooch:BAAALgAFFAIJAgAAAA==.Listenlinda:BAAALgAECgMJBwAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAABLgAECn8WAAIOAAYJIAd4RwCLAAAOAAYJIAd4RwCLAAAAAA==.',
Lj='Lj:BAABLgAECn9TAAIhAAkJDB8MCwDcAgAhAAkJDB8MCwDcAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgUJEAAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMdAAMJzxc9QQAsAAAQAAIJzxcZ4ACEAAAdAAIJtA49QQAsAAABLgAFFAYJEAAgAJoUAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSJlFwC3AgAFAAgJ8CNlFwC3AgAhAAkJQR+TDAC1AgADAAUJkB2vHAAwAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgkJCQAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgYJDAAAAA==.Madammìm:BAAALgAECgYJBgAAAA==.Maegan:BAABLgAECn8cAAIFAAkJdAkewAAIAQAFAAkJdAkewAAIAQAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAABLgAECn8VAAMlAAYJigdMBgBhAAAlAAUJlghMBgBhAAASAAEJWgMIDQAMAAAAAA==.Magerhunter:BAAALgAECgYJCAAAAA==.Magolock:BAAALgAECgUJEgAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8aAAInAAcJ3xYsAQD3AQAnAAcJ3xYsAQD3AQAuAAQKfx8AAicACQmrIfICALICACcACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJDwAAAA==.Makavelli:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Mamajumbo:BAABLgAECn8gAAIUAAkJexwZFwCdAgAUAAkJexwZFwCdAgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAFFAMJBgAFALMdAA==.Mariag:BAAALgADCgQJBAAAAA==.Marikel:BAABLgAECn8XAAIQAAYJxgjd0wDjAAAQAAYJxgjd0wDjAAAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Merinda:BAAALgAECgEJAQAAAA==.Metahorfasis:BAAALgAECgUJBQAAAA==.',
Mi='Michaelken:BAABLgAECn8jAAMhAAkJDhckFgBaAgAhAAkJDhckFgBaAgAFAAEJsAd0mgEvAAAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9bAAIDAAkJQCXyAABUAwADAAkJQCXyAABUAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn9HAAMDAAkJBBasAAACAgADAAkJ3hOsAAACAgAFAAkJFRPTRQD1AQAAAA==.Missusgrey:BAAALgADCgkJCQABLgAECgUJBQAEAAAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn88AAMKAAkJhhzBEwCuAgAKAAkJhhzBEwCuAgALAAQJxgiwegB/AAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgMJBQAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAABLgAECn8UAAMNAAcJ6gubFgBWAQANAAcJ6gubFgBWAQAKAAIJowc0kABYAAAAAA==.Motako:BAABLgAECn8gAAIKAAcJRCCfFQBoAgAKAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAABLgAECn8ZAAIZAAcJxBb+EQCbAQAZAAcJxBb+EQCbAQAAAA==.',
My='Mybizël:BAABLgAECn8pAAIUAAcJwR7oIABAAgAUAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgkJFQAFAAIVAA==.Mystique:BAABLgAECn8dAAICAAkJWgvPAQDhAAACAAkJWgvPAQDhAAAAAA==.Mythdaraghma:BAABLgAECn8WAAIBAAYJNQiyPQC/AAABAAYJNQiyPQC/AAAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8YAAIoAAcJ8hn7BgCeAQAoAAcJ8hn7BgCeAQAuAAQKfzcAAygACQnBJWMCACQDACgACQnBJWMCACQDABQABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgQJBwAAAA==.',
Na='Naama:BAAALgADCgkJKwAAAA==.Nadaar:BAABLgAECn8bAAIYAAgJWhlaAwDyAQAYAAgJWhlaAwDyAQAAAA==.Naelih:BAABLgAECn8tAAIVAAkJ+Q1PDQCLAQAVAAkJ+Q1PDQCLAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwABLgAECggJFQAgAAwQAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Natzu:BAAALgAECgYJCwAAAA==.Nazeer:BAAALgADCgcJCAABLgAFFAUJDQAWAMMLAA==.Nazgrim:BAACLgAFFH8NAAMWAAUJwwt/DQCoAAAWAAUJwwt/DQCoAAAmAAEJAAC9HAAAAAAuAAQKfz4AAhYACAnIFlsvAO8BABYACAnIFlsvAO8BAAAA.',
Ne='Necronu:BAACLgAFFH8MAAIQAAMJDBdLMgCZAAAQAAMJDBdLMgCZAAAuAAQKfxgAAxAACQlQIGgXALoCABAACQkFIGgXALoCAB4ABAmuHZMRAF8BAAEuAAUUBgkmAB8A+xkA.',
Ni='Nikkolos:BAABLgAECn8cAAIBAAgJ5gz1JQBKAQABAAgJ5gz1JQBKAQAAAA==.Ninjastax:BAAALgAECgEJAwAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAFFAEJAwABLgAFFAQJDgAQALsVAA==.',
No='Nogusta:BAACLgAFFH8ZAAIRAAYJNxxBDwCLAQARAAYJNxxBDwCLAQAuAAQKfykAAhEACQloH2kLAP8CABEACQloH2kLAP8CAAAA.Norberta:BAABLgAECn8jAAMfAAkJBAiwOABLAQAfAAkJ8AewOABLAQAjAAYJWAbxIwAIAQAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nuggetssham:BAAALgAECgEJAQAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgQJBQAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAFFAIJAwAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIKAAgJtBgvGQBNAgAKAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMKAAkJ2SPlBwD2AgAKAAkJ2SPlBwD2AgALAAcJXRiAHwAUAgABLgAFFAcJHgAWAH4bAA==.Onubis:BAACLgAFFH8QAAMUAAUJriGILwBRAQAUAAUJriGILwBRAQAoAAIJ5yBLJQCnAAAuAAQKfx8ABBQACQmaHw8MAOECABQACQmOHw8MAOECABUABgnGHdk0AJcBACgAAQmkI7ZUAFsAAAEuAAUUBgkmAB8A+xkA.Onublue:BAABLgAFFH8GAAMLAAYJ8g9DDwCuAAALAAQJqQdDDwCuAAAKAAIJ4QaDJwBOAAABLgAFFAYJJgAfAPsZAA==.Onuchi:BAABLgAFFH8PAAMaAAYJghbNBQDcAAAaAAUJKRPNBQDcAAAgAAYJ3AQaNgDRAAABLgAFFAYJJgAfAPsZAA==.Onulight:BAABLgAFFH8HAAMFAAUJGhsZDgAUAQAFAAQJYx4ZDgAUAQAhAAIJ4hWCDQCJAAABLgAFFAYJJgAfAPsZAA==.Onulite:BAABLgAFFH8HAAMIAAYJkQhaBgAJAQAIAAUJVgpaBgAJAQAJAAIJSQn+FABkAAABLgAFFAYJJgAfAPsZAA==.Onulock:BAAALgAECgYJCgABLgAFFAYJJgAfAPsZAA==.Onux:BAABLgAFFH8SAAITAAYJOBs5JACeAQATAAYJOBs5JACeAQABLgAFFAYJJgAfAPsZAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAcJFQAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAABLgAECn8UAAMJAAYJeBOpNABDAQAJAAYJ7hCpNABDAQAbAAQJLxPjVgDaAAAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJHwAUAHUdAA==.Pallyoop:BAABLgAECn8WAAIhAAcJMg83VgDfAAAhAAcJMg83VgDfAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgYJBwABLgAECgkJGQAQAAYdAA==.Pathaviendha:BAAALgAECgUJAgABLgAECgkJGQAQAAYdAA==.Patherion:BAAALgADCgEJAQABLgAECgkJGQAQAAYdAA==.Patheros:BAAALgADCgQJAwABLgAECgkJGQAQAAYdAA==.Patholans:BAABLgAECn8ZAAIQAAkJBh1JGwCjAgAQAAkJBh1JGwCjAgAAAA==.Pathology:BAAALgAECgMJAwABLgAECgkJGQAQAAYdAA==.Paxman:BAAALgAECgYJCQAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8iAAIdAAgJBCB6BwAQAgAdAAgJBCB6BwAQAgAuAAQKfykAAh0ACQnGJSQCADEDAB0ACQnGJSQCADEDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAALANoPAA==.',
Ph='Phantöm:BAAALgAFFAEJAgAAAA==.Phosphate:BAABLgAECn8QAAITAAYJNxKvbgBYAQATAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Pl='Placcid:BAABLgAECn9MAAIUAAkJIh3yFgCeAgAUAAkJIh3yFgCeAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8iAAMLAAcJKBGUPwA2AQALAAcJKBGUPwA2AQANAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8QAAIJAAQJShD6KQD/AAAJAAQJShD6KQD/AAAuAAQKfzsAAgkACQmYFnoCAHcBAAkACQmYFnoCAHcBAAAA.',
Pr='Prestoh:BAABLgAECn8zAAILAAkJvxFTJQC+AQALAAkJvxFTJQC+AQAAAA==.Prismclaw:BAABLgAECn9SAAIXAAkJhhV/OwAsAgAXAAkJhhV/OwAsAgAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Puk:BAAALgAECgEJAQAAAA==.Purplehaze:BAAALgAECgUJBQAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIbAAkJ3QpDMACAAQAbAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJCgAAAA==.',
Py='Pyrada:BAABLgAECn8XAAMCAAkJxRZlCQDVAQATAAgJhxUQOwDbAQACAAgJAhdlCQDVAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8jAAIUAAkJ5AhbXACQAQAUAAkJ5AhbXACQAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8iAAIbAAkJGRedFgAcAgAbAAkJGRedFgAcAgAAAA==.Quintin:BAABLgAECn8fAAIjAAkJKxVpAACQAQAjAAkJKxVpAACQAQAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBgAAAA==.Ragetotem:BAABLgAECn8kAAMLAAYJmRwgKADSAQALAAYJmRwgKADSAQAKAAMJAAWPuABbAAAAAA==.Ragewarg:BAAALgAFFAIJAgAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIgAAgJIBimGwDbAQAgAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgIJAgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAABLgAECn8VAAIXAAkJMxUTBACwAQAXAAkJMxUTBACwAQABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMhAAgJ/CBcCADoAgAhAAgJ/CBcCADoAgAFAAYJxx0XYQDBAQAAAA==.Relik:BAABLgAECn8kAAIlAAkJjwyPGgBlAQAlAAkJjwyPGgBlAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.Retpaladin:BAAALgADCgYJBgAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQlVwgAFAQAFAAcJFQlVwgAFAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8nAAIHAAkJsxQIOAD5AQAHAAkJsxQIOAD5AQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAABLgAECn8ZAAIKAAYJRA6WZgAoAQAKAAYJRA6WZgAoAQAAAA==.Risky:BAAALgAECgEJAQABLgAECgcJGAAWAMYEAA==.',
Ro='Robïn:BAAALgAECgIJAgABLgAECggJFQAgAAwQAA==.Rondon:BAABLgAECn88AAIUAAkJXCY2AQCHAwAUAAkJXCY2AQCHAwAAAA==.Rookdh:BAACLgAFFH8PAAMBAAYJAAbwGADaAAABAAQJUQTwGADaAAATAAYJ6wV0XgDUAAAuAAQKfykAAxMACQnkFuBcAHIBABMACAk+GOBcAHIBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8sAAIFAAkJcxXvPgAKAgAFAAkJcxXvPgAKAgAAAA==.Rotmaxxer:BAAALgAFFAQJBAAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgAECgcJBwAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMHAAgJCQyznAAEAQAHAAYJhw2znAAEAQAGAAIJFQOvRgAfAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIXAAMJCwkqjgC8AAAXAAMJCwkqjgC8AAAuAAQKfycAAhcACQn1HPM0AJ8CABcACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIcAAMJqwvqPQCvAAAcAAMJqwvqPQCvAAAuAAQKfx8AAhwACQl+Fw0CACQBABwACQl+Fw0CACQBAAAA.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAIOAAcJPRTbDQClAQAOAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8hAAMCAAkJyhwoBACGAgACAAkJyhwoBACGAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAABLgAFFH8IAAMQAAIJ+x7UugCzAAAQAAIJ+x7UugCzAAAeAAIJ1hWQHQCXAAAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8jAAIFAAkJvQk6igBcAQAFAAkJvQk6igBcAQAAAA==.Santaclaaws:BAACLgAFFH8TAAITAAUJrBk4PQAyAQATAAUJrBk4PQAyAQAuAAQKfzUABBMACQmkIo4UAJ4CABMACQmkIo4UAJ4CAAIAAwldFlUcALgAAAEAAgk1GY5bAHIAAAAA.Santapal:BAACLgAFFH8LAAMhAAQJ6xYLIQAWAQAhAAQJ6xYLIQAWAQAFAAEJ3gGoygA2AAAuAAQKfy4ABCEACAkeGm0oAMgBACEABwmzGm0oAMgBAAUAAgl6BVtxAUcAAAMAAglpEqFOADUAAAEuAAUUBQkTABMArBkA.Santatumblr:BAACLgAFFH8GAAMgAAMJdh23LQAFAQAgAAMJdh23LQAFAQAaAAEJLgztQwA3AAAuAAQKfxoABCAACAlRG0sWAGcCACAACAlRG0sWAGcCABoABAlyEABxAG4AABwAAQlNAzWqABoAAAEuAAUUBQkTABMArBkA.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMIAAcJ2xEWPwAUAQAIAAYJAhIWPwAUAQAJAAYJIQxSPgATAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJOAAbAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn85AAIKAAkJBRmHGQB+AgAKAAkJBRmHGQB+AgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMgAAcJWhx+EwAvAgAgAAcJWhx+EwAvAgAaAAUJZwibWwCmAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.Seyren:BAABLgAFFH8MAAISAAMJTg9zCAC+AAASAAMJTg9zCAC+AAAAAA==.',
Sh='Shamiska:BAAALgAECggJEwAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJCAABLgAECgcJGAAWAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMKAAkJiSH+BwAvAwAKAAkJiSH+BwAvAwANAAcJuwpPGwAmAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn9CAAIOAAkJ+Bh4CgA9AgAOAAkJ+Bh4CgA9AgAAAA==.Shieldee:BAABLgAECn82AAMFAAkJ1RxPJAB0AgAFAAkJ1RxPJAB0AgAhAAEJTgOwnQAiAAAAAA==.Shiftystax:BAAALgAECgEJAQAAAA==.Shlectrinell:BAABLgAECn9LAAMkAAkJ7A7xGADSAQAkAAkJ7A7xGADSAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8eAAMXAAYJACHlDgCiAQAXAAYJACHlDgCiAQApAAEJ6g/TBwA5AAAuAAQKfykABBcACQkqJXAJAC8DABcACQkqJXAJAC8DACkAAwlSGHcJALkAABgAAQnWIOsSAFYAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shortebread:BAAALgAFFAIJAgAAAA==.Shortebus:BAAALgAECgEJAQAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIkAAgJXRgLGwAoAgAkAAgJXRgLGwAoAgABLgAFFAgJIgAmAAQZAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgAECgYJBwAAAA==.Sighhy:BAABLgAECn8VAAMJAAcJ4RLVAwAoAQAJAAYJBxPVAwAoAQAIAAMJqwUJewBJAAAAAA==.Sijth:BAACLgAFFH8LAAIFAAQJcRPgQwAjAQAFAAQJcRPgQwAjAQAuAAQKf1YAAgUACQlGIgoPAO4CAAUACQlGIgoPAO4CAAAA.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn80AAIRAAkJjh5iCQDMAgARAAkJjh5iCQDMAgAAAA==.Simmi:BAECLgAFFH8eAAIWAAcJfhtcCQBiAgAWAAcJfhtcCQBiAgAuAAQKfykAAhYACQnBJVIGAFIDABYACQnBJVIGAFIDAAAA.Sinanestesia:BAAALgAECgIJAgAAAA==.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAAALgAECgYJCwAAAA==.Sixte:BAAALgAECgcJCwAAAA==.Sixtea:BAABLgAECn81AAILAAkJ9B4ECQDNAgALAAkJ9B4ECQDNAgAAAA==.',
Sk='Skarredd:BAAALgADCgkJGQAAAA==.Skellington:BAAALgAECgEJAQAAAA==.Skepti:BAABLgAECn8tAAIUAAkJ7BqvIgBZAgAUAAkJ7BqvIgBZAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECggJEgAAAA==.',
Sm='Smeeta:BAACLgAFFH8JAAIQAAMJ4BnujwDrAAAQAAMJ4BnujwDrAAAuAAQKf2AABBAACQmHJH8PAPACABAACQkxJH8PAPACAB4ACAldI4ADAK4CAB0ABQlQETY5AK8AAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAACLgAFFH8RAAIhAAQJDhqABgAWAQAhAAQJDhqABgAWAQAuAAQKf0AAAiEACQnVF1kWAFgCACEACQnVF1kWAFgCAAAA.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Sosa:BAABLgAFFH8FAAIlAAUJrxkkEAAxAQAlAAUJrxkkEAAxAQABLgAFFAgJKQAcAO0jAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAABLgAECn8WAAIXAAkJUA1maACrAQAXAAkJUA1maACrAQAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAABLgAECn8VAAIUAAkJbhYJBwBXAQAUAAkJbhYJBwBXAQAAAA==.Stormii:BAABLgAECn8jAAMKAAkJKA6SVABiAQAKAAgJTQySVABiAQALAAMJfhQcZQC2AAAAAA==.Stormtotem:BAAALgAECgMJAwAAAA==.Strangelock:BAAALgAECggJDwABLgAECgkJMgAQALoNAA==.Strangerdk:BAABLgAECn8yAAIQAAkJug2EXwCqAQAQAAkJug2EXwCqAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBwAAAA==.Superfatbaby:BAABLgAECn8dAAIRAAkJKhP4JwC7AQARAAkJKhP4JwC7AQAAAA==.',
Sw='Swiftstroker:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAACLgAFFH8GAAIOAAMJGwXrLABnAAAOAAMJGwXrLABnAAAuAAQKfzIAAg4ACQkWCuIoABMBAA4ACQkWCuIoABMBAAAA.Swordfish:BAABLgAECn8fAAIjAAgJmSG9AgCKAgAjAAgJmSG9AgCKAgAAAA==.',
Sy='Syannae:BAAALgAECgEJAQAAAA==.Sybelyda:BAAALgADCgYJBgAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBwAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAITAAkJ9wfzigAKAQATAAkJ9wfzigAKAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAHAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9SAAIXAAkJ5yHiCwAaAwAXAAkJ5yHiCwAaAwAAAA==.Tadokof:BAAALgADCgkJOwAAAA==.Talanth:BAABLgAECn8XAAInAAkJ0AjXCgCGAQAnAAkJ0AjXCgCGAQAAAA==.Talya:BAAALgAECggJCAABLgAECgkJQgAOAPgYAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8hAAIFAAkJeBP4QgD+AQAFAAkJeBP4QgD+AQAAAA==.Tayon:BAABLgAECn8bAAMcAAkJ9QdIAgAOAQAcAAkJ9QdIAgAOAQAgAAEJTgan0QAfAAAAAA==.Tayvin:BAABLgAECn8UAAIWAAYJ6RbUPwCSAQAWAAYJ6RbUPwCSAQAAAA==.Tazanath:BAAALgADCgEJAgABLgADCgcJFAAEAAAAAA==.',
Te='Tempest:BAAALgAECgUJBQAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8iAAIlAAcJZB/rAgBxAQAlAAcJZB/rAgBxAQAuAAQKfygAAiUACQmCJMgCABQDACUACQmCJMgCABQDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Thanlel:BAAALgAECgMJAgAAAA==.Tharja:BAABLgAECn8bAAIXAAkJXhvvNACfAgAXAAkJXhvvNACfAgAAAA==.Theodyn:BAAALgAECgQJCgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMRAAcJ0R/RJQArAgARAAcJ0R/RJQArAgAlAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.',
Ti='Tiferet:BAABLgAECn84AAQbAAkJ+iF6BAA6AwAbAAkJ+iF6BAA6AwAIAAgJQAs+MgBSAQAJAAQJzxeqTADRAAAAAA==.Tigiw:BAAALgAECgMJBAAAAA==.Tinysunshine:BAABLgAECn8WAAIaAAgJMRwtEgAwAgAaAAgJMRwtEgAwAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgYJCQAAAA==.Tismtwo:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgAECgUJBQAAAA==.Tolenkar:BAABLgAECn8fAAIUAAkJdR0lHgBxAgAUAAkJdR0lHgBxAgAAAA==.Tomato:BAACLgAFFH8ZAAMGAAcJ8Q7aBwDxAAAHAAYJ7Q+3UwAfAQAGAAQJxA3aBwDxAAAuAAQKfyMAAwYACQlpHaYFAHoCAAYACAkIHKYFAHoCAAcABQlZFwOdAAQBAAAA.Tomhanks:BAABLgAECn8VAAIFAAkJAhVbOwAWAgAFAAkJAhVbOwAWAgAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9dAAIFAAkJvRt9HwCKAgAFAAkJvRt9HwCKAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Trollfu:BAAALgAECgMJAwAAAA==.Truthslayer:BAABLgAECn8cAAMRAAkJKAmMSgAcAQARAAkJKAmMSgAcAQASAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIIAAgJxBBMIwC9AQAIAAgJxBBMIwC9AQAAAA==.',
Tt='Tteinfante:BAAALgAECggJCAAAAA==.',
Tu='Tugzug:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Turdyl:BAABLgAECn8sAAIFAAkJuhHKawCXAQAFAAkJuhHKawCXAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgYJCwAAAA==.Twowheels:BAAALgAECgQJBgAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8YAAQmAAcJrg3sRQD1AAAmAAYJ/w7sRQD1AAAZAAUJjAciNwB/AAAOAAIJgAmGcQA2AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMLAAcJWB1YLQCwAQALAAcJWB1YLQCwAQAKAAIJRhQk1QA1AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAFFAEJAQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgAECgIJBgAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgAECgEJAQAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8wAAIfAAkJjxBnLQCGAQAfAAkJjxBnLQCGAQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn84AAMcAAkJSAsJKwBfAQAcAAkJGQkJKwBfAQAaAAMJUQ4AeABhAAAAAA==.Valydrin:BAABLgAECn9aAAIbAAkJnx73CQDIAgAbAAkJnx73CQDIAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Velilla:BAAALgAECgQJBQAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8YAAQJAAQJrA1VLQDoAAAJAAQJcgxVLQDoAAAIAAMJKgtwCwCXAAAbAAIJ1AwHDgCOAAAuAAQKf1gABAgACQkbH+cIAL8CAAgACQkbH+cIAL8CAAkACQmUFW0SAFACABsACQlPG4cSAEwCAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8gAAIaAAkJUgtlLQBXAQAaAAkJUgtlLQBXAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgkJHwAaAPEUAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgYJCgAAAA==.',
Wi='Wickèr:BAACLgAFFH8LAAMcAAMJpA+DOADEAAAcAAMJpA+DOADEAAAgAAEJCQvGaAAsAAAuAAQKfzgAAxwACQkHHk0JAJ0CABwACQkHHk0JAJ0CABoAAQnIF1WNAEQAAAAA.Wieldblade:BAACLgAFFH8GAAIFAAMJNg+OIgCVAAAFAAMJNg+OIgCVAAAuAAQKfz8AAwUACQn/H84QAOACAAUACQn/H84QAOACAAMACAmIFsgPAMcBAAAA.Wigdrag:BAAALgAECgMJAwAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Woggo:BAAALgAECgEJAQAAAA==.Wolfemoon:BAABLgAECn8UAAIUAAgJwwo2egBLAQAUAAgJwwo2egBLAQAAAA==.Worganlefey:BAAALgAFFAEJAQABLgAFFAIJBQAHADcGAA==.',
Wr='Wrexd:BAABLgAECn8qAAIHAAgJChtRRADOAQAHAAgJChtRRADOAQAAAA==.',
Wu='Wunderbar:BAABLgAECn9CAAMLAAkJOyLIBAAUAwALAAkJOyLIBAAUAwAKAAkJ5xjKGQB8AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8aAAQmAAcJxxYIHQAzAQAmAAYJPBUIHQAzAQAWAAEJ/AYKawBEAAAOAAEJHgobRAAkAAAuAAQKfy8AAyYACQleI/kLANgCACYACQleI/kLANgCABYAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIgAAYJcBaKOQCLAQAgAAYJcBaKOQCLAQAAAA==.',
Xa='Xanith:BAABLgAECn8tAAIRAAgJehhGIQDnAQARAAgJehhGIQDnAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgUJCQABLgAECgUJEgAEAAAAAA==.Yilnara:BAABLgAECn8bAAITAAkJDgdifgAjAQATAAkJDgdifgAjAQAAAA==.',
Yo='Yondo:BAAALgAECgMJAwAAAA==.',
Ys='Ysa:BAACLgAFFH8FAAIaAAMJQSMsEwAjAQAaAAMJQSMsEwAjAQAuAAQKfx4AAxoABwm4JKEQAHcCABoABwm4JKEQAHcCACAAAQmUDZRsACkAAAAA.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgUJEgABLgAECgkJKAAbAAUhAA==.Zogula:BAEBLgAECn8oAAQbAAkJBSHiCwCpAgAbAAkJ0iDiCwCpAgAIAAQJXxZVQQAKAQAJAAEJaiOKZwBgAAAAAA==.',
Zu='Zu:BAAALgAECgcJEAABLgAECgkJDQAEAAAAAA==.',
Zy='Zynara:BAAALgAECgYJCAAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAIoAAgJwB23DQBMAgAoAAgJwB23DQBMAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECggJFQAgAAwQAA==.',
['Ða']='Ðante:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðelusion:BAAALgAECgMJCAAAAA==.',
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
