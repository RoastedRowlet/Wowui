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

local lookup = {'Druid-Restoration','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','Mage-Arcane','Druid-Guardian','Rogue-Subtlety','DeathKnight-Frost','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Mage-Frost','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Druid-Balance','Rogue-Assassination','Shaman-Restoration','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Devourer','Evoker-Augmentation','Monk-Windwalker','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abracanoobra:BAABNQAECn8bAAIBAAoKTxb5IAAhAgABAAoKTxb5IAAhAgAAAA==.Abuki:BAACNQAFFH8OAAICAAYKuRFFBACOAQACAAYKuRFFBACOAQA1AAQKfy0AAgIACgrzH28JAPQCAAIACgrzH28JAPQCAAAA.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQAECggIDAAAAA==.',
Al='Alfuric:BAAANQAECgQIBwAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgQIDAADAAAAAA==.Althraniir:BAAANQAECgEIAgAAAA==.Altrois:BAABNQAECn9EAAIEAAoKcSEPCgBlAwAEAAoKcSEPCgBlAwAAAA==.Altruis:BAAANQADCgcIBAAAAA==.',
Am='Amatrake:BAACNQAFFH8ZAAIFAAgKpRJ5AwDKAQAFAAgKpRJ5AwDKAQA1AAQKfzMAAgUACgp5HtUNAL0CAAUACgp5HtUNAL0CAAAA.Amatsano:BAEANQAECggIDAAAAA==.Amorsith:BAACNQAFFH8HAAIFAAIKgxOHCgCBAAAFAAIKgxOHCgCBAAA1AAQKfzoAAwUACgpWHh8KAJcCAAUACgpWHh8KAJcCAAYABgrBDFL0ADQBAAAA.Amurine:BAAANQAECggICAAAAA==.Amyst:BAABNQAECn8jAAIHAAgKbSFHSQCuAgAHAAgKbSFHSQCuAgAAAA==.',
An='Angrycrack:BAAANQAECggIEgAAAA==.Angryspace:BAAANQAECgUIBQAAAA==.Angusill:BAAANQADCggIFQAAAA==.Animuggus:BAEANQAECgcICQAAAA==.Anjunabeets:BAACNQAFFH8oAAMIAAkKmhyrAwAdAgAIAAgKAxyrAwAdAgAJAAEKJyCoKgBkAAA1AAQKfyEAAwgACgpcJEMaAIMCAAgACQoiJEMaAIMCAAkAAgoTGnQuAZAAAAAA.Anthran:BAABNQAECn8lAAMKAAoKqw0nKgArAQAKAAUKaRAnKgArAQALAAcKoQj04QAFAQAAAA==.',
Ao='Ao:BAAANQAECgIIAwAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICQABNQAECgoKHwAMAJwYAA==.Arcscythe:BAABNQAECn8gAAMNAAoKVhE4AgA8AgANAAgK0BQ4AgA8AgAOAAIK5waoNQFgAAAAAA==.Arctron:BAAANQAECgYICgABNQAECgoKHwAMAJwYAA==.Arthanos:BAAANQAECggICgABNQAECgoKIAAPAD4bAA==.Artoo:BAABNQAECn8jAAIQAAoKIhgfKwBTAgAQAAoKIhgfKwBTAgAAAA==.',
As='Ashesonly:BAACNQAFFH8FAAIRAAQKVAKlGwBcAAARAAQKVAKlGwBcAAA1AAQKf00AAhEACgqJHCYfAFICABEACgqJHCYfAFICAAAA.Assaulter:BAAANQADCgIIAgABNQAECgoKSAAJALYhAA==.',
Au='Auramis:BAABNQAECn83AAMSAAoK9iFrGAAUAwASAAoK9iFrGAAUAwATAAIKsQfNTgBwAAAAAA==.',
Az='Azariel:BAACNQAFFH8HAAIUAAQKMxbXFACRAAAUAAQKMxbXFACRAAA1AAQKf0EAAhQACgqLIm4HABsDABQACgqLIm4HABsDAAAA.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFH8ZAAIEAAgKXCI0AwBkAgAEAAgKXCI0AwBkAgA1AAQKfzEAAgQACgqYJBsLAFsDAAQACgqYJBsLAFsDAAAA.Balgith:BAABNQAECn8vAAMVAAoKlg1OVQDAAQAVAAoKlg1OVQDAAQAGAAUK+AK9RwGFAAAAAA==.Balrus:BAAANQADCgEIAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECn8cAAMGAAkKuQkyuQCrAQAGAAkKuQkyuQCrAQAVAAUKhAl3vQABAQAAAA==.Barthoun:BAABNQAECn8WAAIHAAoKCA3YcQCtAQAHAAoKCA3YcQCtAQAAAA==.Battleburger:BAAANQAECgEIAQAAAA==.Bauchelaine:BAAANQAECgEIAQAAAA==.Bawitaba:BAAANQAECgUJDQAAAA==.',
Be='Benchknight:BAACNQAFFH8OAAQRAAcKXQ55DQAGAQARAAUKwQt5DQAGAQAWAAEKzRgbHQBfAAAEAAEKAABcMwAuAAA1AAQKf0EABBEACgoFIFsSAPoCABEACgrMH1sSAPoCABYACQp/Gv9IAPMBAAQABQqRHdxEACoBAAAA.Beoron:BAACNQAFFH8KAAIXAAYKbBwQAgAVAQAXAAYKbBwQAgAVAQA1AAQKf0UAAhcACgpMJlMBAMQDABcACgpMJlMBAMQDAAAA.Bettyßastion:BAABNQAECn81AAIGAAoKghiTVgAqAgAGAAoKghiTVgAqAgAAAA==.Bettyßlithe:BAAANQAECgUIDAABNQAECgoKNQAGAIIYAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigdk:BAAANQAECgIIAgAAAA==.Bigflex:BAAANQAECggIDgAAAA==.Bio:BAAANQAECggICgAAAA==.Bioenergy:BAAANQADCgcIBwABNQAECggICgADAAAAAA==.Biolysis:BAAANQAECgQIBAABNQAECggICgADAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAABNQAECn8uAAMYAAoK4AlJGAAfAQAOAAoK+webrABLAQAYAAgKnghJGAAfAQAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAABNQAECn8gAAIZAAoKcxLRYwBbAQAZAAoKcxLRYwBbAQAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Brainstorm:BAAANQAECgQIAwAAAA==.Braintumor:BAABNQAECn8eAAIWAAcKIgkGfgAkAQAWAAcKIgkGfgAkAQAAAA==.Brontag:BAABNQAECn80AAQaAAoKTh9gBwCDAgAaAAkKRiBgBwCDAgAHAAoK/hc6oADMAQAbAAEKAACPQQA5AAAAAA==.',
Bu='Bugles:BAAANQAECgEIAQAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgADAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Caliboy:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAABNQAECn8aAAMSAAkKGRjXUQAuAgASAAkKGRjXUQAuAgATAAEKAAA+lAATAAAAAA==.Canekii:BAAANQAECgYIEQABNQAECgkJGgASABkYAA==.Cannyon:BAAANQADCgQIBAAAAA==.Casini:BAAANQAECgcIBwAAAA==.Cathrîne:BAAANQADCggICAAAAA==.',
Ce='Celeice:BAAANQADCgUIBQAAAA==.Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAACNQAFFH8KAAIJAAUKlh83DgAYAQAJAAUKlh83DgAYAQA1AAQKfzsAAgkACgqKJZIJAD8DAAkACgqKJZIJAD8DAAAA.Ceruledge:BAAANQAECgcIBwABNQAECgoKNgATAMofAA==.',
Ch='Chaboomy:BAECNQAFFH8YAAIcAAgK5hOUCgDMAQAcAAgK5hOUCgDMAQA1AAQKf0gAAhwACgrOJCUEAE8DABwACgrOJCUEAE8DAAAA.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAABNQAECn87AAMHAAkKDRHNdAClAQAHAAkKDRHNdAClAQAbAAUKtgodKgCuAAAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECn8nAAQOAAoKqhjvjgBhAgAOAAoKqhjvjgBhAgANAAYKzQ/gBABMAQAYAAEKjh0mSAA0AAAAAA==.Conyay:BAAANQAECggIDgAAAA==.Cowploww:BAAANQAECgMIBAAAAA==.',
Cr='Croissant:BAABNQAECn8iAAILAAgKwx7aOACpAgALAAgKwx7aOACpAgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.Cytheria:BAAANQAECgIIAgABNQAECgoKIAAPAD4bAA==.',
Da='Dalidan:BAAANQAECgUIBgABNQAECgoKGQACAPocAA==.Dalórien:BAAANQADCgUICgABNQAECgQIBAADAAAAAA==.Damaerin:BAAANQAECgUIDgAAAA==.Darkis:BAAANQAECggIEgAAAA==.Darkseph:BAABNQAECn8WAAIdAAgKLRNRFwBuAQAdAAgKLRNRFwBuAQAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFH8VAAMZAAgK/xtuCgDEAQAZAAUKhhtuCgDEAQAeAAQKbwcxGwDMAAA1AAQKf0cABBkACgpEJt4GALIDABkACgpEJt4GALIDAB4AAwpxCPD5AHcAAB8AAQphBoo3ADcAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAABNQAECn84AAIdAAoKPhihDAACAgAdAAoKPhihDAACAgABNQAECgoKSAAJALYhAA==.Delessia:BAAANQAECggIBwAAAA==.Desy:BAAANQAECgYIDQAAAA==.',
Di='Diggersby:BAACNQAFFH8OAAIPAAYKdCCtAADCAQAPAAYKdCCtAADCAQA1AAQKfyQAAg8ACgr6ILwHAAcDAA8ACgr6ILwHAAcDAAAA.Disastrous:BAACNQAFFH8OAAIJAAYKFw5HDAAwAQAJAAYKFw5HDAAwAQA1AAQKfzMAAgkACgo0FxZYABoCAAkACgo0FxZYABoCAAAA.',
Do='Doomangel:BAAANQAECggIBgAAAA==.Doson:BAAANQAECgUIDAAAAA==.',
Dr='Dracthyr:BAAANQAECgYIBQABNQAECggICgADAAAAAA==.Drago:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.Dragonbison:BAAANQAECgcICgAAAA==.Drazzindruid:BAAANQAECgMIAwAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgoKSAAJALYhAA==.',
['Dø']='Døc:BAABNQAECn9LAAQeAAoKTxrWRgBGAgAeAAoKTxrWRgBGAgAZAAkKJRPwVgCCAQAfAAMKJArAKQCyAAAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAACNQAFFH8XAAILAAgKfQtzCQDSAQALAAgKfQtzCQDSAQA1AAQKfzEAAwsACgoVH48fAAYDAAsACgoVH48fAAYDAAoAAgrqDl1hAGIAAAAA.',
El='Eldranus:BAAANQAECggIDAAAAA==.',
En='Enimed:BAABNQAECn9EAAIEAAoK8R02EgCEAgAEAAoK8R02EgCEAgAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAACNQAFFH8JAAQKAAQKnxYSDwCXAAALAAIKPBdfLgCdAAAKAAIKIhASDwCXAAAgAAEKAAAqGwAAAAA1AAQKfywABAoACgp+IDMbAJMBAAsABwp4HkpkAC0CAAoABQpBIDMbAJMBACAABAp8HK8SAB8BAAAA.',
Fa='Falarion:BAAANQAECgcICgAAAA==.Fam:BAABNQAECn81AAIOAAkKgyKYJgBGAwAOAAkKgyKYJgBGAwAAAA==.Fatherseph:BAAANQAECgUICwABNQAECggIFgAdAC0TAA==.',
Fi='Finkymcbinky:BAABNQAECn8cAAIOAAkKgA3miQCTAQAOAAkKgA3miQCTAQAAAA==.Finroz:BAAANQADCgQIBAAAAA==.Fisterdobble:BAABNQAECn87AAIYAAoKHhpWBgCeAgAYAAoKHhpWBgCeAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIPQAAAA==.Florella:BAAANQADCgUIBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forestpump:BAAANQAECgEIAQABNQAECgcIEAADAAAAAA==.Forgedd:BAAANQAECgUIBQAAAA==.Forgeddemon:BAABNQAECn82AAIMAAoKOgz6CwB2AQAMAAoKOgz6CwB2AQAAAA==.',
Fr='Frogkid:BAAANQAECgMIAwAAAA==.Frostborne:BAABNQAECn8uAAIWAAkKJhvyMQBkAgAWAAkKJhvyMQBkAgAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frostystomp:BAABNQAECn8cAAIEAAkK1A9bKQC2AQAEAAkK1A9bKQC2AQABNQAFFAYICgAXAGwcAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAADAAAAAA==.',
Fu='Funeral:BAABNQAECn8mAAILAAoKbw0oXgC6AQALAAoKbw0oXgC6AQABNQAECgoKSAAJALYhAA==.',
Ga='Gamjee:BAAANQAECggIDAAAAA==.',
Ge='Gerkindk:BAAANQADCggICAABNQAECgEIBAADAAAAAA==.Gerkindrd:BAAANQAECgEIBAAAAA==.',
Gh='Ghostly:BAAANQADCggJCQAAAA==.',
Gl='Glyndin:BAAANQAECggIDAAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAYIDgAPAHQgAA==.Goodolrúss:BAAANQADCgYIEAAAAA==.',
Gr='Grackalackin:BAABNQAECn8hAAIBAAcKtRhRIgDlAQABAAcKtRhRIgDlAQAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAABNQAECn8dAAIUAAkKrgnINAB6AQAUAAkKrgnINAB6AQAAAA==.',
Gu='Guilliman:BAABNQAECn8sAAIHAAkKvBxCXQB0AgAHAAkKvBxCXQB0AgAAAA==.Gulaj:BAABNQAECn82AAIJAAoK6RYJbADqAQAJAAoK6RYJbADqAQAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgYICgAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAACNQAFFH8FAAISAAIKHx6FJwCqAAASAAIKHx6FJwCqAAA1AAQKfzcAAhIACgo/H9suAK0CABIACgo/H9suAK0CAAAA.',
Hi='Hiruken:BAAANQADCgcIFQAAAA==.',
Ho='Hope:BAEBNQAECn8pAAMPAAoKlx7mCACzAgAPAAoKlx7mCACzAgABAAoKcBKnHwAvAgABNQAFFAgIGwASAKwRAA==.Hortzel:BAAANQAECggIDAAAAA==.Hotrollz:BAAANQADCgUIBQABNQAECggILgATACAVAA==.Howdoidie:BAABNQAECn8YAAIRAAkKBBWsJgAhAgARAAkKBBWsJgAhAgAAAA==.Howdoitotem:BAABNQAECn8jAAMZAAoKiBl6MgCwAgAZAAoKiBl6MgCwAgAeAAMK3geW+QB3AAAAAA==.',
Hu='Hulkx:BAAANQAECgYIEQAAAA==.Humaa:BAABNQAECn9AAAIGAAoKwRs8VwApAgAGAAoKwRs8VwApAgAAAA==.Huntus:BAABNQAECn8zAAIJAAkKdh2ZOwC3AgAJAAkKdh2ZOwC3AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icenaria:BAAANQADCggICAAAAA==.Icewiz:BAAANQABCgUIBQABNQAECgcIFQAhACsIAA==.Icy:BAABNQAECn8eAAIHAAkKYReFYwBkAgAHAAkKYReFYwBkAgAAAA==.',
Im='Impale:BAAANQADCgcIEgAAAA==.Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECn9GAAITAAoKniA9CADkAgATAAoKniA9CADkAgAAAA==.',
Iz='Izuu:BAABNQAECn8gAAIJAAkKlhDZdADVAQAJAAkKlhDZdADVAQAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQIBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAACNQAFFH8GAAMQAAQKnxE2FgDXAAAQAAQKnxE2FgDXAAAdAAEKIwtJIABIAAA1AAQKfzUAAxAACgqjHRYbAP4BABAACgqeHBYbAP4BAB0ABQrdGuAlAAMBAAAA.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAABNQAECn8oAAILAAoKywtBZgCkAQALAAoKywtBZgCkAQAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQAECggIFgAdAC0TAA==.',
Ka='Kankiro:BAAANQAECgcIBwAAAA==.Kanstentin:BAAANQADCggICAAAAA==.Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAABNQAECn8gAAMBAAYKtA7qPwAMAQABAAYKtA7qPwAMAQAcAAUKrgSkhAC/AAAAAA==.Kelemvor:BAABNQAECn8WAAIhAAoK+wxaLwDHAQAhAAoK+wxaLwDHAQAAAA==.Ken:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgcIBwAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAACNQAFFH8GAAIEAAQKSgoyGwCXAAAEAAQKSgoyGwCXAAA1AAQKfyYAAgQACgq9GugzAD0CAAQACgq9GugzAD0CAAAA.',
Ki='Kimmy:BAAANQAECgYICwAAAA==.',
Kl='Kleenex:BAABNQAECn8wAAIYAAoKnRhWCABeAgAYAAoKnRhWCABeAgAAAA==.',
Ko='Koldiss:BAAANQAECgIIAgAAAA==.',
Kr='Krueger:BAAANQAECgcICgABNQAECgoKHAARAGQTAA==.',
Ku='Kurisutina:BAAANQAECgYIDAABNQAFFAUICgAeAJ0KAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECn9IAAIJAAoKtiG/FgBAAwAJAAoKtiG/FgBAAwAAAA==.Leethalfu:BAABNQAECn8dAAIMAAoKVBeqCQCEAgAMAAoKVBeqCQCEAgAAAA==.Leethalrot:BAAANQAECgEIAQABNQAECgoKHQAMAFQXAA==.Legosi:BAABNQAECn8hAAILAAoKGw15gQBdAQALAAoKGw15gQBdAQAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAABNQAECn84AAILAAoKGiCVIAACAwALAAoKGiCVIAACAwAAAA==.Leviosa:BAABNQAECn8ZAAIhAAoKVh3uDQB0AgAhAAoKVh3uDQB0AgAAAA==.',
Lh='Lhux:BAACNQAFFH8IAAIJAAMKOAp9GADQAAAJAAMKOAp9GADQAAA1AAQKf1IAAgkACgqwIu4MACcDAAkACgqwIu4MACcDAAE1AAQKCgo0ACIAchMA.Lhuxi:BAABNQAECn80AAIiAAoKchNHBgD8AQAiAAoKchNHBgD8AQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAACNQAFFH8HAAIcAAUKhSDlFwDsAAAcAAUKhSDlFwDsAAA1AAQKfzMAAhwACgr5JCQMAGoDABwACgr5JCQMAGoDAAAA.',
Lu='Luceean:BAAANQAECggICQAAAA==.Lurth:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.',
Ly='Lyxxie:BAABNQAECn8+AAMRAAoKbBuyIgA7AgARAAoKbBuyIgA7AgAWAAUKCQvPjQDuAAAAAA==.',
Ma='Maelle:BAAANQAECgQIBAAAAA==.Mageus:BAAANQAECgcICAAAAA==.Manafart:BAAANQADCgYIBgABNQAECgkJOwAHAA0RAA==.Manbearpïg:BAABNQAECn8hAAMXAAkKthuUCgAyAgAXAAkKthuUCgAyAgAcAAQKJwsBaQCFAAABNQAECgoKGAAIAAwmAA==.Matsumushi:BAABNQAECn8uAAMMAAkKzxPKDgAGAgAMAAgKWBbKDgAGAgAjAAgKdwZ4NQD2AAAAAA==.',
Mc='Mcnastyy:BAAANQADCgYICgAAAA==.',
Me='Mefesto:BAABNQAECn8dAAIOAAkKvg+DtgAWAgAOAAkKvg+DtgAWAgABNQABCgQIBgADAAAAAA==.Mellore:BAAANQAECgIIAgABNQAFFAUIBwAcAIUgAA==.Melyna:BAAANQAECgIIAgABNQAECgkJKAAFAIoWAA==.Metsutan:BAACNQAFFH8JAAIQAAcKtBRpCACgAQAQAAcKtBRpCACgAQA1AAQKf0MAAhAACQqgIrgLABkDABAACQqgIrgLABkDAAAA.',
Mi='Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQAECgUICAAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQAECgQIBQAAAA==.',
Na='Naes:BAAANQADCgYIDAAAAA==.Nazuresh:BAAANQAECgEIAQABNQAECggIIgASAPcdAA==.',
Ne='Necrodamus:BAAANQAECggIDgAAAA==.Nekcrotic:BAABNQAECn8VAAMLAAgKshNunACfAQALAAcKuRJunACfAQAKAAIKIxClWAB2AAAAAA==.Nekromant:BAABNQAECn8gAAMKAAcKRA27SACmAAALAAYK2gm6xwA6AQAKAAMKiA27SACmAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgcIBwAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBQAAAA==.Nintales:BAAANQAECgQIDQAAAA==.',
No='Nohric:BAAANQAECgcIEwAAAA==.Nohshim:BAAANQAECgcICAAAAA==.Noobieone:BAAANQAECgIIAQAAAA==.Norsem:BAAANQAECgYIDwAAAA==.',
Nu='Nullmortis:BAAANQAECgEIAQAAAA==.',
Ny='Nymera:BAAANQAECggIDgABNQAECgoKIAAPAD4bAA==.',
['Nä']='Nämeless:BAAANQAECgMIAwAAAA==.',
Oh='Ohlorn:BAACNQAFFH8JAAIfAAcK/gyhAwA9AQAfAAcK/gyhAwA9AQA1AAQKfz8AAh8ACgr6JdAAAHADAB8ACgr6JdAAAHADAAAA.',
Ok='Oktar:BAAANQADCgUIBQAAAA==.',
On='Onenightstab:BAAANQAECgcIEAAAAA==.Onfleek:BAABNQAECn8gAAMSAAgKCCJ6KgChAgASAAgKCCJ6KgChAgATAAIKFAiZfAAwAAAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgYICgAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.Palysuk:BAAANQAECgQICQAAAA==.Papier:BAAANQAECgYIBgAAAA==.Paranoid:BAAANQADCgYIBgAAAA==.Parsephone:BAACNQAFFH8WAAMBAAcKgB3eBADWAQABAAYKYR3eBADWAQAcAAQKgg5pFADPAAA1AAQKf1MABAEACgp3JfIAANIDAAEACQpWJvIAANIDABwACgrmH4YLAOkCABcABQroHOUgAPsAAAE1AAQKCgogAAIA7xYA.Parstout:BAABNQAECn8gAAICAAoK7xYxDABvAgACAAoK7xYxDABvAgAAAA==.Pawsitivity:BAABNQAECn82AAIZAAoK6SK0IAAIAwAZAAoK6SK0IAAIAwAAAA==.',
Pd='Pdbm:BAABNQAECn8gAAIGAAoKThpGUACkAgAGAAoKThpGUACkAgAAAA==.',
Pe='Petr:BAABNQAECn84AAMSAAoKHBrlMACkAgASAAoKHBrlMACkAgATAAEKAADqjgAcAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAABNQAECn8xAAIVAAoKEx46LwCpAgAVAAoKEx46LwCpAgAAAA==.',
Ph='Physix:BAAANQAECgcIBQAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcICwAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkadin:BAAANQAECgYIBgABNQAECgoKOQARACkfAA==.Porkins:BAABNQAECn85AAQRAAoKKR8cFgDaAgARAAoKzx4cFgDaAgAWAAYKdxMMZgB5AQAEAAEKAACHxAAAAAAAAA==.',
Pr='Priestus:BAAANQAECgUIAwAAAA==.Primeslice:BAAANQAECgIIAgABNQAFFAYICgAXAGwcAA==.',
Ps='Psyndra:BAAANQAFFAEIAQABNQAECgoKHwAeAEkhAA==.',
Py='Pyraxx:BAABNQAECn9FAAIYAAoKaSPJAACwAwAYAAoKaSPJAACwAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFH8ZAAIhAAgKQBsBBAALAgAhAAgKQBsBBAALAgA1AAQKfzMAAiEACgqjJe4GAO0CACEACgqjJe4GAO0CAAAA.',
Qu='Quatermaine:BAAANQAECgUIDgAAAA==.',
Ra='Radovan:BAACNQAFFH8RAAMLAAcK7B7EFQBIAQALAAYKpSDEFQBIAQAKAAEKCBiBGgBQAAA1AAQKf1UAAwsACgovJsoPAFMDAAsACQoSJsoPAFMDAAoABQpDIM4aAJYBAAAA.Rayael:BAAANQAECgQIEgABNQAFFAMIBgAOAFEQAA==.Rayjax:BAAANQAECgQIAwAAAA==.Raìdèn:BAABNQAECn8iAAISAAgK9x1cPgBBAgASAAgK9x1cPgBBAgAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECn8sAAMeAAoKjBP3lgBOAQAeAAkKDRL3lgBOAQAZAAYKBAiVxgAFAQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ro='Roktar:BAAANQADCgcIDgABNQAECgoKIAAPAD4bAA==.Rosaelyia:BAAANQADCggIDwABNQAECgoKLwAJAA4ZAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECn8cAAIVAAgK4SDqJADXAgAVAAgK4SDqJADXAgAAAA==.',
Sa='Samavati:BAABNQAECn8bAAICAAcKfQ7DJQBLAQACAAcKfQ7DJQBLAQAAAA==.Sammi:BAAANQAECgYIBQAAAA==.Sarah:BAABNQAECn8wAAMSAAkKXiQBBACvAwASAAkKXiQBBACvAwAkAAMKngv6GwCHAAAAAA==.Saross:BAAANQADCggICAAAAA==.Sasori:BAACNQAFFH8MAAIQAAUKaghtCABwAQAQAAUKaghtCABwAQA1AAQKfygAAhAACQotHAQNAKUCABAACQotHAQNAKUCAAAA.Sassyface:BAABNQAECn9AAAIKAAoKAxEyBQCsAQAKAAoKAxEyBQCsAQAAAA==.',
Sc='Scaledia:BAAANQAECgEIAQAAAA==.',
Se='Sellit:BAAANQAECgUIBgAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQAECggIBwABNQAFFAQIBwAUADMWAA==.Shadowdin:BAABNQAECn8yAAIVAAoKtxwQJwDNAgAVAAoKtxwQJwDNAgAAAA==.Shamzilla:BAABNQAECn8oAAIZAAgKABtRNACnAgAZAAgKABtRNACnAgAAAA==.Shockblast:BAAANQADCggIFgAAAA==.Shriike:BAAANQADCgYIBgAAAA==.Shuyinn:BAAANQAECggICAABNQAECgoKJQAKAKsNAA==.',
Si='Sibbrena:BAABNQAECn82AAITAAoKyh9PCADiAgATAAoKyh9PCADiAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAABNQAECn8VAAMLAAcKMxLlywAyAQALAAYKFhDlywAyAQAKAAEKpxo7agBMAAAAAA==.Sinemon:BAAANQAECgcICwAAAA==.Sinz:BAAANQAECgIIAQAAAA==.',
Sk='Skn:BAABNQAECn8vAAMVAAoKyCLVCgByAwAVAAoKyCLVCgByAwAGAAUKiRvz4QBYAQAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAABNQAECn8YAAMbAAUKWQPCOQBjAAAbAAUKWQPCOQBjAAAHAAQKxwEQFwFOAAAAAA==.Slycedyce:BAAANQAECgMIAwABNQAFFAcIEQALAOweAA==.',
Sm='Smartlurth:BAAANQAECgIIAgAAAA==.',
Sn='Snowjob:BAABNQAECn8WAAIOAAcKjRYAygDxAQAOAAcKjRYAygDxAQAAAA==.',
So='Solatic:BAAANQAECgUIBQAAAA==.Sonal:BAAANQADCgYIBgABNQAECgoKOwALAKUYAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Speedburrito:BAAANQADCgUIBQAAAA==.Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECggIDAAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stead:BAABNQAECn8aAAIZAAoKsRb3LwAZAgAZAAoKsRb3LwAZAgAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAABNQAECn8XAAQgAAoKzgzeDQB4AQAgAAcKrAreDQB4AQAKAAQKtxB4NwDjAAALAAUKdQiyCQG4AAAAAA==.Stellar:BAAANQAECgUIEQABNQAECgoKagAQAPskAA==.Stelthme:BAABNQAECn8yAAMQAAkKpxsjJAB1AgAQAAkKeRkjJAB1AgAdAAcKiRbxPQDXAQABNQAECgoKagAQAPskAA==.Strongman:BAAANQAECgIIAgAAAA==.',
Sw='Sweetie:BAAANQABCgYICAAAAA==.',
Ta='Takeshì:BAAANQADCgcIBwABNQAECggIIgASAPcdAA==.Tanìs:BAAANQAECggIEwAAAA==.Tarle:BAABNQAECn8oAAIFAAkKihZ2FwC+AQAFAAkKihZ2FwC+AQAAAA==.Tazath:BAAANQAECggIDgABNQAFFAYICgAXAGwcAA==.',
Te='Tendroni:BAAANQAECgIIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAABNQAECn8zAAMEAAoKJRmyIgDlAQAEAAoKJRmyIgDlAQAWAAIKkwbajQAuAAAAAA==.Thraxsus:BAAANQABCgIIAgAAAA==.',
To='Tonhãotrovão:BAAANQAECgQIBAABNQAECgoKGAAIAAwmAA==.',
Tr='Trashii:BAABNQAECn8vAAMlAAoKZA5RBwAIAgAlAAoKZA5RBwAIAgAIAAMKHwLNcgBrAAAAAA==.Treevive:BAAANQAECgYIBgABNQAFFAQICgASAOkVAA==.Trencough:BAAANQAECgYIBgAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAACNQAFFH8GAAIZAAMK3gIRHwC8AAAZAAMK3gIRHwC8AAA1AAQKfyEAAhkACQrxHbY0AKUCABkACQrxHbY0AKUCAAAA.Trystan:BAABNQAECn8xAAIGAAoKehAniwC1AQAGAAoKehAniwC1AQAAAA==.',
Ts='Tsinga:BAAANQAECgUICQAAAA==.Tsla:BAAANQADCgEIAQAAAA==.',
Tu='Turlo:BAAANQADCgcICwAAAA==.',
Tw='Twobrews:BAACNQAFFH8GAAIMAAMKSRazBgDqAAAMAAMKSRazBgDqAAA1AAQKfyoAAwwACgqcG1IFAA0DAAwACQohH1IFAA0DACMABAriCPU8AMQAAAAA.Twohammered:BAAANQADCgcICwABNQAFFAMIBgAMAEkWAA==.Twojoints:BAAANQAECgYIBgABNQAFFAMIBgAMAEkWAA==.',
['Tì']='Tìnktìnk:BAAANQADCggIDgABNQAECggIIgASAPcdAA==.',
['Tø']='Tøm:BAACNQAFFH8WAAIGAAgK9Rh3BQADAgAGAAgK9Rh3BQADAgA1AAQKfz8AAgYACgpCJb4MAD4DAAYACgpCJb4MAD4DAAAA.',
Ul='Ullirus:BAAANQAECgIIAQAAAA==.Ultimatefury:BAAANQAECgQIBAAAAA==.',
Un='Unb:BAAANQAECgEIAQAAAA==.Unbiased:BAABNQAECn8zAAMWAAoKpxo4NQBUAgAWAAgKGxg4NQBUAgARAAoKGxmmNQADAgAAAA==.Unholyblodd:BAAANQADCggIIAAAAA==.Unshookable:BAACNQAFFH8JAAICAAQKExD1BwDWAAACAAQKExD1BwDWAAA1AAQKfzUAAgIACgpoIkYFAE0DAAIACgpoIkYFAE0DAAAA.',
Ur='Ursos:BAABNQAECn8gAAMPAAoKPhvECwB9AgAPAAoKPhvECwB9AgAXAAMK5RGUKgCyAAAAAA==.Urìko:BAAANQAECgYIBAAAAA==.',
Ut='Utrig:BAABNQAECn8cAAMHAAoKugqfcQCuAQAHAAoKugqfcQCuAQAbAAEKGQW3SQApAAABNQAECgoKIAAPAD4bAA==.',
Va='Vaelor:BAAANQADCgQIBAABNQAECgoKIAAPAD4bAA==.Valsande:BAAANQADCgIIAgAAAA==.Valzyne:BAAANQAECgUIAwAAAA==.',
Ve='Vecnah:BAAANQADCgMIAwAAAA==.Vermax:BAAANQAECgYICQAAAA==.',
Vi='Vika:BAAANQAECggIDQABNQAECgoKIAAPAD4bAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAABNQAECn8aAAMUAAgKgBCnSgD/AAAUAAQKsxKnSgD/AAAhAAYK3wtDTAD3AAAAAA==.Voidlockus:BAAANQAECggICwAAAA==.Voorhees:BAAANQABCgQIBAAAAA==.',
Vu='Vulcin:BAABNQAECn8hAAIVAAoKOxtyJgDQAgAVAAoKOxtyJgDQAgABNQAECgoKRQAYAGkjAA==.',
Wa='War:BAAANQADCgQIBAABNQAFFAQICQAKAJ8WAA==.Wariuus:BAAANQAECgcICAAAAA==.Watercupp:BAABNQAECn8VAAIhAAcKKwi4SAAQAQAhAAcKKwi4SAAQAQAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgUIBgAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAABNQAECn8yAAMeAAkKfh+WIAC5AgAeAAkKfh+WIAC5AgAZAAMKRhm+5gDKAAAAAA==.Windsor:BAAANQAECgMIAgAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xe='Xena:BAAANQAECgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQAECgEIAgADAAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Za='Zandramadas:BAABNQAECn8rAAMBAAoKnhlHGQByAgABAAoKnhlHGQByAgAcAAgKGA8DSgC/AQAAAA==.Zaraline:BAABNQAECn8vAAIJAAoKDhnxPgBYAgAJAAoKDhnxPgBYAgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECggIDAAAAA==.',
Zo='Zoomiez:BAAANQAECgUIDwAAAA==.',
Zp='Zpai:BAABNQAECn8fAAMMAAoKnBhDDwD8AQAMAAoKnBhDDwD8AQAjAAYKbAWxTADFAAAAAA==.',
Zy='Zyfae:BAAANQAECggIBAAAAA==.Zynos:BAAANQADCggICQAAAA==.Zyyn:BAAANQAECgYICgAAAA==.',
['Äc']='Ächilles:BAAANQABCgIIAgAAAA==.',
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
