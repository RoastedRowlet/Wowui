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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','Druid-Feral','Paladin-Protection','DemonHunter-Devourer','Hunter-Survival','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Mage-Fire','Druid-Guardian','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Rogue-Subtlety','Evoker-Preservation','Druid-Restoration','Warlock-Affliction','Monk-Brewmaster','Warrior-Arms','Warrior-Fury','Druid-Balance','Warlock-Destruction','Priest-Shadow','DemonHunter-Vengeance','Priest-Holy','Shaman-Restoration','DemonHunter-Havoc','Monk-Mistweaver','Evoker-Devastation','Priest-Discipline','Shaman-Enhancement','Warrior-Protection','Monk-Windwalker','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aamodar:BAABLgAECn8bAAMBAAgJMQ/7SQCXAQABAAgJMQ/7SQCXAQACAAMJ/geoIgB1AAAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAABLgAECn8yAAIDAAgJyBeYPADQAQADAAgJyBeYPADQAQAAAA==.Abhorrent:BAAALgAECgEJAQAAAA==.',
Ac='Acathisia:BAAALgAECgEJAQAAAA==.Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgQJBAAAAA==.Adino:BAABLgAECn82AAIBAAkJmQ7ENgDYAQABAAkJmQ7ENgDYAQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAACLgAFFH8QAAIEAAQJiBqJKAA+AQAEAAQJiBqJKAA+AQAuAAQKfyUAAgQACAnnIvAOABcDAAQACAnnIvAOABcDAAAA.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.',
Ah='Ahote:BAABLgAECn8TAAIFAAUJJSXKCAAMAgAFAAUJJSXKCAAMAgAAAA==.Ahtee:BAABLgAECn84AAMEAAkJsx2QFQCkAgAEAAkJsx2QFQCkAgAGAAQJdwjmMQBuAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.Akuprovik:BAABLgAECn8bAAIHAAcJ9AprdgAOAQAHAAcJ9AprdgAOAQAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Alanthos:BAAALgAECgQJBAAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgAECgcJBwABLgAFFAMJBQABAN4SAA==.Alexandraus:BAAALgAECgUJBQAAAA==.Alexiea:BAAALgADCgkJDQAAAA==.Algodon:BAABLgAFFH8GAAIEAAMJkQygUwDaAAAEAAMJkQygUwDaAAAAAA==.Allenduin:BAAALgADCgEJAQAAAA==.Almeads:BAAALgAECgEJAQAAAA==.Alonias:BAAALgAECgUJCQAAAA==.Alseena:BAABLgAECn8eAAIEAAYJ7Bn7igA6AQAEAAYJ7Bn7igA6AQAAAA==.Alysiita:BAAALgAECgEJAQAAAA==.',
Am='Amadeux:BAACLgAFFH8OAAIIAAQJzxjmCwBNAQAIAAQJzxjmCwBNAQAuAAQKfyMAAggACAlfIHAHAIACAAgACAlfIHAHAIACAAAA.Amarawr:BAAALgADCgYJBgABLgAFFAQJDgAIAM8YAA==.Amicae:BAAALgADCgcJCAAAAA==.Ammandor:BAAALgAECgQJBAAAAA==.Amun:BAAALgAECgEJAQAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgYJDgABLgAECggJLAAJANMbAA==.Anform:BAAALgAECgIJAgAAAA==.Anryn:BAAALgAECgYJBgABLgAFFAQJEAAEAIgaAA==.Anthais:BAAALgAECgQJBAAAAA==.Anvar:BAACLgAFFH8FAAIBAAMJ3hJbRADhAAABAAMJ3hJbRADhAAAuAAQKfxwAAgEACQkFG+EbAFQCAAEACQkFG+EbAFQCAAAA.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgYJCQAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn9AAAIKAAkJ+SHaAgBfAwAKAAkJ+SHaAgBfAwAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECggJDAAAAA==.',
At='Atrumdeus:BAABLgAECn9BAAIEAAgJ6B3XKQA4AgAEAAgJ6B3XKQA4AgAAAA==.',
Au='Audiamer:BAAALgAECgkJDgAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQALAAAAAA==.Aweyaeh:BAAALgADCgQJBwAAAA==.Awkykit:BAABLgAECn8fAAIMAAgJqAVuBgAPAQAMAAgJqAVuBgAPAQAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAINAAYJVxB+FwD/AAANAAYJVxB+FwD/AAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Baloou:BAAALgAECgEJAQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8pAAIOAAgJJxsDLgBDAgAOAAgJJxsDLgBDAgAAAA==.Bannann:BAAALgADCgIJAgAAAA==.Banned:BAAALgAECgQJBQABLgAFFAIJBwADACshAA==.Bariôn:BAAALgAECgQJBwAAAA==.Barney:BAAALgADCgYJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAgJIwAPAIYgAA==.Beaksbigdk:BAACLgAFFH8jAAMPAAgJhiBfAgCsAgAPAAcJhiBfAgCsAgAQAAEJAACnEQBmAAAuAAQKf0AAAw8ACQk6JgIIABgDAA8ACQkXJgIIABgDABAACAmnJKwFAKwCAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAABLgAECn8ZAAMPAAgJFRCTfwCEAQAPAAgJ1A+TfwCEAQAQAAcJ7gSeLwCzAAAAAA==.Beedo:BAAALgAECgEJAgAAAA==.Beef:BAAALgAECgYJBgABLgAFFAUJDgARALgcAA==.Beefknight:BAAALgAECgMJAwAAAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAABLgAECn8VAAISAAcJJAeaKQAcAQASAAcJJAeaKQAcAQAAAA==.Belldia:BAACLgAFFH8ZAAIBAAYJkhFLBQBOAQABAAYJkhFLBQBOAQAuAAQKf0QAAwEACQnZII0PAL8CAAEACQnZII0PAL8CAAIABQnTDaZQAAsBAAAA.Beni:BAAALgAECgUJDAAAAA==.Beniima:BAAALgAECgYJEwAAAA==.Benimarú:BAAALgAECgQJBAAAAA==.Bennylickz:BAABLgAECn8zAAMTAAkJMxd0DQDUAQATAAgJyRV0DQDUAQARAAYJORW5JwCDAQAAAA==.',
Bi='Bibby:BAAALgAECgYJEAAAAA==.Bibi:BAAALgAECgQJBAAAAA==.Birdbear:BAABLgAECn8YAAMFAAYJ+AqkHQDgAAAFAAYJ+AqkHQDgAAAUAAUJeAvhbADNAAAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAFFAQJDAAVAE0TAA==.Blufox:BAABLgAECn8XAAIEAAcJUiTLIgBbAgAEAAcJUiTLIgBbAgAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAOANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgIJAgABLgAECgYJFgAHAHMeAA==.',
Br='Brainpower:BAAALgAECgYJBgAAAA==.Broherum:BAAALgAECgEJAQAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.Brunia:BAAALgADCgIJAgAAAA==.',
Bu='Bubonicmyro:BAAALgAECgMJAwABLgAECggJGgAWAE8WAA==.Buckbeak:BAAALgAECgYJDAAAAA==.Bulgingtotem:BAAALgAECgEJAQAAAA==.Busting:BAAALgAECgYJEAAAAA==.Buttmucker:BAAALgAECgIJAgAAAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAIJAgAAAA==.',
By='Byebye:BAAALgAECgcJBgAAAA==.',
['Bà']='Bàhamut:BAAALgAECgYJCwAAAA==.',
['Bå']='Båemax:BAABLgAECn8aAAMXAAgJrA3hGQBhAQAXAAgJTg3hGQBhAQAYAAQJwQcGXQCwAAAAAA==.',
Ca='Caelestos:BAABLgAECn8ZAAMIAAgJiBuEDABCAgAIAAcJiBuEDABCAgACAAcJvApnGgC5AAAAAA==.Castar:BAAALgADCgIJAgAAAA==.',
Cc='Ccwwds:BAAALgADCgYJDQABLgAFFAIJAwALAAAAAA==.',
Ce='Celypzo:BAAALgADCgkJCQAAAA==.Cewkie:BAABLgAECn8nAAIYAAcJ0hj+JQCjAQAYAAcJ0hj+JQCjAQAAAA==.',
Ch='Chaulock:BAAALgAECgcJCAAAAA==.Chausup:BAAALgADCgQJBAABLgAECggJJwAEAKQkAA==.Chautime:BAABLgAECn8nAAIEAAgJpCTCBwBYAwAEAAgJpCTCBwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgcJCAALAAAAAA==.Chemdizz:BAAALgAECgYJDwAAAA==.Chialliance:BAABLgAECn8cAAMZAAgJIBLgIgCEAQAZAAgJIBLgIgCEAQAUAAEJowGo6gAaAAAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAYJGQANAOYVAA==.Chocö:BAAALgAECgYJBgAAAA==.Choujisan:BAAALgAECgYJDwABLgAFFAMJCAAEAGsMAA==.Chrysamere:BAAALgADCgcJDQAAAA==.Chugrar:BAAALgADCggJDQAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8eAAIIAAgJUiGMAwDwAgAIAAgJUiGMAwDwAgAAAA==.Cloft:BAAALgAECgYJBgAAAA==.Clumzylock:BAABLgAECn8dAAMDAAcJYQ6sagBQAQADAAcJOA6sagBQAQAaAAYJ+QsXOADUAAABLgAECggJMQAbAEMMAA==.',
Co='Code:BAABLgAECn8fAAISAAkJvSLJBwAUAwASAAkJvSLJBwAUAwAAAA==.Consfearacy:BAAALgAECggJCgAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8jAAIEAAcJCB/pQgDfAQAEAAcJCB/pQgDfAQAAAA==.Corrl:BAABLgAECn8VAAIOAAcJSRiDeQBoAQAOAAcJSRiDeQBoAQABLgAECgcJIwAEAAgfAA==.',
Cr='Crayzie:BAAALgADCgEJAQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgAECgQJBQABLgAECgUJBQALAAAAAA==.Creatrix:BAAALgADCgcJBwAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuma:BAAALgAECgEJBgAAAA==.Cumb:BAABLgAECn8WAAMHAAYJcx6zQwCaAQAHAAYJYRyzQwCaAQAcAAIJnxDjKgAyAAAAAA==.Curatoria:BAAALgAECgYJDwAAAA==.',
Cw='Cwwddsz:BAAALgAECgEJAQABLgAFFAIJAwALAAAAAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgYJDAAAAA==.',
Da='Daioh:BAAALgADCgEJAQAAAA==.Daladin:BAAALgADCgEJAQAAAA==.Dalanos:BAAALgADCgUJBQAAAA==.Damacraze:BAACLgAFFH8GAAIBAAIJlR06UgCvAAABAAIJlR06UgCvAAAuAAQKfx4AAgEACAm6IbUQALQCAAEACAm6IbUQALQCAAAA.Darkbluerose:BAABLgAECn8XAAMCAAYJrQdPIACJAAAIAAUJLgXKIQDJAAACAAYJVAZPIACJAAAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAABLgAECn8XAAIKAAcJ5we2PgAhAQAKAAcJ5we2PgAhAQAAAA==.Daxine:BAAALgAECgYJBgAAAA==.',
De='Deadboy:BAAALgADCggJCgAAAA==.Deadroar:BAAALgAFFAIJAwAAAA==.Deadwill:BAAALgAECgMJAwAAAA==.Deaminase:BAABLgAECn8pAAIOAAYJ5R0ZagCLAQAOAAYJ5R0ZagCLAQAAAA==.Deathknell:BAAALgAFFAEJAQAAAA==.Decypher:BAABLgAECn8aAAIdAAgJBxntEgAeAgAdAAgJBxntEgAeAgAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAABLgAECn8ZAAIeAAgJOxl1FwBhAgAeAAgJOxl1FwBhAgAAAA==.Demidru:BAABLgAECn8cAAIZAAcJFRWSIgCHAQAZAAcJFRWSIgCHAQAAAA==.Demonboar:BAABLgAECn8cAAMfAAgJOBPbFwCOAQAfAAgJOBPbFwCOAQAHAAYJPwSUmwDhAAAAAA==.Demonrocky:BAAALgADCgkJCwAAAA==.Demunic:BAACLgAFFH8GAAMcAAQJSAKCCQBrAAAfAAMJlAJ1GACIAAAcAAMJlQGCCQBrAAAuAAQKfxgAAhwACAnHBaATAOkAABwACAnHBaATAOkAAAAA.Dennis:BAAALgAECgIJBQAAAA==.Derringer:BAAALgAECgYJBgAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dharin:BAAALgAECgEJAQAAAA==.Dhqt:BAAALgAECgEJAwABLgAECgUJBQALAAAAAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dihnnis:BAAALgAECgMJAwAAAA==.Dingbangow:BAAALgAECgUJCwAAAA==.Discoinferno:BAAALgAECgIJAgAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAABLgAECn8UAAIfAAYJ1xILJQAVAQAfAAYJ1xILJQAVAQAAAA==.',
Do='Doneza:BAAALgAECgMJAwAAAA==.Donki:BAABLgAFFH8FAAIPAAUJ1gkFWgAaAQAPAAUJ1gkFWgAaAQAAAA==.Donothingwin:BAACLgAFFH8HAAIDAAIJKyHqaQDBAAADAAIJKyHqaQDBAAAuAAQKfyUAAwMACQl/Jt0DAH4DAAMACQl/Jt0DAH4DABoAAwkKJZgnACUBAAAA.Doomgirl:BAAALgAECgYJBgAAAA==.Doublelift:BAAALgAFFAIJBAAAAA==.',
Dr='Dragondeznut:BAAALgAECgIJAgAAAA==.Drakblak:BAABLgAECn8jAAIdAAkJRBQZGwADAgAdAAkJRBQZGwADAgAAAA==.Draukarí:BAABLgAECn8sAAQVAAkJfB5TAQDlAgAVAAkJQh5TAQDlAgADAAcJYRzvKABtAgAaAAEJiB+5XwBQAAAAAA==.Drayer:BAABLgAECn8sAAIKAAgJahHlLgB4AQAKAAgJahHlLgB4AQAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAABLgAECn8eAAIHAAgJnxg6MQDhAQAHAAgJnxg6MQDhAQAAAA==.Drunkenmist:BAABLgAECn8iAAIgAAYJVBMPNABSAQAgAAYJVBMPNABSAQAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8UAAMRAAUJKCD8FABjAQARAAQJKCD8FABjAQAhAAEJAACwDgAAAAAuAAQKfykAAxEACQllIm4KAJUCABEACQllIm4KAJUCACEABgkIFVYaAGEBAAAA.',
Du='Dudley:BAAALgAECgEJAQAAAA==.Dundundun:BAAALgAECgcJCQAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAABLgAECn8cAAMBAAkJXwm3SgCVAQABAAkJXwm3SgCVAQACAAEJrwDWmwAQAAAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgAECgMJAwABLgAFFAgJIwAPAIYgAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAABLgAECn8VAAIiAAgJcBjRDQBlAgAiAAgJcBjRDQBlAgAAAA==.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8cAAMCAAYJCRowCACcAQACAAYJ8hkwCACcAQABAAQJygj5OAADAQAuAAQKfy8AAwIACQlbIwACAMoCAAIACQlbIwACAMoCAAEAAgljFtrBAH0AAAAA.',
Eg='Eggdrop:BAABLgAECn8yAAIYAAkJ2h+dBQDtAgAYAAkJ2h+dBQDtAgAAAA==.Egufro:BAAALgAECgYJBgABLgAFFAMJCQAjAO0TAA==.',
Eh='Ehgu:BAACLgAFFH8JAAIjAAMJ7RNVCADuAAAjAAMJ7RNVCADuAAAuAAQKfzAAAiMACQkXGk4GAEYCACMACQkXGk4GAEYCAAAA.',
Ei='Eismond:BAAALgAECgMJBAAAAA==.',
El='Eleaya:BAAALgAECgIJAgAAAA==.Elediyn:BAAALgAECgMJBgAAAA==.Eleverclear:BAABLgAECn8YAAMKAAcJWRSpPgB+AQAKAAcJWRSpPgB+AQAEAAIJXw9mDwFwAAAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAABLgAECn8UAAIEAAgJbAYNkgAuAQAEAAgJbAYNkgAuAQAAAA==.',
Em='Emidget:BAABLgAECn8XAAIOAAYJ9hIGkgA5AQAOAAYJ9hIGkgA5AQAAAA==.',
En='Endervish:BAAALgAECgEJAgABLgAECgkJIQABACsRAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.',
Er='Erhmer:BAAALgAECggJBgAAAA==.Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAABLgAECn8XAAIPAAYJqAqfswAbAQAPAAYJqAqfswAbAQAAAA==.',
Fa='Fabermor:BAAALgAECgEJAQAAAA==.Fairygon:BAAALgAECgUJBQAAAA==.Fairyhunter:BAAALgAECgYJBwAAAA==.Fairymonk:BAAALgAECgYJDgAAAA==.Fangrat:BAAALgAECgEJAQABLgAECgUJBQALAAAAAA==.Fariona:BAAALgADCggJCgAAAA==.Fartbarf:BAABLgAECn8kAAIDAAgJcxJ4VADKAQADAAgJcxJ4VADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Fatfatfat:BAAALgAECgIJAgABLgAFFAIJAwALAAAAAA==.Fatshark:BAAALgAECgEJAQABLgAFFAIJAwALAAAAAA==.Faya:BAAALgADCgUJBQABLgAFFAMJBQABAN4SAA==.',
Fe='Fennicuss:BAAALgAECgEJAgAAAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAABLgAECn8YAAIgAAgJpgamRQD8AAAgAAgJpgamRQD8AAAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAcJHgAkAN4kAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fl='Flameblue:BAAALgAECgYJEQAAAA==.Flandia:BAAALgAECgQJDAAAAA==.Fleen:BAAALgAECgIJBAABLgAECgYJFgAHAHMeAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAABLgAECn8zAAIPAAkJthLgOgDyAQAPAAkJthLgOgDyAQAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frittata:BAAALgAECgUJBQABLgAFFAQJCgAOAIcIAA==.Frostbringer:BAAALgAECgMJAwAAAA==.Frostworn:BAAALgADCgYJBgAAAA==.Frostybetch:BAAALgAECgcJDAAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIEAAcJ+RwHMwBWAgAEAAcJ+RwHMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAgJHAAQAHsVAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgAECgUJBQAAAA==.',
Fy='Fylerian:BAACLgAFFH8iAAIZAAgJzCKRAADdAgAZAAgJzCKRAADdAgAuAAQKfyIAAhkACQn0JHgCAJcDABkACQn0JHgCAJcDAAAA.Fylerianmage:BAABLgAECn8YAAIOAAYJMiD1lwClAQAOAAYJMiD1lwClAQABLgAFFAgJIgAZAMwiAA==.Fylerianprie:BAAALgAFFAEJAQABLgAFFAgJIgAZAMwiAA==.Fyrebane:BAAALgAECgYJBgAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAABLgAFFH8GAAIRAAQJ3BKeMADQAAARAAQJ3BKeMADQAAAAAA==.Gargalon:BAABLgAFFH8FAAIRAAUJ1woSKQD5AAARAAUJ1woSKQD5AAAAAA==.Gatør:BAAALgAECgcJEwAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAABLgAECn8ZAAINAAgJhBzeDADaAQANAAgJhBzeDADaAQAAAA==.',
Gh='Ghettomike:BAAALgAECgcJDAAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Gillixos:BAAALgAECgEJAQAAAA==.Giny:BAABLgAECn8rAAIJAAkJmBNzHADRAQAJAAkJmBNzHADRAQAAAA==.',
Gl='Glandros:BAAALgADCgUJBwAAAA==.Glorin:BAAALgAECgYJDAAAAA==.',
Go='Gobbledeez:BAABLgAECn8VAAIeAAgJ1hc3LQDUAQAeAAgJ1hc3LQDUAQAAAA==.Gojojo:BAABLgAECn8pAAIYAAgJfRxBEwC0AgAYAAgJfRxBEwC0AgAAAA==.Gongfuboar:BAAALgAECgYJBgAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgMJCQAAAA==.Govinniuur:BAABLgAECn8lAAIQAAgJQhAmGwBRAQAQAAgJQhAmGwBRAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECgkJNgAPACAWAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgADCgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIOAAgJ1CLiEwAxAwAOAAgJ1CLiEwAxAwAAAA==.Greatness:BAAALgAECgYJBgAAAA==.Grizzy:BAAALgAFFAEJAQAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groundscore:BAAALgADCgUJBQABLgAECgMJBAALAAAAAA==.Gryf:BAAALgADCgQJBAAAAA==.',
Gu='Gundam:BAAALgAECggJDgABLgAFFAcJHAAOABQbAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgAECgYJBgAAAA==.Gwydionatlan:BAAALgADCgEJAQABLgAECgYJBgALAAAAAA==.',
Gy='Gyndrinolara:BAABLgAECn8dAAIBAAgJ2hJqRgCiAQABAAgJ2hJqRgCiAQAAAA==.',
Ha='Hafadude:BAAALgAECgkJCwAAAA==.Hakouh:BAAALgAECggJDwAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Hatereading:BAAALgAECgUJBgAAAA==.',
He='Headhuntér:BAABLgAECn8YAAIIAAgJUARTKAA6AQAIAAgJUARTKAA6AQAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgEJAgAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECgkJMwATADMXAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAFFAQJCQAdAHQHAA==.Hellokrittyz:BAAALgADCgcJBwAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAUJFAAjACsjAA==.Hikiru:BAAALgAECgkJCwAAAA==.Hikura:BAAALgAECgcJBgAAAA==.Hirohh:BAAALgAECgUJBQAAAA==.',
Hk='Hkinc:BAAALgAECgYJBwABLgAECggJHwAEAB0hAA==.',
Ho='Holydwarfen:BAAALgAECgEJAQAAAA==.Holygrey:BAAALgADCgYJBwAAAA==.Holysh:BAAALgADCgYJBgAAAA==.Holywater:BAACLgAFFH8HAAIGAAMJCRHxCAC3AAAGAAMJCRHxCAC3AAAuAAQKfz4AAgYACAkOIdAEALMCAAYACAkOIdAEALMCAAAA.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAABLgAECn8WAAMDAAYJ+B5rQQAJAgADAAYJ+B5rQQAJAgAaAAIJtxbsUgB1AAAAAA==.Horick:BAAALgAECgEJAQAAAA==.Houndo:BAAALgADCggJCAAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Hu='Hunnie:BAAALgAECgEJAQAAAA==.',
Hy='Hyperiann:BAAALgADCgEJAQAAAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Ic='Iceyrot:BAAALgAECgYJBwAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJAwABLgAFFAEJAQALAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAABLgAECn8ZAAMfAAcJ1RnREgDJAQAfAAcJ1RnREgDJAQAHAAQJIgW+yABlAAAAAA==.Ineedbowjob:BAAALgAECgYJEAAAAA==.Intothedark:BAAALgAECgQJBgAAAA==.Intotherain:BAAALgADCgIJAwAAAA==.Inya:BAAALgAECgYJDAAAAA==.Inyomouf:BAAALgAECgEJAgAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIEAAgJxyCPFwDbAgAEAAgJxyCPFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgcJDwAAAA==.',
Is='Isaacnewton:BAABLgAECn8rAAIYAAcJCSHjEgA5AgAYAAcJCSHjEgA5AgAAAA==.Islandstyle:BAAALgAECgEJAQAAAA==.',
It='Ithoril:BAAALgADCgcJCwAAAA==.Itsdone:BAABLgAECn8tAAMDAAgJJRM5TQDhAQADAAgJDhI5TQDhAQAaAAMJSxQQJQBnAAABLgAFFAQJCQAdAHQHAA==.',
Iv='Iveliz:BAABLgAECn8ZAAIbAAgJxhNcHwCjAQAbAAgJxhNcHwCjAQAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAFFAUJBQARANUCAA==.',
Ja='Jackk:BAACLgAFFH8MAAIKAAUJMBohFgBAAQAKAAUJMBohFgBAAQAuAAQKfzMAAwoACAkmIT8IAOoCAAoACAkmIT8IAOoCAAQABQnZCYS2APMAAAAA.Jackks:BAAALgAECgEJAQABLgAFFAUJDAAKADAaAA==.Jadewulf:BAAALgADCgcJBgABLgAECggJFQABAI0WAA==.Jaeger:BAABLgAECn8cAAIIAAgJfhrSCwAVAgAIAAgJfhrSCwAVAgAAAA==.Jamalsdad:BAAALgAECgIJAgAAAA==.Janzan:BAABLgAECn8VAAIeAAYJcxPNUAA5AQAeAAYJcxPNUAA5AQAAAA==.Jasmonk:BAABLgAECn81AAIlAAkJHwzyIAB/AQAlAAkJHwzyIAB/AQAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8aAAIHAAgJpg6NbQAiAQAHAAgJpg6NbQAiAQAAAA==.',
Ji='Jinkz:BAAALgAECgYJCQAAAA==.',
Jo='Josephsmith:BAAALgAECgkJAwAAAA==.',
Ju='Judgevis:BAABLgAECn8WAAIKAAgJrg8UNwBIAQAKAAgJrg8UNwBIAQAAAA==.Jumbles:BAAALgAECgYJBgAAAA==.Justeene:BAAALgAECgYJBgABLgAECgQJBQALAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
['Jø']='Jøshu:BAAALgAECgUJBwAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwALAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katedolores:BAAALgAECgcJBwABLgAECggJMgABAH4jAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgAECgYJBgAAAA==.Kazuu:BAAALgADCgEJBgAAAA==.',
Ke='Keepup:BAABLgAECn8UAAMHAAcJWx9UJwAQAgAHAAcJWx9UJwAQAgAcAAEJgBamKAA9AAABLgAFFAIJBwADACshAA==.Keg:BAAALgAFFAEJAgABLgAFFAgJHAAQAHsVAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECgkJKgAeACwbAA==.Keladun:BAAALgAECgUJDAAAAA==.',
Kh='Khaho:BAABLgAECn8bAAIOAAgJuhMAaACQAQAOAAgJuhMAaACQAQAAAA==.Khonan:BAABLgAECn8XAAQlAAYJVBeLNwBAAQAlAAUJ+hSLNwBAAQAgAAYJtg6HNAAfAQAWAAEJsQPylgAeAAABLgAFFAcJEgAOALYZAA==.',
Ki='Kiamar:BAAALgAECgkJDwAAAA==.Kicey:BAAALgAECgkJBQABLgAECgkJHwASAL0iAA==.Kijyo:BAABLgAECn8VAAIcAAgJ0hQ1DgBAAQAcAAgJ0hQ1DgBAAQAAAA==.Kishu:BAAALgADCggJDQAAAA==.Kitten:BAAALgAECggJCAAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Kl='Kleokleo:BAAALgAECgEJAQAAAA==.',
Kn='Knutebomb:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.Korlax:BAAALgAECgQJBQAAAA==.',
Kr='Krex:BAAALgADCgYJDQAAAA==.Krossedup:BAAALgADCgcJDgAAAA==.Kryptonikk:BAAALgAECgYJDwAAAA==.Krystal:BAAALgAECgMJBgAAAA==.Kröw:BAABLgAECn8eAAIjAAkJaA4iDQCoAQAjAAkJaA4iDQCoAQAAAA==.',
Ku='Kudrix:BAABLgAECn8oAAIlAAgJGSLVBwCoAgAlAAgJGSLVBwCoAgAAAA==.Kurgaz:BAAALgAECgYJBgAAAA==.Kurø:BAABLgAECn8sAAIPAAkJRR5iHgBvAgAPAAkJRR5iHgBvAgAAAA==.',
Kw='Kwanzie:BAAALgAECgMJAwAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.Kyzen:BAAALgADCgYJBgAAAA==.',
['Kà']='Kàri:BAACLgAFFH8FAAIUAAIJ4gWmSwBwAAAUAAIJ4gWmSwBwAAAuAAQKfxsAAhQACQn7GCAUAIgCABQACQn7GCAUAIgCAAAA.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMPAAcJ6BSZaAC8AQAPAAcJDhSZaAC8AQAmAAMJvBFgFQA/AAAAAA==.Latherfanta:BAAALgAECgcJEQAAAA==.Laurijaydn:BAAALgAECgcJCQAAAA==.Laylâ:BAAALgAECgEJAQAAAA==.',
Le='Lelink:BAAALgAECgcJEgAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leniuum:BAAALgADCgMJBgAAAA==.Leoden:BAAALgADCgUJBAAAAA==.Leopard:BAAALgAECgkJBwAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAABLgAECn8WAAIfAAUJvApLRQDgAAAfAAUJvApLRQDgAAABLgAECgYJCQALAAAAAA==.Lightlana:BAACLgAFFH8TAAIEAAUJXRTsLQAzAQAEAAUJXRTsLQAzAQAuAAQKfyUAAgQACAm5IdAYANQCAAQACAm5IdAYANQCAAAA.Lightwalker:BAAALgAECgUJBQAAAA==.Likeaglove:BAAALgAECgcJDwABLgAFFAQJCQAdAHQHAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8kAAMeAAgJph9sDwCtAgAeAAgJph9sDwCtAgAJAAMJ5QpMbgCKAAAAAA==.Lizzieag:BAECLgAFFH8IAAIYAAMJ4QqKKgDOAAAYAAMJ4QqKKgDOAAAuAAQKfy8AAhgACAlqGQQiAEQCABgACAlqGQQiAEQCAAAA.',
Ll='Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loafsies:BAAALgADCgMJAwAAAA==.Loakai:BAAALgAECgEJAQAAAA==.Lockman:BAAALgADCgMJBAAAAA==.Lockndotz:BAAALgAECgYJEQABLgAECgQJBQALAAAAAA==.Loenil:BAABLgAECn8mAAIEAAgJywz8fwBOAQAEAAgJywz8fwBOAQAAAA==.Lohueng:BAAALgAECgYJEAAAAA==.Loodah:BAAALgAECggJCgAAAA==.Lookee:BAABLgAECn8aAAIOAAYJeBTfhwBLAQAOAAYJeBTfhwBLAQAAAA==.Loranoth:BAAALgADCggJDwAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.Lovecox:BAAALgAECgEJAgAAAA==.',
Lu='Lucielle:BAAALgAECgYJCwAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn84AAIUAAkJziLHAwBtAwAUAAkJziLHAwBtAwAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAYJGQABAJIRAA==.Lustarhymes:BAAALgAECgUJBQAAAA==.',
Ly='Lyxon:BAABLgAECn8fAAIUAAgJrhYYHwAqAgAUAAgJrhYYHwAqAgAAAA==.',
['Lå']='Låw:BAAALgAECgIJBAAAAA==.',
Ma='Maandos:BAAALgADCgcJBwAAAA==.Mabrian:BAAALgADCgcJBwAAAA==.Mael:BAAALgADCgUJBQAAAA==.Mafoôza:BAABLgAECn8uAAIYAAkJOiKxBwDGAgAYAAkJOiKxBwDGAgAAAA==.Magicalama:BAAALgADCgYJCwABLgAFFAQJDgAIAM8YAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgIJAgABLgAECggJHAABAHEXAA==.Magpen:BAAALgADCgMJBgAAAA==.Mahboyblu:BAAALgAECgMJAwAAAA==.Mahndoo:BAACLgAFFH8KAAIOAAQJhwivUwAfAQAOAAQJhwivUwAfAQAuAAQKfyAAAg4ACAmRGo5DAPUBAA4ACAmRGo5DAPUBAAAA.Makto:BAAALgADCgUJCAAAAA==.Malia:BAAALgAECgcJCQAAAA==.Maliciouso:BAABLgAECn8qAAIeAAkJLBstDgC7AgAeAAkJLBstDgC7AgAAAA==.Malédiction:BAABLgAECn8bAAIOAAgJ6RXXdwDiAQAOAAgJ6RXXdwDiAQAAAA==.Mattdemøn:BAAALgAECgMJAwABLgAECggJJgABALMZAA==.Matua:BAAALgAECgMJBAAAAA==.Maymae:BAAALgAECgYJEgAAAA==.',
Me='Medizine:BAAALgAECgEJBAAAAA==.Medon:BAAALgADCgYJBgAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megabonk:BAAALgAECgQJBQABLgAECggJKQAYAH0cAA==.Megademac:BAABLgAECn8fAAIHAAcJIA5ccAAbAQAHAAcJIA5ccAAbAQAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.Metus:BAAALgADCgkJCQAAAA==.',
Mi='Miistral:BAABLgAECn8iAAIEAAgJ6hUBXACbAQAEAAgJ6hUBXACbAQAAAA==.Mimmz:BAAALgADCgEJAQAAAA==.Miniblinks:BAAALgADCgQJAwAAAA==.Minisid:BAABLgAFFH8JAAIOAAMJEQkmbQDbAAAOAAMJEQkmbQDbAAABLgAFFAYJIgAYAPAfAA==.Miriia:BAAALgAECgIJAwAAAA==.Mirshta:BAAALgADCggJEQAAAA==.Missmaam:BAABLgAECn8hAAIcAAcJqyDkBgDxAQAcAAcJqyDkBgDxAQABLgAFFAQJBgAgAPEOAA==.Mistinmae:BAAALgAECgEJAgABLgAECgYJKAAeAD8WAA==.Mistrjenkins:BAAALgAECgYJDQAAAA==.Mistyeva:BAAALgAECgUJBQABLgAECgkJOAAUAM4iAA==.Mixoz:BAAALgAECgQJBAAAAA==.Miyoko:BAAALgADCgIJAgAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQALAAAAAA==.Mokotrize:BAABLgAECn8yAAIGAAkJ/xiSBwA2AgAGAAkJ/xiSBwA2AgAAAA==.Momtok:BAAALgAECgUJBwAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAACLgAFFH8LAAIZAAUJRxEsGgAeAQAZAAUJRxEsGgAeAQAuAAQKfykAAhkACAlhHGwQAJ0CABkACAlhHGwQAJ0CAAAA.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECggJJgABALMZAA==.Mordred:BAABLgAECn8YAAIcAAYJ0wdFGAC0AAAcAAYJ0wdFGAC0AAAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCQAAAA==.',
Mu='Mud:BAAALgAECgUJBwAAAA==.Munchies:BAAALgAECgYJCQAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQABLgAECggJGgAWAE8WAA==.Myrolee:BAABLgAECn8aAAQWAAgJTxbWGgCvAQAWAAgJXhTWGgCvAQAgAAgJkgy1MwBUAQAlAAQJPhHtSwCpAAAAAA==.Myrowrynn:BAAALgAECgYJBgABLgAECggJGgAWAE8WAA==.Myrozond:BAAALgAECgYJDwABLgAECggJGgAWAE8WAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAAEAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIEAAcJZyNNGQDRAgAEAAcJZyNNGQDRAgAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAABLgAECn80AAIlAAkJaiUEAgBBAwAlAAkJaiUEAgBBAwAAAA==.Narset:BAAALgADCgUJBQAAAA==.Nattum:BAAALgADCgMJAwAAAA==.Nayasylpha:BAABLgAECn8sAAIWAAgJxhzxDwCdAgAWAAgJxhzxDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Neown:BAABLgAECn8YAAIOAAYJ7BK6kgA3AQAOAAYJ7BK6kgA3AQABLgAECggJKgAUAEgeAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAABLgAECn8tAAIOAAkJMSGxHgCKAgAOAAkJMSGxHgCKAgAAAA==.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAABLgAECn8bAAIdAAYJ6Qp6NwD6AAAdAAYJ6Qp6NwD6AAAAAA==.Nightknigh:BAAALgAECgEJAgAAAA==.Nirri:BAAALgAECgcJCAAAAA==.Nishendra:BAABLgAECn8aAAITAAkJix3+BgDQAgATAAkJix3+BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAABLgAECn8dAAMBAAgJuQ2/VgBxAQABAAgJuQ2/VgBxAQAIAAYJ+wY4NQDeAAAAAA==.Nitezilla:BAAALgAECgQJBAAAAA==.',
No='Noblok:BAAALgAECgQJBQAAAA==.Nocando:BAACLgAFFH8JAAIdAAQJdAeJFQDoAAAdAAQJdAeJFQDoAAAuAAQKfxgAAh0ACQkLGOYOAFICAB0ACQkLGOYOAFICAAAA.Nofeetpicsyo:BAABLgAECn8xAAIbAAgJQwxzKQBcAQAbAAgJQwxzKQBcAQAAAA==.Nootella:BAABLgAECn8UAAIKAAYJlSIoHgAlAgAKAAYJlSIoHgAlAgABLgAECgkJGwAiAIsXAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAABLgAECn8gAAQEAAYJMCNnSQAGAgAEAAUJCCRnSQAGAgAKAAEJgSLrZwBjAAAGAAEJzx/GNwBWAAAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8dAAIbAAgJGBoMGwAGAgAbAAgJGBoMGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAFFAQJDAAVAE0TAA==.Nylinuya:BAAALgAECgYJEwABLgAFFAQJDAAVAE0TAA==.Nyteskye:BAAALgAECgEJAgAAAA==.Nyxoblivion:BAAALgADCgcJEQAAAA==.',
['Nî']='Nîco:BAABLgAECn8qAAIUAAgJSB7wGABwAgAUAAgJSB7wGABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAACLgAFFH8KAAIWAAQJKguIIwABAQAWAAQJKguIIwABAQAuAAQKfyAAAxYACAlbD0MnAFcBABYACAkID0MnAFcBACUAAQlYFct4ADkAAAAA.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAACLgAFFH8NAAIDAAUJSRmRLgBNAQADAAUJSRmRLgBNAQAuAAQKfzMAAgMACQnQFhcrABUCAAMACQnQFhcrABUCAAAA.Ollphéist:BAAALgAECgYJBgAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECgkJMwATADMXAA==.',
On='Oneall:BAABLgAECn8zAAIZAAgJmxU8HAC5AQAZAAgJmxU8HAC5AQAAAA==.Onehit:BAAALgAECgMJBQAAAA==.Onlyspells:BAABLgAECn8WAAMOAAgJaAm2pwCKAQAOAAgJaAm2pwCKAQAMAAEJnAELEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8lAAIQAAkJJRgIEwCwAQAQAAkJJRgIEwCwAQAAAA==.',
Or='Orchideva:BAAALgADCgEJAQABLgAECgkJOAAUAM4iAA==.Orelikai:BAAALgADCgQJBAAAAA==.Oreoz:BAAALgADCgUJBQAAAA==.',
Ot='Othin:BAABLgAECn8ZAAIUAAgJKRs0GABiAgAUAAgJKRs0GABiAgAAAA==.Ottoshock:BAAALgAECgEJAQAAAA==.',
Pa='Painloa:BAABLgAECn8eAAMmAAgJpAojDwA4AQAmAAgJpAojDwA4AQAPAAYJZwFg7wCfAAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8cAAIiAAkJ8Q7fHACuAQAiAAkJ8Q7fHACuAQAAAA==.Pandadance:BAAALgAECgcJEwAAAA==.Pandakill:BAAALgAECgUJBgAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandaxi:BAAALgAECgIJAgABLgAECggJHwAEAB0hAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAgAAAA==.Papachungus:BAAALgADCgYJCQAAAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJEAALAAAAAA==.Papagenu:BAAALgAECgYJCQABLgAECgYJEAALAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8tAAIOAAkJLyPODwDlAgAOAAkJLyPODwDlAgAAAA==.Pazzie:BAAALgAECgMJBgAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.Phreyja:BAAALgAECgEJAQAAAA==.',
Pm='Pmac:BAABLgAECn8VAAIOAAUJWxBwuAD4AAAOAAUJWxBwuAD4AAABLgAECgcJHwAHACAOAA==.',
Po='Poggie:BAAALgAECgQJBgAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potox:BAAALgAECgIJAgAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Power:BAAALgAECgEJAQAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Primerecall:BAAALgAECgkJAgAAAA==.Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgAECgcJCAAAAA==.',
Pu='Punishment:BAAALgADCgYJCwAAAA==.Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAABLgAECn8vAAMaAAkJpR+4AQCaAgAaAAgJgCG4AQCaAgADAAMJTA7jxgCiAAAAAA==.',
Qa='Qai:BAABLgAECn8iAAMFAAgJkg+aFwBEAQAFAAUJ7BaaFwBEAQANAAgJNgevMACgAAAAAA==.',
Qu='Quan:BAAALgAECgIJBQAAAA==.Quelestraza:BAABLgAECn8cAAITAAgJSBarCwD5AQATAAgJSBarCwD5AQAAAA==.',
Ra='Raewyck:BAABLgAECn88AAIBAAgJpBa8LQD8AQABAAgJpBa8LQD8AQAAAA==.Ragar:BAAALgAECgUJBQABLgAFFAMJCwAYAEUkAA==.Raginbull:BAABLgAECn8jAAIkAAgJVBi5DgDUAQAkAAgJVBi5DgDUAQAAAA==.Raginganja:BAAALgADCgMJBgAAAA==.Ragingmaze:BAABLgAECn8hAAMPAAkJ+A5ETgC1AQAPAAkJYwxETgC1AQAQAAEJpx+qQQBYAAAAAA==.Rainburrow:BAAALgAECggJDAAAAA==.Raptormortis:BAABLgAECn8nAAMJAAkJpRpqDwBVAgAJAAkJpRpqDwBVAgAeAAYJ5BOnSQBUAQAAAA==.Rawd:BAAALgADCgIJAgAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgALAAAAAA==.Raylen:BAAALgAECgYJBgAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgALAAAAAA==.Reinitia:BAAALgAECgUJBgAAAA==.Rellic:BAAALgAECgEJAQAAAA==.Remy:BAAALgAECgcJEAAAAA==.Renkagisa:BAAALgAECgUJBQAAAA==.Renku:BAAALgAECgQJEgAAAA==.Retana:BAAALgAECgQJCAAAAA==.Retrisan:BAAALgAECgUJBQAAAA==.',
Rh='Rhinn:BAABLgAECn8bAAIjAAgJFwufEgBLAQAjAAgJFwufEgBLAQAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAAALgAECgcJEgAAAA==.Ritsuyi:BAAALgAECgEJAQABLgAECgMJBAALAAAAAA==.Ritualbeef:BAAALgADCgYJCAABLgAECgkJDAALAAAAAA==.Riven:BAAALgAECggJDgAAAA==.',
Ro='Roarbear:BAABLgAECn8bAAIYAAkJxxU1FQAhAgAYAAkJxxU1FQAhAgAAAA==.Roastedz:BAABLgAECn8kAAIaAAYJbA6vEgDxAAAaAAYJbA6vEgDxAAAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roodeekay:BAAALgAECgQJCAABLgAECggJMQASAK4fAA==.Roomi:BAABLgAECn8zAAIjAAkJyBvmBQBSAgAjAAkJyBvmBQBSAgAAAA==.Roowar:BAAALgAECgcJEwABLgAECggJMQASAK4fAA==.Rorié:BAAALgADCggJDAAAAA==.Rorthu:BAAALgAECgYJBgAAAA==.Roru:BAABLgAECn8lAAMDAAgJ3huNJQAuAgADAAgJ3huNJQAuAgAaAAMJSwWZVABwAAAAAA==.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgAECgYJBgAAAA==.Ruxman:BAAALgAECgEJAQAAAA==.',
Ry='Ry:BAABLgAECn8VAAIDAAUJcB9PegBnAQADAAUJcB9PegBnAQAAAA==.Ryanna:BAAALgAECgYJCQAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgcJDAAAAA==.',
['Ræ']='Rædiêncë:BAABLgAECn8cAAIEAAkJEwYogwBIAQAEAAkJEwYogwBIAQAAAA==.',
['Rò']='Ròó:BAABLgAECn8xAAQSAAgJrh/rCAACAwASAAgJrh/rCAACAwAnAAMJLR5+FAC1AAAoAAIJiSNDGABdAAAAAA==.',
Sa='Saevio:BAABLgAECn8kAAIPAAgJVxybMwANAgAPAAgJVxybMwANAgAAAA==.Sallean:BAAALgAECgEJAQAAAA==.Salvader:BAAALgAECgcJCAAAAA==.Sanctus:BAAALgAECgYJCQAAAA==.Sanlorastik:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwALAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAACLgAFFH8HAAIPAAMJ1BWfYQAJAQAPAAMJ1BWfYQAJAQAuAAQKfygAAw8ACAnQGlhCADACAA8ACAnQGlhCADACACYABglhEVcRABkBAAAA.Saso:BAAALgAECgYJBwAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAIKAAMJ/hULDgD3AAAKAAMJ/hULDgD3AAAuAAQKfxcAAgoACAnGJWMEACcDAAoACAnGJWMEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJBAAAAA==.Scoot:BAEALgAFFAIJAgABLgAFFAYJEwAdAPodAA==.Scotchnsoda:BAACLgAFFH8WAAMdAAQJCRAqEgAJAQAdAAQJCRAqEgAJAQAiAAEJJgNwPAA5AAAuAAQKfy4ABB0ACQnuE3spAKYBAB0ACQnfE3spAKYBACIABgnCE+AlAHEBABsAAQlyANFrABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgAECgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgUJDwAAAA==.Selenegosa:BAABLgAECn8fAAMhAAgJnBWACwA9AQAhAAYJGBeACwA9AQARAAYJNBBHSADgAAABLgAECggJMgABAH4jAA==.Seran:BAABLgAECn8jAAIBAAkJbSCQCgDfAgABAAkJbSCQCgDfAgAAAA==.Serenade:BAABLgAECn8xAAIZAAkJMBFoGwDAAQAZAAkJMBFoGwDAAQAAAA==.Severyne:BAABLgAECn8oAAIUAAgJIiUUBQA8AwAUAAgJIiUUBQA8AwABLgAFFAUJCAAgAGsgAA==.',
Sh='Shadowchad:BAAALgADCgUJCAAAAA==.Shadowmeld:BAAALgAECgcJEAAAAA==.Shadowpump:BAAALgAECgYJDAAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgAECgIJAgAAAA==.Shallanaera:BAAALgAECgYJBgAAAA==.Shamanco:BAAALgAECgYJBwAAAA==.Shamanu:BAAALgAECgcJEQABLgAECgcJGAAEAGcjAA==.Shamsel:BAABLgAECn8xAAIbAAgJNg0WJwBsAQAbAAgJNg0WJwBsAQAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8ZAAINAAYJ5hVlBAB3AQANAAYJ5hVlBAB3AQAuAAQKfygAAg0ACQn2IEICABEDAA0ACQn2IEICABEDAAAA.Shikes:BAABLgAFFH8GAAIOAAMJUQ7CZgDoAAAOAAMJUQ7CZgDoAAAAAA==.Shinpaku:BAAALgADCgIJAgAAAA==.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJDAAAAA==.Shorin:BAAALgADCgYJCwAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAACLgAFFH8GAAIUAAMJtSBrIAAjAQAUAAMJtSBrIAAjAQAuAAQKfzMAAxQACQmZIwQEAFADABQACAliJQQEAFADABkAAQn1Cn9uAEIAAAAA.Shweatyballs:BAABLgAECn8XAAIOAAYJahtGjQC4AQAOAAYJahtGjQC4AQAAAA==.Shóki:BAAALgAECggJCAAAAA==.',
Si='Sidetrax:BAAALgADCgQJBAAAAA==.Silran:BAABLgAECn8XAAIEAAgJCwxRoAAVAQAEAAgJCwxRoAAVAQAAAA==.Silverwings:BAAALgADCgEJAQAAAA==.Simmara:BAABLgAECn8hAAMBAAkJKxFyNgDZAQABAAkJKxFyNgDZAQAIAAQJggSGJACmAAAAAA==.Sinistar:BAAALgAECgEJAQAAAA==.Sinner:BAECLgAFFH8TAAIdAAYJ+h1mAgAZAgAdAAYJ+h1mAgAZAgAuAAQKfxoAAx0ACQkXHdIHAM4CAB0ACQkXHdIHAM4CABsAAwnuAxNZAFcAAAAA.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAcJHgAkAN4kAA==.Skruff:BAAALgAECgIJAwAAAA==.',
Sl='Slamuraijack:BAAALgAECgUJAgAAAA==.Slayngin:BAAALgAECgQJCQABLgAECgUJCAALAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAFFAMJAwAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAABLgADCgYJBgALAAAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgIJAgAAAA==.Solweaver:BAAALgADCgEJAQAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAABLgAECn8hAAIGAAgJ5ha8DQC6AQAGAAgJ5ha8DQC6AQAAAA==.',
Sq='Squirrely:BAAALgADCgIJAgABLgAECggJJgABALMZAA==.Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAABLgAECn8bAAIQAAgJ0gQxLADIAAAQAAgJ0gQxLADIAAAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Stonystark:BAAALgAECgEJBAAAAA==.Straam:BAACLgAFFH8SAAIeAAQJFBfIHgA2AQAeAAQJFBfIHgA2AQAuAAQKf0UAAh4ACQmIIioFADsDAB4ACQmIIioFADsDAAAA.Stumpe:BAAALgAECgIJAwAAAA==.Stupidity:BAAALgAECgYJBgAAAA==.Støney:BAABLgAECn81AAIOAAkJmA5FUgDJAQAOAAkJmA5FUgDJAQAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAcJHgAkAN4kAA==.Subroutine:BAABLgAECn8WAAICAAgJHh/4DgDKAgACAAgJHh/4DgDKAgABLgAFFAcJHgAkAN4kAA==.Subtractive:BAACLgAFFH8eAAIkAAcJ3iTnAACEAgAkAAcJ3iTnAACEAgAuAAQKfxsAAiQACAmmJiQBAIYDACQACAmmJiQBAIYDAAAA.Superiorha:BAABLgAECn8XAAIlAAkJJh1pBwCvAgAlAAkJJh1pBwCvAgAAAA==.',
Sw='Swagchamp:BAAALgADCgQJBQABLgAECgcJCAALAAAAAA==.Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIOAAIJ2SHQMwDKAAAOAAIJ2SHQMwDKAAAuAAQKfyIAAg4ACQk5I7oFAKcDAA4ACQk5I7oFAKcDAAAA.',
Sy='Sylthara:BAABLgAECn8gAAIeAAcJYhQIOQCaAQAeAAcJYhQIOQCaAQAAAA==.Syrellis:BAAALgAECgEJAgAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8sAAIcAAgJBxeMCADAAQAcAAgJBxeMCADAAQAAAA==.Tahle:BAAALgAECgIJAgAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAABLgAECn8dAAIOAAYJjRc2fABiAQAOAAYJjRc2fABiAQAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tatonka:BAAALgADCgYJAwAAAA==.Tavin:BAAALgAECgUJBQAAAA==.Tazchem:BAAALgAECgQJBQAAAA==.',
Te='Techboar:BAAALgAECgEJAQAAAA==.Teinuya:BAACLgAFFH8MAAMVAAQJTROUAgBKAQAVAAQJMhOUAgBKAQADAAIJMAvQjQCBAAAuAAQKfzoABBUACQmVHxMBAOACABUACQkaHxMBAOACABoABgkSHQUMAAICAAMABAkCFyaVAPsAAAAA.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Temparia:BAAALgAECgYJBgAAAA==.Tenderfiddle:BAAALgAECgYJEwAAAA==.Tenochitilan:BAAALgAECggJDQAAAA==.Tenuous:BAABLgAECn8ZAAMZAAgJzBlfFAAIAgAZAAgJzBlfFAAIAgAUAAQJ6QZijAB6AAAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAFFAMJBgAUALUgAA==.Thanar:BAAALgADCgEJAQAAAA==.Thevelo:BAAALgADCgcJBwABLgAECgYJDgALAAAAAA==.Thisistheway:BAACLgAFFH8IAAIkAAMJ0hQqFQDNAAAkAAMJ0hQqFQDNAAAuAAQKfy0AAiQACQnjHFwGAIQCACQACQnjHFwGAIQCAAEuAAUUBAkRABMAxBkA.Thoorz:BAAALgAECgMJBAAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAABLgAECn8XAAMBAAYJfxglYgBUAQABAAYJvhclYgBUAQACAAYJ0QqmVAD4AAABLgAECgMJBAALAAAAAA==.Thothh:BAABLgAECn8WAAQiAAYJ1A1MLwAzAQAiAAYJWg1MLwAzAQAdAAIJXQ+1bAB3AAAbAAIJEgnDXgBeAAAAAA==.Thraxacious:BAACLgAFFH8MAAIFAAQJbBFNBQA6AQAFAAQJbBFNBQA6AQAuAAQKfyAAAgUACAnAGAUMAMQBAAUACAnAGAUMAMQBAAAA.Thulcandra:BAABLgAECn8UAAIOAAYJxB/fYwARAgAOAAYJxB/fYwARAgAAAA==.Thulsadoomm:BAABLgAECn8gAAIQAAYJDh6UEQDyAQAQAAYJDh6UEQDyAQAAAA==.Thundermay:BAABLgAECn8oAAIeAAYJPxbaQQB0AQAeAAYJPxbaQQB0AQAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAABLgAECn8nAAIkAAYJ5w20JwDMAAAkAAYJ5w20JwDMAAAAAA==.Tigó:BAABLgAECn8oAAIEAAkJjSAeDgDbAgAEAAkJjSAeDgDbAgAAAA==.Tigölebittie:BAABLgAECn8qAAMUAAkJTBJ3JwDyAQAUAAkJTBJ3JwDyAQAZAAQJcw8FVwCDAAAAAA==.Tiifa:BAAALgADCgIJAQAAAA==.Tinkerrbella:BAABLgAECn8WAAQBAAcJvQ3yUwBsAQABAAcJvQ3yUwBsAQACAAUJFgIZbQCKAAAIAAIJsgHjTQBEAAABLgAFFAYJGQABAJIRAA==.Tireliaa:BAAALgAECgUJCAAAAA==.Tizzymami:BAAALgADCgQJBAAAAA==.',
Tj='Tjnewt:BAAALgADCgkJCQAAAA==.',
To='Toatsie:BAABLgAECn8VAAIEAAgJJBekRwDQAQAEAAgJJBekRwDQAQAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Tribulationz:BAAALgAECgQJBAABLgAECggJLAAJANMbAA==.Trumpybear:BAABLgAECn8fAAIEAAgJHSEgGgCJAgAEAAgJHSEgGgCJAgAAAA==.',
Ts='Tsun:BAABLgAECn80AAMXAAkJWBqhCgAXAgAXAAgJaByhCgAXAgAkAAkJbxKsDQDlAQAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgcJCgABLgAECgcJGAAEAGcjAA==.',
Ud='Uddertrouble:BAEBLgAECn8cAAIBAAgJcRcKOwDIAQABAAgJcRcKOwDIAQAAAA==.',
Uf='Ufos:BAAALgADCggJHgAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAOANkhAA==.',
Ul='Ulfgrim:BAAALgADCggJEwAAAA==.',
Un='Uncletat:BAABLgAECn87AAQdAAkJuySeAQCLAwAdAAkJuySeAQCLAwAiAAYJmCFWDwBJAgAbAAEJHRQoawA4AAAAAA==.',
Ur='Urmada:BAABLgAECn8vAAIOAAkJPA0OUADPAQAOAAkJPA0OUADPAQAAAA==.Urmami:BAABLgAECn8rAAIDAAkJrRMlLwAEAgADAAkJrRMlLwAEAgAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Uz='Uzui:BAAALgAECgcJDgAAAA==.',
Va='Vahnt:BAABLgAECn8yAAIeAAgJGxh1IAAcAgAeAAgJGxh1IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8rAAIEAAkJLh57KgA2AgAEAAkJLh57KgA2AgAAAA==.Vampire:BAABLgAECn8VAAIHAAkJ6hrsFQB3AgAHAAkJ6hrsFQB3AgAAAA==.Vampyre:BAACLgAFFH8cAAIQAAgJexWTBQDUAQAQAAgJexWTBQDUAQAuAAQKfx4AAhAACQnFIfoCADMDABAACQnFIfoCADMDAAAA.Vanadie:BAAALgAECgYJBgAAAA==.Vanta:BAAALgADCgcJDQAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJBAAAAA==.Vendettá:BAABLgAECn8UAAIeAAYJwRgNTQBHAQAeAAYJwRgNTQBHAQAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgAECgQJBAAAAA==.',
Vi='Vidi:BAAALgAECgUJBQAAAA==.Virala:BAAALgAECgUJBQAAAA==.Visenya:BAAALgAECgUJCQAAAA==.Vishontey:BAAALgAECgQJBAAAAA==.Vitaminn:BAABLgAECn8uAAQEAAkJVx2FGACSAgAEAAkJVx2FGACSAgAKAAIJTwZkigBUAAAGAAEJnBf7PgBCAAAAAA==.Vithiris:BAAALgADCgYJBgAAAA==.',
Vk='Vk:BAAALgAECgkJEwAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAwAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECgkJDgAAAA==.Vynnii:BAAALgAECggJCAABLgAECgkJDgALAAAAAA==.Vynora:BAAALgAECgkJCwAAAA==.Vyrse:BAAALgAFFAQJBAAAAA==.',
Wa='Wafflez:BAAALgAECgcJBwAAAA==.Walterlight:BAAALgAECgEJAQAAAA==.Wampa:BAAALgAECgYJBwAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wasabii:BAAALgAFFAIJAgAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgQJCAAAAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8LAAIYAAMJRSRRDwARAQAYAAMJRSRRDwARAQAuAAQKfzoAAxcACQkeJQEEALwCABgABwmvJZkNAOkCABcACQmZIwEEALwCAAAA.Windente:BAABLgAECn8gAAMBAAkJ5RUUPgC+AQABAAgJJRYUPgC+AQACAAQJ/AgEZwCjAAAAAA==.Wing:BAEBLgAFFH8HAAIEAAMJiyBaNgAgAQAEAAMJiyBaNgAgAQABLgAFFAYJEwAdAPodAA==.Wiseau:BAABLgAECn8mAAMBAAgJsxkcMQDuAQABAAgJsxkcMQDuAQACAAEJ4wMElAAmAAAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgYJCwAAAA==.',
Wu='Wulfhound:BAABLgAECn8VAAIBAAgJjRb7MwDjAQABAAgJjRb7MwDjAQAAAA==.Wulfnbolt:BAAALgADCgIJAgAAAA==.Wulfsblood:BAAALgADCgQJBAABLgAECggJFQABAI0WAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECggJHgAAAQ==.',
Xe='Xexhu:BAAALgAECgcJBwAAAA==.',
Xp='Xpand:BAAALgADCgYJCAAAAA==.',
Xu='Xuen:BAAALgAECgYJEgAAAA==.',
Ya='Yazbrez:BAAALgADCgEJAQABLgAECgYJDwALAAAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zaeluna:BAABLgAECn8zAAINAAgJZiB1AwDWAgANAAgJZiB1AwDWAgAAAA==.Zanikan:BAAALgAECgkJAgAAAA==.Zanzer:BAAALgAECgUJEAAAAA==.Zathara:BAABLgAECn8gAAIFAAkJWxVMCAAYAgAFAAkJWxVMCAAYAgAAAA==.',
Ze='Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zeroshot:BAAALgAECgEJBQAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.',
Zo='Zorvax:BAAALgAECgUJCAAAAA==.',
Zp='Zpazzie:BAAALgAECgIJBgAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgAECgEJAQAAAA==.',
['Zö']='Zörö:BAABLgAECn8YAAIPAAkJ5xcpMAAbAgAPAAkJ5xcpMAAbAgAAAA==.',
['Ãr']='Ãrx:BAAALgAECgIJAgAAAA==.',
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
