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

local lookup = {'Mage-Frost','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Survival','Paladin-Retribution','DemonHunter-Devourer','Monk-Brewmaster','Warrior-Arms','DeathKnight-Blood','Rogue-Subtlety','Monk-Windwalker','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Restoration','Druid-Guardian','Warrior-Fury','Rogue-Assassination','Shaman-Enhancement','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Druid-Balance','Paladin-Protection','Paladin-Holy','Priest-Holy','Druid-Feral','Shaman-Restoration','Priest-Shadow','DemonHunter-Havoc','Mage-Fire','Mage-Arcane','Priest-Discipline','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Aderai:BAAALgADCgYJCgAAAA==.',
Ae='Aeliong:BAAALgAECgEJAQAAAA==.Aendronys:BAAALgADCgQJAwAAAA==.',
Af='Afterparty:BAABLgAECn8VAAIBAAgJ2BIe5QArAQABAAgJ2BIe5QArAQAAAA==.',
Ag='Aguni:BAABLgAECn8cAAQCAAgJfx4zLADqAQACAAgJ/x0zLADqAQADAAIJXRlnFgCZAAAEAAMJIh4AAAAAAAABLgAFFAQJCAAFAKgUAA==.',
Ah='Ahmin:BAAALgADCgYJBgAAAA==.',
Ai='Aiura:BAAALgAECgcJEQAAAA==.',
Aj='Ajunlucky:BAACLgAFFH8RAAMGAAQJmBwmEwBdAQAGAAQJmBwmEwBdAQAHAAEJuAMSIwBLAAAuAAQKfzIAAgYACQkpItcGAO8CAAYACQkpItcGAO8CAAAA.',
Al='Alagondar:BAABLgAECn8aAAIIAAgJtw1TXwBoAQAIAAgJtw1TXwBoAQAAAA==.Alakard:BAABLgAECn8gAAIJAAgJhRoeIgADAgAJAAgJhRoeIgADAgAAAA==.Alberich:BAAALgAECgcJDwAAAA==.Alexari:BAAALgADCgcJCwAAAA==.Alexthejoker:BAAALgADCgQJAwAAAA==.Alody:BAAALgAECgEJAQAAAA==.Althenath:BAAALgADCgMJBAAAAA==.',
Am='Amalica:BAABLgAECn8aAAIBAAUJaiGffABBAQABAAUJaiGffABBAQAAAA==.Amenadiel:BAAALgAECgcJEQAAAA==.Amuyal:BAAALgADCgYJBgAAAA==.',
An='Anaphylactic:BAAALgAECgYJBQAAAA==.Andrea:BAABLgAECn8bAAIKAAYJVhd4IgBXAQAKAAYJVhd4IgBXAQAAAA==.Angelline:BAAALgAECgUJDgABLgAFFAMJDQALAD4lAA==.Antimagi:BAAALgADCgkJCQAAAA==.',
Ap='Apheelia:BAAALgAECgQJDAAAAA==.Appypie:BAACLgAFFH8GAAIMAAMJzwUlHACVAAAMAAMJzwUlHACVAAAuAAQKfy0AAgwACQmpEXQRAJ8BAAwACQmpEXQRAJ8BAAAA.',
Ar='Arale:BAAALgAECgEJAQAAAA==.Aramala:BAAALgAECgIJAwAAAA==.Arkveld:BAACLgAFFH8FAAINAAMJuB9RFAAkAQANAAMJuB9RFAAkAQAuAAQKfzIAAg0ACAlfJRcEALwCAA0ACAlfJRcEALwCAAAA.Arthasia:BAAALgAECgcJBwABLgAFFAgJIAADAMwmAA==.',
As='Ashurasenku:BAABLgAECn8WAAIJAAgJBgcPaAACAQAJAAgJBgcPaAACAQAAAA==.Asten:BAAALgAECgUJCAAAAA==.',
At='Athair:BAABLgAECn8fAAIOAAYJMx/VFgCtAQAOAAYJMx/VFgCtAQAAAA==.Athineana:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgUJBQABLgAFFAIJAwAPAAAAAA==.Aulken:BAAALgADCgEJAQAAAA==.',
Ay='Aylinn:BAABLgAECn8iAAMQAAkJaRzqAwC4AgAQAAkJaRzqAwC4AgARAAEJVQYadwAjAAAAAA==.Aylira:BAAALgAECgQJCAAAAA==.Aymonzo:BAABLgAECn8eAAMJAAgJ7RfCRgBjAQAJAAgJ7RfCRgBjAQASAAEJFBTFIwA5AAAAAA==.',
Az='Azem:BAAALgADCgkJDAAAAA==.',
Ba='Badlóck:BAAALgAECgcJBgAAAA==.Baharrar:BAACLgAFFH8PAAITAAQJSh/gEQBvAQATAAQJSh/gEQBvAQAuAAQKfysAAxMACQkYIhEIAPsCABMACQkYIhEIAPsCABQAAQn9Eos+ADgAAAAA.Barofslovr:BAAALgADCgcJBwABLgAECgYJFQAIAA0fAA==.Barrylowmana:BAAALgADCgcJBwAAAA==.Bartendresse:BAAALgAECgEJAQAAAA==.Bastrasz:BAAALgAECgcJCwAAAA==.Batar:BAAALgADCgYJBgAAAA==.',
Be='Bearalas:BAACLgAFFH8OAAICAAUJ+RRDNwAgAQACAAUJ+RRDNwAgAQAuAAQKfxUAAgIACQmqG/YYAL8CAAIACQmqG/YYAL8CAAAA.Bearis:BAAALgADCgMJAwAAAA==.Beekin:BAAALgAECgUJCwAAAA==.Beeyah:BAABLgAECn8jAAIGAAgJUiGsFABjAgAGAAgJUiGsFABjAgAAAA==.Beldion:BAAALgADCgUJBQABLgAECgYJIQAKALYVAA==.Bellator:BAAALgADCgMJAwAAAA==.Bellona:BAAALgADCgQJBAAAAA==.Bernarnold:BAABLgAECn8XAAIVAAcJ/h3pGADYAQAVAAcJ/h3pGADYAQAAAA==.Bettyspready:BAABLgAECn8XAAIWAAgJLw/HBwCLAQAWAAgJLw/HBwCLAQAAAA==.',
Bi='Bigmanooshki:BAAALgADCgQJBAAAAA==.Bigoysters:BAAALgAFFAEJAQAAAA==.Bigpoppapump:BAABLgAECn8jAAIXAAgJ8CSZAQDlAgAXAAgJ8CSZAQDlAgAAAA==.Bigthumbb:BAAALgAECgEJAQAAAA==.Bigvikingg:BAAALgAECgcJBAAAAA==.Bikook:BAAALgADCgIJAgABLgAECgkJHwAQAOUPAA==.Binnyi:BAABLgAECn8sAAMYAAkJ6Q7/BADTAQAYAAkJ6Q7/BADTAQARAAYJogbuPAD6AAAAAA==.Biwwy:BAAALgAECgEJAQAAAA==.',
Bl='Blabidil:BAAALgADCgQJBAAAAA==.Blackfoot:BAABLgAECn8XAAIZAAkJpBWxGwCuAQAZAAkJpBWxGwCuAQAAAA==.Blackyeshua:BAACLgAFFH8QAAIRAAQJCBONGQAsAQARAAQJCBONGQAsAQAuAAQKfzQAAhEACQk/HyUKAHQCABEACQk/HyUKAHQCAAAA.Blastphemy:BAAALgADCgYJBgAAAA==.Blindpov:BAAALgADCggJCQAAAA==.',
Bo='Boanhead:BAAALgADCgIJAgAAAA==.Bogorline:BAAALgADCgkJDwAAAA==.Boomtiloom:BAAALgAECgYJDAAAAA==.Borgastraz:BAABLgAECn8VAAQYAAYJhA/dDgDYAAAYAAUJzQ3dDgDYAAARAAQJDgztRwC6AAAQAAIJEAymJwBgAAAAAA==.Boru:BAAALgADCgcJBwAAAA==.Boshin:BAAALgAECgEJAQAAAA==.Boshintime:BAAALgAECgMJAwAAAA==.Bouberry:BAABLgAECn8XAAIEAAYJWx5DFQCgAQAEAAYJWx5DFQCgAQAAAA==.',
Br='Brewstoes:BAAALgADCgQJBQAAAA==.Bricksquadx:BAAALgAECgMJBQAAAA==.Brink:BAAALgADCgMJAwAAAA==.Broki:BAAALgAECgEJAgAAAA==.Brugnir:BAAALgAECgYJBgABLgAECgUJBwAPAAAAAA==.Bruwen:BAAALgAFFAIJAwAAAA==.',
Bu='Bubblegruff:BAAALgADCgkJGQAAAA==.Bubbleohsevn:BAAALgAECgcJEgAAAA==.Bubblesaurus:BAABLgAECn8nAAMRAAgJshj+GAC+AQARAAgJ4Rf+GAC+AQAYAAYJrg96IQAgAQAAAA==.Bum:BAAALgADCgkJCQAAAA==.Burlan:BAAALgAECgYJEgAAAA==.',
['Bé']='Béåst:BAAALgAECgYJDwAAAA==.',
['Bë']='Bërshton:BAAALgAECgYJCAAAAA==.',
Ca='Cakeshake:BAABLgAECn8aAAIGAAYJOBM8YgAkAQAGAAYJOBM8YgAkAQAAAA==.Caleris:BAABLgAECn8kAAIaAAkJDhokCAAzAgAaAAkJDhokCAAzAgAAAA==.Camelnuckle:BAABLgAECn8kAAIZAAkJpRUGGwC0AQAZAAkJpRUGGwC0AQAAAA==.Car:BAAALgADCgIJAgAAAA==.Cattle:BAABLgAECn8cAAIbAAkJeRQFEwDqAQAbAAkJeRQFEwDqAQAAAA==.',
Ch='Chaosglaive:BAAALgAECgcJEgAAAA==.Chaostorms:BAABLgAECn8UAAMcAAcJ9guuGwDjAAAcAAcJ9guuGwDjAAAdAAIJJQLDbAA6AAAAAA==.Chess:BAAALgAECgYJCwAAAA==.Chickenhydra:BAAALgADCgYJBgAAAA==.Chlorophil:BAAALgADCgYJBwAAAA==.Choochew:BAAALgAECgEJAgAAAA==.Chowlock:BAABLgAECn8oAAQEAAkJdiPaAgDTAgAEAAcJniPaAgDTAgADAAYJViIABAAAAgACAAUJmSJOawCMAQAAAA==.Chowmantwo:BAAALgADCgEJAQAAAA==.Chronical:BAAALgADCgcJBwAAAA==.',
Cl='Classicmonk:BAAALgAECgQJBQAAAA==.Clawsofpeace:BAAALgADCgkJDQABLgAECggJIQAeAGEOAA==.Cleverboi:BAAALgAECgIJAgAAAA==.',
Co='Coldflesh:BAAALgAECgkJAQAAAA==.Conlord:BAABLgAECn8XAAIFAAYJ5SPSNgDdAQAFAAYJ5SPSNgDdAQAAAA==.Constancia:BAAALgAECgUJDQAAAA==.',
Cr='Crackahjack:BAAALgAECgEJAQAAAA==.Craigor:BAAALgAECgEJAQABLgAECggJFQAaAK4YAA==.Croppydust:BAAALgADCgcJDAAAAA==.Cryden:BAAALgADCgYJCQAAAA==.',
Cy='Cylicmylic:BAAALgAECgQJBAAAAA==.',
Cz='Czark:BAAALgAECgQJBAAAAA==.',
Da='Dalamaar:BAAALgADCgEJAQAAAA==.Dampundies:BAAALgAECgEJAQAAAA==.Dandey:BAAALgAECgYJBwAAAA==.Dangerdoom:BAAALgAECgIJAwABLgAECggJJgABAPAYAA==.Dantee:BAABLgAECn8wAAISAAkJyB4RAgCpAgASAAkJyB4RAgCpAgAAAA==.Daps:BAAALgADCgcJCgAAAA==.Darkfoxgrime:BAABLgAECn8kAAIOAAkJeBC8FQC3AQAOAAkJeBC8FQC3AQAAAA==.Dartini:BAAALgAECgIJAgAAAA==.Datsmywife:BAABLgAECn8ZAAMfAAcJTRCMEQCVAQAfAAcJTRCMEQCVAQAbAAUJYAUaSgCNAAAAAA==.Davis:BAABLgAECn8ZAAIFAAkJ+wuNQwCxAQAFAAkJ+wuNQwCxAQAAAA==.Dayquill:BAAALgAECgEJAQAAAA==.Daytimes:BAAALgAECgIJAgAAAA==.Daytknight:BAAALgAECgMJAwAAAA==.',
De='Deadvikingg:BAAALgAFFAMJAwAAAA==.Deadwix:BAAALgADCgMJAwAAAA==.Deebss:BAAALgAECgMJAwAAAA==.Degradation:BAAALgAECgEJBQAAAA==.Degru:BAAALgAECgYJDgABLgAECgkJEQAPAAAAAA==.Delaire:BAABLgAECn8XAAIcAAcJjh3xCADsAQAcAAcJjh3xCADsAQAAAA==.Demenhunta:BAAALgAECgMJAgAAAA==.Demonkow:BAACLgAFFH8QAAICAAUJnhgoFwA3AQACAAUJnhgoFwA3AQAuAAQKfyMAAwIACQlRIh8fACwCAAIACAkXIh8fACwCAAQABAkPIgcbAHUBAAAA.Dereksama:BAAALgADCgQJBAAAAA==.Destrah:BAAALgADCgUJBQAAAA==.Deviiarrc:BAACLgAFFH8UAAIQAAQJLiI4CwCDAQAQAAQJLiI4CwCDAQAuAAQKfykAAhAACQlMJCADADUDABAACQlMJCADADUDAAAA.',
Di='Dikan:BAAALgADCgEJAQAAAA==.Dinosaurman:BAAALgAECgQJBAAAAA==.Disintegrate:BAAALgAECgcJBwAAAA==.',
Do='Doova:BAAALgADCgYJCgAAAA==.Dorik:BAAALgADCgYJBgAAAA==.',
Dr='Dracar:BAACLgAFFH8GAAIIAAMJlQvSQgDlAAAIAAMJlQvSQgDlAAAuAAQKfyEAAggACAmYFVVDALMBAAgACAmYFVVDALMBAAAA.Drackian:BAAALgAECgQJBAAAAA==.Dragondyne:BAAALgAECggJCAABLgAFFAMJBgAKAIQLAA==.Drdurun:BAAALgADCgYJBwAAAA==.Drekavak:BAAALgAECgYJCAAAAA==.Drekfur:BAAALgAECgQJBAAAAA==.Drmmrfist:BAABLgAECn8vAAIKAAkJERZSEAD9AQAKAAkJERZSEAD9AQAAAA==.Druideca:BAAALgAECgYJDgAAAA==.Druidyne:BAAALgAECgkJCQABLgAFFAMJBgAKAIQLAA==.',
Du='Dustra:BAAALgAECgEJAQAAAA==.',
Dw='Dwippietiggs:BAABLgAECn8vAAIIAAkJwiAzDADOAgAIAAkJwiAzDADOAgAAAA==.',
Ea='Earthfeather:BAAALgAECgEJAQAAAA==.',
Ec='Echoesonmute:BAAALgADCgEJAQAAAA==.',
Ed='Edhochuli:BAAALgADCgUJBQABLgAECgcJDQAPAAAAAA==.',
Ee='Eetee:BAABLgAECn8kAAQZAAgJchOEKwC7AQAZAAgJchOEKwC7AQAXAAQJNQvHHwDVAAAgAAUJIw1YagCtAAAAAA==.',
Ek='Ekitten:BAAALgAECgYJCwABLgAFFAUJDwATAAAjAA==.',
El='Elandria:BAABLgAECn8XAAIHAAcJsQHuNgCbAAAHAAcJsQHuNgCbAAAAAA==.Elohym:BAAALgADCgUJBQAAAA==.Elsea:BAAALgAECgQJDQAAAA==.',
Em='Emberstone:BAAALgAECgEJAQAAAA==.Emerys:BAAALgAECgYJBgAAAA==.Emotions:BAABLgAECn8VAAIJAAgJWhKUSQBaAQAJAAgJWhKUSQBaAQAAAA==.',
Ep='Epicdragon:BAAALgAECgYJCgAAAA==.',
Eq='Equesmortis:BAAALgAECgYJDgAAAA==.',
Er='Erös:BAAALgAECgUJDwAAAA==.',
Et='Etatoned:BAAALgAECgYJEgAAAA==.Etengaged:BAAALgAECgYJDQAAAA==.Ethavoc:BAAALgAECgIJAgAAAA==.Ethuln:BAAALgADCgIJAgAAAA==.',
Eu='Eurdice:BAAALgADCgIJAgAAAA==.',
Ev='Evo:BAAALgAECgMJAwABLgAECggJLAABAMQdAA==.Evrae:BAABLgAECn8eAAINAAgJPxesEADUAQANAAgJPxesEADUAQAAAA==.',
Ex='Extragrace:BAABLgAECn8dAAIBAAYJGgXitADdAAABAAYJGgXitADdAAAAAA==.',
Fa='Faithshand:BAABLgAECn8sAAMeAAkJwgvrIQBrAQAeAAkJwgvrIQBrAQAhAAUJewPPPwC4AAAAAA==.Fallenbow:BAAALgAECgYJCAAAAA==.Fappa:BAACLgAFFH8GAAICAAMJZQKsYgCuAAACAAMJZQKsYgCuAAAuAAQKfzgAAgIACQnfFgkjABgCAAIACQnfFgkjABgCAAAA.',
Fe='Featherstone:BAAALgADCgIJAwAAAA==.Feelzdope:BAAALgADCgQJBAAAAA==.Feio:BAABLgAECn8rAAIiAAkJlx8EBQCpAgAiAAkJlx8EBQCpAgAAAA==.Felfirez:BAAALgAECgEJAQAAAA==.Fellhock:BAAALgAECgMJAwAAAA==.Felydrak:BAABLgAECn8aAAQYAAgJ1hSJDQABAgAYAAgJshOJDQABAgAQAAMJowbsJQBsAAARAAIJZgw5XgBeAAAAAA==.Fergilicious:BAAALgAECgYJEQABLgAECgYJFQAIAA0fAA==.',
Fi='Finkenator:BAACLgAFFH8XAAIBAAcJHRsQCQAYAgABAAcJHRsQCQAYAgAuAAQKfyYAAgEACQl/I70KAG4DAAEACQl/I70KAG4DAAAA.Finkler:BAACLgAFFH8IAAIBAAQJjRvJLQBaAQABAAQJjRvJLQBaAQAuAAQKfywAAgEACQnqIsIOAFEDAAEACQnqIsIOAFEDAAEuAAUUBwkXAAEAHRsA.Firedanny:BAAALgAECgcJDgAAAA==.',
Fl='Flameshock:BAABLgAECn8uAAQjAAkJbBJCAgDlAQAjAAkJ4BBCAgDlAQAkAAQJKhA2BwD1AAABAAQJdwOaJwGyAAAAAA==.Flippybippi:BAAALgAECgEJAQAAAA==.Flixur:BAACLgAFFH8XAAIBAAQJtRBaQAA6AQABAAQJtRBaQAA6AQAuAAQKfx8AAgEABwnnHxs/AN0BAAEABwnnHxs/AN0BAAAA.Fluffyduck:BAAALgAECgYJBgAAAA==.Flyzikman:BAAALgADCgEJAQAAAA==.',
Fo='Forestdump:BAAALgADCgYJBgABLgAECgcJDQAPAAAAAA==.Forté:BAAALgADCgMJAwAAAA==.',
Fr='Freek:BAAALgAECgEJAwABLgAECgUJBwAPAAAAAA==.Freewillie:BAAALgAECgEJAwABLgAECgQJBgAPAAAAAA==.Friarmj:BAABLgAECn8wAAIlAAkJuQ2GFADgAQAlAAkJuQ2GFADgAQAAAA==.Frigidbeach:BAAALgAECgYJDwAAAA==.Frozeny:BAAALgADCgcJDQAAAA==.',
Fu='Furrita:BAAALgADCgcJBwAAAA==.',
Ga='Galazeth:BAABLgAECn8cAAMRAAgJhx7DDwAiAgARAAgJhx7DDwAiAgAYAAYJMA1XHQBEAQABLgAFFAQJCAAFAKgUAA==.Gamthor:BAABLgAECn8VAAIaAAgJrhggIQA2AQAaAAgJrhggIQA2AQAAAA==.Gaten:BAAALgAECgYJBgAAAA==.',
Ge='Germz:BAAALgAECgkJBwAAAA==.',
Gi='Gildeddash:BAABLgAECn8VAAIIAAYJkAabswDLAAAIAAYJkAabswDLAAAAAA==.Giudice:BAAALgAECgIJAgAAAA==.',
Gl='Glengoyne:BAAALgAECgQJDQAAAA==.Globoe:BAACLgAFFH8cAAMYAAgJcx5FAAD/AQAYAAUJeyRFAAD/AQARAAcJShplCQDFAQAuAAQKfzMAAxgACQksJkIAAMsDABgACQnhJUIAAMsDABEACAmCInsNAJ4CAAAA.Gluggther:BAAALgAECgQJBAAAAA==.',
Go='Goru:BAAALgADCgYJBgAAAA==.',
Gr='Grahz:BAAALgAECgEJAQAAAA==.Gravyboat:BAAALgAECgYJEwAAAA==.Graydawn:BAAALgADCgcJCQAAAA==.Grimwillie:BAAALgAECgQJBgAAAA==.Grismago:BAAALgAFFAEJAQAAAA==.Grizzlebee:BAAALgADCgEJAQAAAA==.',
Gu='Gusto:BAAALgAECgQJBgAAAA==.',
['Gë']='Gënghiskhän:BAAALgADCgUJBQAAAA==.',
Ha='Haakon:BAAALgAECgEJAQAAAA==.Hammertaint:BAAALgAECgYJBgAAAA==.Harrowing:BAABLgAECn8+AAIdAAkJPCNlAQB/AwAdAAkJPCNlAQB/AwAAAA==.Haurt:BAABLgAECn8zAAIbAAkJIhOuFQDNAQAbAAkJIhOuFQDNAQAAAA==.Havoq:BAAALgAECgMJAwAAAA==.',
He='Healamore:BAAALgADCgEJAgAAAA==.Healingway:BAAALgADCgUJBQABLgAECgcJDQAPAAAAAA==.Heavyhooves:BAABLgAECn8eAAIVAAgJ7xBcIQCYAQAVAAgJ7xBcIQCYAQAAAA==.Helawix:BAAALgADCggJEgAAAA==.Hellful:BAABLgAECn8VAAMgAAkJjgp9NQB9AQAgAAkJjgp9NQB9AQAZAAMJxQEvfQBRAAAAAA==.Hellscrèam:BAAALgAECgQJBgAAAA==.Herc:BAAALgAECgEJAQAAAA==.',
Hi='Hischier:BAABLgAECn8hAAMDAAkJaxciBwDkAQADAAcJVBwiBwDkAQACAAkJmwoVQQCaAQAAAA==.',
Ho='Holyjoey:BAAALgAECgYJDAAAAA==.Holymôley:BAABLgAECn8tAAIgAAkJdCENBQAcAwAgAAkJdCENBQAcAwAAAA==.Holytroller:BAAALgAECgUJCAAAAA==.Horrorcosmic:BAAALgADCgEJAQAAAA==.Hotbeeframen:BAAALgADCgEJAQAAAA==.',
Hu='Hulken:BAAALgADCgYJBgAAAA==.Humanpriest:BAAALgADCgEJAQABLgADCgkJCQAPAAAAAA==.Hussongs:BAAALgAECgEJAQAAAA==.',
['Hû']='Hûnta:BAAALgADCgQJBAAAAA==.',
Ic='Iceegoose:BAAALgAECgEJAQAAAA==.',
Ie='Ieratha:BAAALgAECgYJEAAAAA==.',
Ih='Ihuntyou:BAAALgAECgkJBQAAAA==.',
Il='Illidanina:BAAALgADCgUJBQABLgAFFAgJIAADAMwmAA==.',
Im='Impossibull:BAAALgADCgYJBgAAAA==.',
In='Invi:BAABLgAECn8hAAMdAAkJAh50EACPAgAdAAkJAh50EACPAgAIAAcJwhXpfACAAQAAAA==.',
Ir='Ironbull:BAAALgADCgYJBgAAAA==.',
It='Itkøvian:BAAALgAECggJCAAAAA==.',
Ja='Jarrickah:BAAALgAECgQJBAAAAA==.Jaycito:BAAALgAECgYJCwAAAA==.Jayylols:BAAALgAECgcJCAAAAA==.',
Je='Jeor:BAABLgAECn8bAAIIAAYJ5wepogDmAAAIAAYJ5wepogDmAAAAAA==.Jereome:BAAALgAECgYJDAAAAA==.Jezhus:BAAALgADCgkJBgAAAA==.',
Ji='Jigsy:BAABLgAECn8jAAMCAAkJ8CDLCgDKAgACAAgJ8CDLCgDKAgAEAAMJBx+KLAAMAQAAAA==.Jigy:BAAALgAECgYJDAAAAA==.Jimmy:BAAALgADCgcJBwAAAA==.',
Jo='Jokerzwild:BAAALgADCgQJBwAAAA==.Jorker:BAABLgAECn8bAAIJAAgJtR0RGgC4AgAJAAgJtR0RGgC4AgAAAA==.Jovinistus:BAAALgADCgcJDwAAAA==.',
Ju='Judgecutìe:BAABLgAECn8aAAIdAAgJvRlkFgALAgAdAAgJvRlkFgALAgAAAA==.Jue:BAAALgAECgEJBQAAAA==.Juiice:BAAALgADCgcJBwAAAA==.',
['Jë']='Jësus:BAAALgAECgcJEAAAAA==.',
Ka='Kaioh:BAAALgAECgEJAQAAAA==.Kalandaelis:BAAALgADCggJCwAAAA==.Kalei:BAAALgADCgYJBgAAAA==.Kamisama:BAAALgAECgYJDQAAAA==.Kawalskie:BAAALgAECgQJBQAAAA==.Kazraghand:BAABLgAECn8yAAIHAAkJzwddGgCAAQAHAAkJzwddGgCAAQAAAA==.',
Ke='Kei:BAACLgAFFH8VAAIJAAUJMhSdKwAjAQAJAAUJMhSdKwAjAQAuAAQKfzEAAwkACAnQHegVAFMCAAkACAnQHegVAFMCACIAAQkYDGRxADMAAAAA.Kelsaru:BAAALgADCgYJBgAAAA==.Kelsio:BAABLgAECn8zAAIGAAkJsxC0LADZAQAGAAkJsxC0LADZAQAAAA==.Kess:BAAALgAECgcJEgAAAA==.Keyboardcatt:BAABLgAECn8dAAIIAAgJrxzRJgAfAgAIAAgJrxzRJgAfAgAAAA==.',
Kh='Kharos:BAABLgAECn8lAAMeAAgJXgmVOwBNAQAeAAgJ0gWVOwBNAQAlAAgJZAdOLAAVAQAAAA==.',
Ki='Kikeo:BAAALgAECggJCgABLgAFFAUJFQAJADIUAA==.Killerwarz:BAAALgAECgEJAgAAAA==.Kirkoth:BAAALgAECgEJAQAAAA==.Kitariya:BAAALgADCgIJAgAAAA==.',
Kn='Knuts:BAABLgAECn8ZAAMEAAcJQAJlOwDGAAAEAAcJFQJlOwDGAAACAAYJzwEs+ABpAAAAAA==.',
Ko='Kogori:BAAALgAECgUJCgAAAA==.Konsentrated:BAABLgAECn8eAAIBAAYJ2Bb4dwBKAQABAAYJ2Bb4dwBKAQAAAA==.Kowtagion:BAAALgADCgYJBgABLgAFFAUJEAACAJ4YAA==.',
Ku='Kungfudegru:BAAALgAECgkJEQAAAA==.Kurator:BAAALgAECgYJBgAAAA==.Kuraven:BAAALgADCgcJBwAAAA==.Kuromo:BAAALgADCgMJBgAAAA==.',
Ky='Kylidan:BAAALgAECgEJAgAAAA==.Kyradin:BAAALgADCgIJAgABLgADCgYJDAAPAAAAAA==.Kyruutos:BAABLgAECn8fAAIIAAgJqwfbhwAUAQAIAAgJqwfbhwAUAQAAAA==.Kyvoker:BAAALgAECgQJBgAAAA==.',
['Kí']='Kítkat:BAABLgAECn8zAAIgAAgJORwwFABWAgAgAAgJORwwFABWAgAAAA==.',
La='Lachulax:BAAALgAECgUJBwAAAA==.Lacie:BAAALgAECgMJBwAAAA==.',
Le='Legato:BAAALgAECgEJAwAAAA==.Leibowitzy:BAABLgAECn8hAAIKAAYJthXGKAAvAQAKAAYJthXGKAAvAQAAAA==.Lettucee:BAAALgADCgYJBgAAAA==.Lexstrasza:BAAALgADCgEJAgAAAA==.',
Lh='Lhehitman:BAACLgAFFH8HAAIBAAQJRwxhQgA1AQABAAQJRwxhQgA1AQAuAAQKfzAAAwEACQmlIJ8MAOQCAAEACQmlIJ8MAOQCACQAAwmmEy4SAKEAAAAA.',
Li='Lifedeath:BAAALgADCgMJAwAAAA==.Lightsey:BAAALgAECgYJEAAAAA==.Lilth:BAAALgAECgIJAwABLgAECggJGgAdAL0ZAA==.Lindalamage:BAAALgADCgQJBQAAAA==.Linebreaker:BAABLgAECn8VAAIVAAgJkx6UPgCqAQAVAAgJkx6UPgCqAQAAAA==.Litezamatch:BAAALgADCgIJAgAAAA==.Liveloveslay:BAAALgAECgkJBQAAAA==.',
Lo='Loreena:BAAALgADCgIJAgAAAA==.Lorein:BAAALgAECgQJBQAAAA==.',
Lu='Luckydog:BAAALgAECgQJCAABLgAECgcJDwAPAAAAAA==.Ludey:BAABLgAECn9CAAMDAAkJyR2PAgCUAgADAAkJyR2PAgCUAgACAAEJeQQyDgEqAAAAAA==.Lutnick:BAAALgAECgEJAQAAAA==.Lutray:BAABLgAECn8sAAIaAAkJNiXdAABKAwAaAAkJNiXdAABKAwAAAA==.',
Ly='Lysandriloc:BAABLgAECn8jAAQCAAkJPQ+VPgCjAQACAAkJNg2VPgCjAQAEAAUJlwUDOgDMAAADAAMJERKwHACNAAAAAA==.',
Ma='Madcowdíseaz:BAABLgAECn8jAAIFAAgJxBf7OgDPAQAFAAgJxBf7OgDPAQAAAA==.Madskadoosh:BAAALgADCgEJAQAAAA==.Madtotems:BAAALgAECgcJEgAAAA==.Magnator:BAABLgAFFH8FAAIBAAMJ0wLaZADLAAABAAMJ0wLaZADLAAAAAA==.Malanore:BAABLgAECn8XAAIJAAcJ9hMgWQCWAQAJAAcJ9hMgWQCWAQAAAA==.Manbeartree:BAAALgAECgIJAgABLgAFFAYJGwAdAE8hAA==.Manbeärpig:BAAALgAECgQJBwAAAA==.Maomao:BAABLgAECn8nAAIeAAkJ1BlaEABiAgAeAAkJ1BlaEABiAgAAAA==.Margherita:BAAALgADCgEJAQAAAA==.Marodd:BAABLgAECn8mAAIhAAkJ0h7QBwCPAgAhAAkJ0h7QBwCPAgAAAA==.Mashìra:BAAALgAECgQJBAABLgAFFAQJCwAHAEkZAA==.Mashîra:BAABLgAFFH8LAAIHAAQJSRlrCABdAQAHAAQJSRlrCABdAQAAAA==.Matilda:BAAALgAECgEJAQAAAA==.Matylin:BAAALgADCgEJAQAAAA==.Maximus:BAACLgAFFH8GAAImAAMJ+R4oDQAUAQAmAAMJ+R4oDQAUAQAuAAQKfx4AAiYACQkdIlYBAOwCACYACQkdIlYBAOwCAAAA.',
Me='Meanmachine:BAAALgADCgIJAgAAAA==.Meatpocket:BAAALgAECgEJAgAAAA==.Meatwangs:BAABLgAECn8YAAIgAAgJixqFHwD7AQAgAAgJixqFHwD7AQAAAA==.Meleguar:BAAALgADCgIJBAAAAA==.Merihem:BAAALgADCggJDgAAAA==.Merpz:BAAALgADCgYJCwAAAA==.',
Mi='Mia:BAACLgAFFH8GAAIJAAQJ6xXvOgDuAAAJAAQJ6xXvOgDuAAAuAAQKfxUAAgkABgkLI6A6AAoCAAkABgkLI6A6AAoCAAAA.Miamore:BAAALgADCgEJAQABLgADCgkJCQAPAAAAAA==.Milize:BAAALgAECgIJAgAAAA==.Milknkookies:BAAALgAECgIJAgAAAA==.Miney:BAAALgAECgEJAQAAAA==.Mirowen:BAAALgAECgYJBgABLgAECgUJBwAPAAAAAA==.Misc:BAAALgAECgcJCQAAAA==.Mistaeatit:BAABLgAECn8kAAIFAAcJ5iJYLAAHAgAFAAcJ5iJYLAAHAgAAAA==.Mitch:BAAALgAECgQJCAAAAA==.Miu:BAAALgAFFAEJAQAAAA==.',
Mk='Mkachen:BAAALgADCgUJBQAAAA==.',
Mo='Monkintrunk:BAAALgADCgIJAgAAAA==.Moody:BAAALgAECgEJAQAAAA==.Moondotter:BAABLgAECn8UAAICAAYJlRcRXABMAQACAAYJlRcRXABMAQAAAA==.Moongoddess:BAAALgAECgIJAgABLgAECgYJFAACAJUXAA==.Moonslayer:BAABLgAECn8cAAMbAAkJXB4rBgCzAgAbAAkJXB4rBgCzAgATAAEJiAFv6gAaAAAAAA==.Moovefool:BAABLgAECn8YAAMgAAgJAwhCRwAtAQAgAAgJAwhCRwAtAQAZAAMJpQc1dgBpAAAAAA==.Mortimer:BAABLgAECn8qAAIFAAkJsByXGABwAgAFAAkJsByXGABwAgAAAA==.',
Mu='Mudgeon:BAAALgAECgYJEQAAAA==.Mulheron:BAAALgADCgMJBAAAAA==.Mulletmonk:BAAALgAECgQJCAAAAA==.',
['Mâ']='Mâshîrâ:BAABLgAECn8dAAMZAAgJHSKmCgDsAgAZAAgJHSKmCgDsAgAXAAMJwApDJACVAAABLgAFFAQJCwAHAEkZAA==.',
['Må']='Måshîrå:BAAALgAECgEJAgABLgAFFAQJCwAHAEkZAA==.',
Na='Nagarafan:BAABLgAECn8lAAIBAAgJ1AwsYQB8AQABAAgJ1AwsYQB8AQAAAA==.Nakor:BAABLgAECn8aAAIBAAgJABBeVQCaAQABAAgJABBeVQCaAQAAAA==.Natalie:BAAALgAECgQJCAAAAA==.Naughtybits:BAABLgAFFH8FAAIgAAUJ0Q4fEgBgAQAgAAUJ0Q4fEgBgAQAAAA==.',
Ne='Nefariat:BAAALgAECgMJBQAAAA==.Nefarious:BAAALgAECgEJAQABLgAECgMJBQAPAAAAAA==.Nefeli:BAACLgAFFH8GAAMRAAMJFwRCMAC1AAARAAMJFwRCMAC1AAAQAAMJswBFGwB/AAAuAAQKfzwAAxEACQmMHaUJAH0CABEACQnTHKUJAH0CABgACQlcGEQKADoCAAAA.Nelinne:BAABLgAECn8jAAMHAAgJeQHuMwCvAAAHAAgJbQHuMwCvAAAGAAMJDgFmygA7AAAAAA==.Nestia:BAAALgAECgYJDQAAAA==.Never:BAACLgAFFH8RAAICAAUJdyJ+EgCWAQACAAUJdyJ+EgCWAQAuAAQKfysAAwIACQmdJc0BALQDAAIACQmdJc0BALQDAAQABQnxIGoPANYBAAAA.',
Ni='Niccolò:BAAALgADCgEJAQAAAA==.Nidis:BAAALgADCgYJAQAAAA==.Nieve:BAAALgADCgEJAQAAAA==.Nightarrow:BAABLgAECn8rAAMGAAkJKRrBFgBUAgAGAAkJKRrBFgBUAgAmAAEJKwBVnAAKAAAAAA==.Nightbird:BAAALgAECgkJAgAAAA==.Nightshade:BAABLgAECn8+AAQGAAkJWx4JEACIAgAGAAkJWx4JEACIAgAHAAkJjxDEDQAIAgAmAAgJQwtPOACDAQAAAA==.Nil:BAAALgAECgcJDwAAAA==.Ninjamonkggz:BAABLgAECn8UAAIOAAcJRxNqKgCKAQAOAAcJRxNqKgCKAQAAAA==.Nitron:BAAALgAFFAEJAQAAAA==.Nix:BAABLgAECn8mAAIBAAkJqRkeJQBIAgABAAkJqRkeJQBIAgAAAA==.',
No='Noanelororal:BAAALgAECgEJAQAAAA==.Nortney:BAABLgAECn8VAAIVAAgJ7hjfGgB1AgAVAAgJ7hjfGgB1AgAAAA==.Noskilzreq:BAAALgAECgYJDAAAAA==.Nostrum:BAAALgAECgYJCgAAAA==.Noughts:BAAALgADCgEJAQAAAA==.Novva:BAAALgAECgEJAQAAAA==.',
Nu='Nubootie:BAAALgAECgQJBAAAAA==.',
Ny='Nyckels:BAAALgADCgEJAQAAAA==.',
Oa='Oathbound:BAAALgADCgEJAQAAAA==.',
Ob='Oblaan:BAABLgAECn8rAAQCAAkJzCCVCADiAgACAAgJmCCVCADiAgAEAAUJSR2RFgCVAQADAAEJHCKMJwBTAAAAAA==.',
Oc='Ocllo:BAABLgAECn8mAAIcAAkJ3hYgCgDTAQAcAAkJ3hYgCgDTAQAAAA==.Octopusy:BAAALgAECgUJCAAAAA==.',
Oj='Ojo:BAABLgAECn8eAAIWAAkJXw4IBgDCAQAWAAkJXw4IBgDCAQAAAA==.',
On='Onebuttonaug:BAAALgAECggJEwABLgAFFAcJHAAZAEoWAA==.Oniana:BAABLgAECn8xAAImAAgJvhh3BgDnAQAmAAgJvhh3BgDnAQAAAA==.',
Oo='Oozle:BAAALgADCgMJBQAAAA==.',
Op='Openwide:BAAALgADCgMJAwABLgAECgcJDQAPAAAAAA==.Oprahwinfuri:BAAALgADCgYJBgAAAA==.',
Or='Orccrusher:BAAALgADCgQJBwAAAA==.Orndushin:BAAALgADCgIJAgAAAA==.',
Ot='Ot:BAAALgAECgUJBwAAAA==.',
Pa='Pagamas:BAACLgAFFH8JAAIBAAQJPhyZJQBtAQABAAQJPhyZJQBtAQAuAAQKfxsAAgEACAk/IiYwALICAAEACAk/IiYwALICAAAA.Painbringer:BAAALgAFFAMJAwAAAA==.Pajano:BAAALgADCgcJGQAAAA==.Palandari:BAAALgAECgEJAQAAAA==.Palawin:BAAALgADCgkJCQAAAA==.Pandawan:BAAALgADCgkJDAAAAA==.Panter:BAABLgAECn8YAAMDAAgJchxWAwAdAgADAAgJchxWAwAdAgACAAIJeBCrwgB2AAAAAA==.Papaboomie:BAAALgAECgIJAgAAAA==.',
Pe='Peachpear:BAAALgAECgcJEQAAAA==.Perditious:BAAALgAECgQJBAAAAA==.',
Ph='Pharaoh:BAABLgAECn82AAIhAAgJuhioEwDiAQAhAAgJuhioEwDiAQAAAA==.Phodoe:BAABLgAECn8mAAITAAkJrwyZPABZAQATAAkJrwyZPABZAQAAAA==.Phycara:BAAALgAECgMJBAAAAA==.Phyronix:BAAALgAECgQJBQAAAA==.',
Pi='Pickawp:BAAALgAECgQJBAAAAA==.Pikepole:BAAALgADCgkJCQAAAA==.',
Pl='Playne:BAABLgAECn8pAAIBAAgJYxufMAAUAgABAAgJYxufMAAUAgAAAA==.',
Pn='Pnzr:BAAALgAECgcJCgAAAA==.',
Po='Pokeureyeout:BAABLgAECn8bAAIGAAYJQQmVcwD6AAAGAAYJQQmVcwD6AAAAAA==.Poofarts:BAAALgAECgEJAQAAAA==.Poostorclose:BAAALgAECgQJCQAAAA==.Pootonium:BAAALgAECgYJCgAAAA==.Popaul:BAAALgADCgYJCwAAAA==.',
Pr='Prahn:BAABLgAECn8iAAIgAAkJuA1VPQCMAQAgAAkJuA1VPQCMAQAAAA==.Preaced:BAABLgAECn8hAAIeAAgJYQ4hKwCcAQAeAAgJYQ4hKwCcAQAAAA==.Prokix:BAABLgAECn8hAAIBAAgJlQnjcABZAQABAAgJlQnjcABZAQAAAA==.Propainiac:BAAALgAECgQJBAAAAA==.',
Pu='Pumpkinpuff:BAABLgAECn8hAAInAAgJJiJSBwDOAgAnAAgJJiJSBwDOAgAAAA==.Purplppleatr:BAAALgADCgEJAQABLgAECggJKAAIALESAA==.',
['Pî']='Pîlot:BAABLgAECn8VAAIIAAYJDR+oQwCyAQAIAAYJDR+oQwCyAQAAAA==.',
Qu='Quiet:BAAALgAECgEJAQAAAA==.Quietkidz:BAAALgAECgEJAQAAAA==.Quiettreader:BAABLgAECn8dAAIBAAYJnRfngQA3AQABAAYJnRfngQA3AQAAAA==.Quokka:BAABLgAECn8hAAMTAAgJRCI9BwALAwATAAgJRCI9BwALAwAbAAUJ5xdGNgBjAQAAAA==.',
Ra='Raambocatt:BAAALgAECgYJBgAAAA==.Raidboss:BAAALgAECgYJDAAAAA==.Raklem:BAABLgAECn8kAAMGAAkJeA+dNwCrAQAGAAkJeA+dNwCrAQAmAAQJygNpbQCJAAAAAA==.Rampage:BAAALgADCgYJBgABLgAECgYJIQAKALYVAA==.Ramssox:BAAALgAECgEJAQAAAA==.Raty:BAAALgAECgIJAgAAAA==.',
Re='Redeath:BAABLgAECn8VAAIMAAYJNw3/JADVAAAMAAYJNw3/JADVAAABLgAECggJKAAIALESAA==.Redirect:BAAALgAECgEJAQABLgAECggJKAAIALESAA==.Redonculous:BAAALgAECggJDwAAAA==.Redpool:BAAALgAECgUJBwAAAA==.Reinault:BAACLgAFFH8RAAIOAAQJFw8eDgATAQAOAAQJFw8eDgATAQAuAAQKfycAAw4ACQmvHMoVADwCAA4ACQmvHMoVADwCACcABwnPCGI5AAMBAAAA.Reiramas:BAAALgAECgUJBQAAAA==.Relentful:BAAALgADCgIJAgAAAA==.Reliea:BAAALgAECgMJBAAAAA==.Renalla:BAAALgADCgYJBwAAAA==.Renix:BAAALgAECgEJAQAAAA==.Revansong:BAAALgAFFAIJAgABLgAFFAMJBQANALgfAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.',
Ro='Rob:BAAALgAECgQJBAAAAA==.Ronx:BAABLgAECn8eAAIBAAgJNBWrVACcAQABAAgJNBWrVACcAQAAAA==.Roodfrost:BAAALgADCgUJBwAAAA==.Roxxiloxxi:BAABLgAECn8qAAMEAAkJnQW0LgABAQACAAkJ+AQTaAAvAQAEAAgJGgS0LgABAQAAAA==.Royal:BAABLgAECn8pAAIUAAgJDRUzEAByAQAUAAgJDRUzEAByAQAAAA==.',
Ru='Rudeboy:BAAALgAECgUJBgAAAA==.Ruination:BAAALgAECgEJBAAAAA==.Rukìa:BAAALgADCgUJBQABLgAFFAIJAwAPAAAAAA==.',
Sa='Sabria:BAACLgAFFH8FAAIdAAMJXApwIgDAAAAdAAMJXApwIgDAAAAuAAQKfzkAAx0ACQn5GdANAG0CAB0ACQn5GdANAG0CAAgACAnND9lcAMwBAAAA.Sahee:BAAALgADCgMJAwAAAA==.Sahria:BAAALgAECgYJDwAAAA==.Samlosco:BAABLgAECn8mAAIYAAgJwRduBADvAQAYAAgJwRduBADvAQAAAA==.Saninth:BAAALgAECgEJAQAAAA==.Sanwicheater:BAAALgAECgQJBgABLgAFFAQJCQABAD4cAA==.Satra:BAAALgADCggJDwAAAA==.Savus:BAAALgAECgYJEAAAAA==.',
Sc='Scalpelheals:BAACLgAFFH8fAAIlAAgJtBODAQAnAgAlAAgJtBODAQAnAgAuAAQKfz8ABCUACQnCJb0AAKsDACUACQnCJb0AAKsDAB4ABwnvGvsbAP0BACEAAQkeCRliADQAAAAA.Sceledrus:BAAALgADCgcJDQAAAA==.Schizadin:BAAALgAECgcJCAAAAA==.Schizology:BAAALgADCgkJDAAAAA==.',
Se='Sebekuul:BAAALgAECggJCgAAAQ==.Selbur:BAAALgADCgMJAwABLgAFFAYJFQAOABMfAA==.Selfie:BAAALgADCgEJAgAAAA==.Selys:BAAALgADCgQJBAABLgAECggJMAAVANgTAA==.Sence:BAAALgAECgEJAQAAAA==.Sendy:BAAALgAECgYJCAAAAA==.Sephurik:BAACLgAFFH8cAAIBAAgJPRW6AgBaAgABAAgJPRW6AgBaAgAuAAQKf0MAAgEACQnJI3YIAIMDAAEACQnJI3YIAIMDAAAA.Sepimoth:BAAALgADCgYJDAAAAA==.Septicaemia:BAAALgAECgMJAwAAAA==.Seriphan:BAAALgAECgEJAQAAAA==.Serovin:BAAALgADCgcJBwAAAA==.',
Sh='Shamaderp:BAAALgADCgYJBgAAAA==.Shanamana:BAAALgADCgEJAQAAAA==.Shaolin:BAAALgADCgUJBQABLgAFFAIJAwAPAAAAAA==.Shawman:BAAALgADCgEJAQAAAA==.Sheepie:BAAALgADCgMJAwAAAA==.Shindorei:BAAALgAECgMJAwAAAA==.Shintai:BAAALgAECgUJDwAAAA==.Shnicklfritz:BAAALgADCgQJBQAAAA==.Showtek:BAABLgAECn8rAAMUAAgJxxm2CgDrAQAUAAcJqhm2CgDrAQAbAAgJMxWaGACuAQAAAA==.Shyft:BAABLgAECn8WAAINAAcJiBfIFwCEAQANAAcJiBfIFwCEAQABLgAFFAIJAwAPAAAAAA==.Shyfted:BAAALgADCgUJBQABLgAFFAIJAwAPAAAAAA==.Shyfty:BAAALgAECgYJCQABLgAFFAIJAwAPAAAAAA==.Shîn:BAABLgAECn8eAAQIAAcJzxudWAB4AQAIAAcJaxqdWAB4AQAcAAMJGQ0hMgCFAAAdAAIJXAW2igBTAAAAAA==.',
Si='Sickology:BAAALgAECgQJBgAAAA==.Sikanda:BAACLgAFFH8IAAMFAAQJqBSwYwDtAAAFAAMJNBWwYwDtAAAoAAEJAhPiEABJAAAuAAQKfyYAAwUACAmCI98gAL4CAAUACAmCI98gAL4CACgABgkHIUUGAMYBAAAA.Simplord:BAAALgAECgYJCQAAAA==.Sinara:BAAALgAECgUJCgAAAA==.Sintaxtwo:BAACLgAFFH8XAAMGAAUJlSPqCwB/AQAGAAUJlSPqCwB/AQAmAAQJzhnBEwADAQAuAAQKfyQAAyYACQkUJTMIABwDACYACAnFIzMIABwDAAYABgn0IxElAP0BAAAA.Sion:BAABLgAECn8kAAIhAAgJyx+bCgBcAgAhAAgJyx+bCgBcAgAAAA==.Sithlordz:BAAALgAECgQJBgAAAA==.',
Sk='Sky:BAABLgAECn8YAAIBAAgJdCCJHwD2AgABAAgJdCCJHwD2AgAAAA==.Skyelf:BAABLgAECn8hAAIGAAgJOhCzLgD3AQAGAAgJOhCzLgD3AQAAAA==.Skyrizzy:BAAALgAECgEJAQAAAA==.',
Sl='Sluggerr:BAABLgAECn8UAAIaAAgJXCC2CACUAgAaAAgJXCC2CACUAgAAAA==.',
Sm='Smallpox:BAAALgAECgQJBAAAAA==.Smitemedaddy:BAAALgADCgYJBQAAAA==.Smoke:BAAALgAECgMJAwAAAA==.Smokedeuce:BAAALgAECgYJCQAAAA==.Smokyette:BAAALgAECgMJAwABLgAECgYJCQAPAAAAAA==.',
So='Somira:BAAALgAECgUJCAAAAA==.Soraia:BAABLgAECn8ZAAIBAAYJHA2IkwAYAQABAAYJHA2IkwAYAQAAAA==.',
Sp='Spanktotank:BAABLgAECn8VAAIJAAYJaBECbgD0AAAJAAYJaBECbgD0AAAAAA==.Spectrecles:BAAALgAECgYJCwABLgAECgcJDQAPAAAAAA==.Spectrecless:BAAALgAECgcJDQAAAA==.Speez:BAABLgAECn8oAAMGAAkJwRIQJAACAgAGAAkJwRIQJAACAgAmAAEJuQGgmgAYAAAAAA==.Spookieturbo:BAAALgAECgYJCQAAAA==.Spookyhunter:BAABLgAECn8PAAIJAAgJdSIwDgCUAgAJAAgJdSIwDgCUAgAAAA==.',
St='Stablehand:BAABLgAECn82AAIGAAkJNBo/GQBCAgAGAAkJNBo/GQBCAgAAAA==.Stephen:BAAALgADCgcJBwAAAA==.Steve:BAACLgAFFH8cAAMZAAcJShZgAgDbAQAZAAcJShZgAgDbAQAgAAIJUgFGSABeAAAuAAQKfy0AAxkACQkOIrQCAIIDABkACQkOIrQCAIIDACAAAglwApqOAEYAAAAA.Stonedfel:BAABLgAECn8dAAIiAAkJuA75FQByAQAiAAkJuA75FQByAQAAAA==.Stonkbonkk:BAAALgAECgYJEAAAAA==.Stylez:BAAALgAECgYJCwAAAA==.',
Su='Sucsuck:BAAALgAECgMJAwAAAA==.Sundora:BAACLgAFFH8FAAIIAAIJ5RHoVAClAAAIAAIJ5RHoVAClAAAuAAQKfxcAAggACAlIGCU5ANUBAAgACAlIGCU5ANUBAAAA.Sunhoof:BAABLgAECn8kAAMIAAkJoxRLQAC9AQAIAAkJCxJLQAC9AQAcAAYJGxcAFwBlAQAAAA==.Superuberbot:BAABLgAECn8fAAIhAAgJGBGjJQBHAQAhAAgJGBGjJQBHAQAAAA==.Superuberdot:BAABLgAECn8kAAQDAAcJthc0EAArAQADAAcJNRU0EAArAQACAAQJGRUcjgDgAAAEAAUJDAaDIQBkAAAAAA==.Superuberhot:BAAALgAECgQJBgAAAA==.Superubernot:BAAALgAECgEJAwAAAA==.',
Sy='Sylvyr:BAAALgAECgMJAwAAAA==.Syntacks:BAABLgAECn8mAAIBAAgJ8BhlTQBOAgABAAgJ8BhlTQBOAgAAAA==.Syzara:BAAALgADCgYJCQAAAA==.',
['Sø']='Sørina:BAAALgAECgEJAQAAAA==.Sørrow:BAABLgAECn8fAAIJAAgJtg4tWAAtAQAJAAgJtg4tWAAtAQAAAA==.',
Ta='Tabi:BAABLgAECn8pAAIBAAkJ4gXSZAB0AQABAAkJ4gXSZAB0AQAAAA==.Tacts:BAAALgAECgYJEQAAAA==.Taiyn:BAAALgAECgQJBAABLgAECggJFQAaAK4YAA==.Takecare:BAAALgADCgIJAwAAAA==.Tankaa:BAAALgADCgYJBwAAAA==.',
Te='Terein:BAAALgADCgYJBwAAAA==.Test:BAAALgAECgcJDAAAAA==.',
Th='Thedawg:BAAALgADCgQJBAAAAA==.Thedayman:BAAALgAECgYJBgAAAA==.Theo:BAAALgAECgEJAQAAAA==.Therwinn:BAABLgAECn8hAAIGAAkJlyKBCgDAAgAGAAkJlyKBCgDAAgAAAA==.Thetaint:BAACLgAFFH8GAAINAAMJKBwuFgANAQANAAMJKBwuFgANAQAuAAQKfy8AAw0ACQkoIcQEAKsCAA0ACQkfIcQEAKsCABYABgmhG7oIAHIBAAAA.Thoradin:BAAALgADCgEJAQAAAA==.Thraxion:BAAALgAECgYJDwAAAA==.Thread:BAAALgAECgQJBgAAAA==.Threestorms:BAAALgADCgQJBAAAAA==.Thunderkow:BAAALgADCgcJCAABLgAFFAUJEAACAJ4YAA==.Thunderous:BAAALgAECgQJBAAAAA==.',
Ti='Tinee:BAAALgADCgkJCQABLgAECggJGAABAEEXAA==.Tinyrunes:BAAALgAECgcJEgAAAA==.',
To='Tojiguro:BAAALgADCgYJBwAAAA==.Tommoorello:BAAALgADCgEJAQAAAA==.Torags:BAAALgADCgEJAgAAAA==.Torrask:BAAALgAECgIJAgAAAA==.Totemofpeace:BAAALgAECgkJEwABLgAECggJIQAeAGEOAA==.Towfu:BAABLgAECn8YAAIBAAgJQRcDPwDeAQABAAgJQRcDPwDeAQAAAA==.',
Tr='Traelayn:BAAALgAECgEJAQAAAA==.Trapgawd:BAAALgADCgEJAQAAAA==.Trentlock:BAACLgAFFH8TAAMCAAUJwhIVMwApAQACAAUJwhIVMwApAQADAAIJiQh4EwBHAAAuAAQKfzMABAMACAkdIu8HAIIBAAIABwkGHtNGAIgBAAMABQkyI+8HAIIBAAQABQmaG1oMACoBAAAA.Tristae:BAAALgAECgcJDwAAAA==.Trollslingin:BAAALgADCgkJEAAAAA==.Truuk:BAAALgAECgYJCQAAAA==.',
Ts='Tsu:BAAALgAECgQJBQAAAA==.',
Tu='Tunapie:BAAALgAECgEJAgAAAA==.',
Ty='Tyzula:BAAALgAECgcJCwAAAA==.',
['Tê']='Têstament:BAAALgAECgQJBAAAAA==.',
Ub='Ubasti:BAAALgAECgcJDgAAAA==.',
Un='Unstablesha:BAAALgAECgYJBgAAAA==.',
Ur='Urahara:BAAALgAECgQJBAAAAA==.',
Va='Valiriel:BAAALgADCgcJDQAAAA==.Variz:BAAALgADCgEJAQAAAA==.Varsalis:BAAALgADCgMJAwAAAA==.',
Ve='Velidra:BAAALgADCgYJCQAAAA==.Vellektra:BAAALgAECgEJAQAAAA==.Vernöm:BAAALgAECgQJBAAAAA==.Vethmoree:BAAALgAECgUJBwABLgAECgYJBwAPAAAAAA==.',
Vi='Via:BAAALgAECgYJAwAAAA==.Vil:BAACLgAFFH8cAAIhAAgJkByiAABxAgAhAAgJkByiAABxAgAuAAQKfykAAiEACQk7JtcCAHoDACEACQk7JtcCAHoDAAAA.Vilonus:BAABLgAECn8pAAICAAgJXBDHSgB8AQACAAgJXBDHSgB8AQAAAA==.Virvum:BAAALgAECgQJBAAAAA==.Vitiate:BAAALgAECgYJCQAAAA==.',
Vo='Voll:BAABLgAECn8UAAMlAAYJrw/kKgAeAQAlAAYJjQ/kKgAeAQAeAAMJ+g73RACBAAAAAA==.',
['Và']='Vàáko:BAAALgAECgIJAgAAAA==.',
Wa='Warwix:BAAALgADCgMJAwAAAA==.Waxillium:BAAALgAECgcJCQAAAA==.',
We='Werebuddy:BAAALgADCgUJBQAAAA==.Weshyerga:BAAALgAFFAMJAwABLgAFFAUJEwAKAHImAA==.',
Wi='Wigly:BAABLgAECn8oAAIlAAkJbxF9DwAgAgAlAAkJbxF9DwAgAgAAAA==.Willathewise:BAAALgAECgYJBgAAAA==.Wingsolid:BAAALgADCgYJCwABLgAECgcJDQAPAAAAAA==.Withengar:BAABLgAECn8fAAIJAAgJuCG7FABcAgAJAAgJuCG7FABcAgAAAA==.',
Wr='Wrathrine:BAAALgAECgQJCQAAAA==.',
Wu='Wuoshi:BAACLgAFFH8HAAInAAQJEgkjGgDvAAAnAAQJEgkjGgDvAAAuAAQKfxQAAycACAkVErcmAH0BACcACAkVErcmAH0BAA4AAQn8EHhuADQAAAAA.Wuuzzyy:BAAALgAECgcJDwAAAA==.',
Xa='Xaliko:BAABLgAECn8lAAMCAAkJ+iBJCADmAgACAAkJ+iBJCADmAgAEAAYJUxZKEgC6AQAAAA==.Xanathos:BAAALgADCgUJBQAAAA==.Xanbaran:BAABLgAECn9CAAIeAAkJ3AqRIgBmAQAeAAkJ3AqRIgBmAQAAAA==.',
Xe='Xena:BAAALgAECgUJCAABLgAECggJKQAUAA0VAA==.Xero:BAAALgAECgMJBAABLgAECggJKQAUAA0VAA==.',
Xo='Xorellion:BAABLgAECn8pAAIBAAkJrg0wSQC8AQABAAkJrg0wSQC8AQAAAA==.',
Xy='Xyrters:BAACLgAFFH8PAAIQAAQJERF8EgAMAQAQAAQJERF8EgAMAQAuAAQKfyAAAhAACAlPIWYEAA0DABAACAlPIWYEAA0DAAAA.',
Ya='Yamikaiba:BAAALgAECgEJAQAAAA==.',
Ye='Yeji:BAAALgADCgEJAQAAAA==.Yelhsa:BAAALgADCgMJAwAAAA==.',
Yi='Yiddiephokin:BAAALgADCgYJCAAAAA==.',
Yu='Yukigodx:BAAALgADCggJEQAAAA==.Yukki:BAAALgAECgcJCAAAAA==.',
Za='Zanus:BAAALgADCgEJAgAAAA==.Zapmommy:BAAALgADCgIJAgAAAA==.Zariel:BAAALgAECgQJCQAAAA==.Zartini:BAABLgAECn8TAAIJAAkJcheOSABdAQAJAAkJcheOSABdAQAAAA==.Zartööl:BAAALgAECgQJBAAAAA==.Zaylas:BAAALgADCgMJAwAAAA==.',
Ze='Zeeba:BAAALgADCgEJAQAAAA==.Zerildk:BAABLgAECn8fAAMFAAkJJRhnPQDGAQAFAAkJehZnPQDGAQAoAAIJzBYzGACCAAAAAA==.Zerphaine:BAABLgAECn8fAAITAAkJthKZIQD1AQATAAkJthKZIQD1AQAAAA==.Zevs:BAABLgAECn8VAAIcAAgJdwu+GQBEAQAcAAgJdwu+GQBEAQAAAA==.',
Zi='Zic:BAABLgAECn8XAAIFAAcJcAwKewAkAQAFAAcJcAwKewAkAQAAAA==.Zixxi:BAABLgAECn8rAAIBAAkJURulIABfAgABAAkJURulIABfAgAAAA==.',
Zu='Zulakar:BAABLgAECn8cAAIdAAYJlhlLNgCjAQAdAAYJlhlLNgCjAQAAAA==.Zurxes:BAAALgAECgcJEAAAAA==.',
Zy='Zynatra:BAAALgAECgQJBwAAAA==.',
['Âk']='Âkaeus:BAABLgAECn8kAAIZAAkJuROpGgC3AQAZAAkJuROpGgC3AQAAAA==.',
['Ça']='Çaz:BAAALgADCgcJBwAAAA==.',
['Ëv']='Ëvø:BAAALgAECgUJCgAAAA==.',
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
