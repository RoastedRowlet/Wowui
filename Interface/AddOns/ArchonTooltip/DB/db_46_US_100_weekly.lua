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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','Druid-Feral','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Restoration','Hunter-Survival','Paladin-Holy','Druid-Guardian','Unknown-Unknown','Mage-Fire','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Rogue-Subtlety','Evoker-Preservation','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Monk-Brewmaster','Priest-Shadow','Warrior-Arms','Druid-Balance','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Restoration','Priest-Holy','Monk-Mistweaver','Evoker-Devastation','Priest-Discipline','Warrior-Protection','Shaman-Elemental','Monk-Windwalker','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aamodar:BAABLgAECn8mAAMBAAgJ9BH6TQC0AQABAAgJ9BH6TQC0AQACAAMJ/gdgKQBtAAAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAACLgAFFH8HAAIDAAQJsA5PWAASAQADAAQJsA5PWAASAQAuAAQKf00AAgMACQmqHBoXAJgCAAMACQmqHBoXAJgCAAAA.Abhorrent:BAAALgAECgEJAQAAAA==.',
Ac='Acathisia:BAAALgAECgEJAQAAAA==.Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgQJBAAAAA==.Adino:BAABLgAECn87AAIBAAkJHRFOPADrAQABAAkJHRFOPADrAQAAAA==.Adrial:BAAALgAECgEJAQAAAA==.Adric:BAAALgAECgEJAQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAACLgAFFH8dAAIEAAUJnh4+KwBaAQAEAAUJnh4+KwBaAQAuAAQKfycAAgQACAkiI/AOABcDAAQACAkiI/AOABcDAAAA.Aetherz:BAAALgAECgEJAQAAAA==.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.Agrolazor:BAAALgAECgIJAgAAAA==.',
Ah='Ahote:BAACLgAFFH8LAAIFAAQJpSRkAgCuAQAFAAQJpSRkAgCuAQAuAAQKfx4AAgUABQlKJjAJAC4CAAUABQlKJjAJAC4CAAAA.Ahtee:BAABLgAECn89AAMEAAkJCSAfFgC8AgAEAAkJCSAfFgC8AgAGAAQJdwjFOgBuAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.Akuprovik:BAABLgAECn8uAAMHAAkJ5xAHWgB2AQAHAAkJLQ0HWgB2AQAIAAUJnxipKgAkAQAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Alanthos:BAAALgAECgQJBAAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgAECgcJBwABLgAFFAQJCgABAHgSAA==.Alexandraus:BAABLgAECn8gAAIJAAkJWxV1HQBXAgAJAAkJWxV1HQBXAgAAAA==.Alexiea:BAAALgAECgQJBAAAAA==.Algodon:BAABLgAFFH8GAAIEAAMJkQx8dgDBAAAEAAMJkQx8dgDBAAAAAA==.Allenduin:BAAALgADCgEJAQAAAA==.Almeads:BAAALgAECgEJAQAAAA==.Alonias:BAAALgAECgUJCQAAAA==.Alseena:BAABLgAECn8gAAIEAAcJqBkyfgBvAQAEAAcJqBkyfgBvAQAAAA==.Alysiita:BAAALgAECgEJAQAAAA==.',
Am='Amadeux:BAACLgAFFH8UAAIKAAYJiRWHCACFAQAKAAYJiRWHCACFAQAuAAQKfyYAAgoACQnqHHAHAIACAAoACQnqHHAHAIACAAAA.Amarawr:BAAALgADCgYJBgABLgAFFAYJFAAKAIkVAA==.Amicae:BAAALgADCgcJCAAAAA==.Ammandor:BAAALgAECgQJBAAAAA==.Amun:BAAALgAECgcJBwAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgYJDgAAAA==.Anform:BAAALgAECgIJAgAAAA==.Anryn:BAAALgAECgYJBgABLgAFFAUJHQAEAJ4eAA==.Anthais:BAAALgAECgQJBAAAAA==.Anvar:BAACLgAFFH8KAAIBAAQJeBKhRQAbAQABAAQJeBKhRQAbAQAuAAQKfx8AAgEACQkEHn8cAHYCAAEACQkEHn8cAHYCAAAA.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgYJCQAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn9FAAILAAkJ+SFJBABTAwALAAkJ+SFJBABTAwAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Arianrhod:BAAALgAECgQJBAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arunis:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECggJDAAAAA==.',
As='Astolpho:BAAALgADCgEJAQAAAA==.',
At='Atrumdeus:BAABLgAECn9bAAIEAAkJhiAkDQD6AgAEAAkJhiAkDQD6AgAAAA==.',
Au='Audiamer:BAABLgAECn8YAAMMAAkJwxVmEgDEAQAMAAgJnxZmEgDEAQAFAAkJbgoxFwBVAQAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQANAAAAAA==.Awkykit:BAABLgAECn8fAAIOAAgJqAX4CADxAAAOAAgJqAX4CADxAAAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAIMAAYJVxB+FwD/AAAMAAYJVxB+FwD/AAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Baloou:BAAALgAECgEJAQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8tAAIPAAgJ2htEMgBNAgAPAAgJ2htEMgBNAgAAAA==.Bannann:BAAALgAECgEJAQAAAA==.Banned:BAAALgAECgQJBQABLgAFFAIJCAADACshAA==.Bariôn:BAAALgAECgQJBwAAAA==.Barney:BAAALgADCgYJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAgJLwAQAJQjAA==.Beaklondemon:BAAALgAFFAIJAwABLgAFFAgJLwAQAJQjAA==.Beaksbigdk:BAACLgAFFH8vAAQQAAgJlCMGBgC7AgAQAAcJlCMGBgC7AgARAAEJAACnEQBmAAASAAEJJRD8JgBDAAAuAAQKf0EAAxAACQk6JjwMAAkDABAACQkXJjwMAAkDABEACAmnJJYHAJ4CAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAABLgAECn8ZAAMQAAgJFRCTfwCEAQAQAAgJ1A+TfwCEAQARAAcJ7gT2OACtAAAAAA==.Bearsmonk:BAAALgAECgUJDwABLgAECgYJHAAFAPgKAA==.Beedo:BAAALgAECgEJAgAAAA==.Beef:BAAALgAECgYJBgABLgAFFAUJDgATALgcAA==.Beefknight:BAAALgAECgMJAwAAAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAABLgAECn8eAAIUAAkJJQwJGgDFAQAUAAkJJQwJGgDFAQAAAA==.Belldia:BAACLgAFFH8cAAIBAAcJxw/SEQDFAQABAAcJxw/SEQDFAQAuAAQKf0sAAwEACQkCItQSALcCAAEACQkCItQSALcCAAIABQnTDaZQAAsBAAAA.Beni:BAAALgAECgUJDAAAAA==.Beniima:BAABLgAECn8tAAIPAAkJlRq2IQCUAgAPAAkJlRq2IQCUAgAAAA==.Benimarú:BAAALgAECgQJBAAAAA==.Bennylickz:BAABLgAECn85AAMVAAkJmxgwDQD6AQAVAAgJXhcwDQD6AQATAAcJNxTJJgCpAQAAAA==.',
Bi='Bibby:BAAALgAECgYJEAAAAA==.Bibi:BAAALgAECgQJBAAAAA==.Bigpapas:BAAALgAECggJDgABLgAFFAQJDgAWALsNAA==.Birdbear:BAABLgAECn8cAAMFAAYJ+ApXJgDTAAAFAAYJ+ApXJgDTAAAJAAUJeAvsdwDMAAAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAFFAUJDgAXAFUUAA==.Bloopmasta:BAAALgAECgcJAQAAAA==.Blufox:BAABLgAECn8cAAIEAAgJPCSXEwDLAgAEAAgJPCSXEwDLAgAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAPANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgIJAgABLgAECgYJFgAHAHMeAA==.Bodytea:BAAALgADCgcJBwAAAA==.',
Br='Brainpower:BAAALgAECgYJBgAAAA==.Brandawn:BAAALgADCgYJBgABLgAFFAMJBwAYAKMVAA==.Broherum:BAAALgAECgEJAgAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.Brunia:BAAALgADCgIJAgAAAA==.',
Bu='Bubonicmyro:BAAALgAECgMJAwABLgAECggJGgAZAE8WAA==.Buckbeak:BAAALgAECgYJDAAAAA==.Bulgingtotem:BAAALgAECgQJBAAAAA==.Busting:BAAALgAECgYJEAAAAA==.Buttmucker:BAAALgAECgIJBgABLgAECgkJLAAaAJ8eAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAIJAgAAAA==.',
By='Byebye:BAAALgAECgkJBgAAAA==.',
['Bà']='Bàhamut:BAAALgAECgYJEwAAAA==.',
['Bå']='Båemax:BAABLgAECn8hAAMbAAgJmxFkHwBeAQAbAAgJQA5kHwBeAQAWAAcJVg1QQwA3AQAAAA==.',
Ca='Caelestos:BAABLgAECn8ZAAMKAAgJiBsJEAAwAgAKAAcJiBsJEAAwAgACAAcJvAprHwCwAAAAAA==.Castar:BAAALgADCgIJAgAAAA==.Catalella:BAAALgAECgcJBgAAAA==.',
Cc='Ccwwds:BAAALgADCgYJDQABLgAFFAMJBQAPADEIAA==.',
Ce='Celypzo:BAAALgADCgkJCQAAAA==.Cewkie:BAABLgAECn8vAAIWAAgJ8Bp3FwAxAgAWAAgJ8Bp3FwAxAgAAAA==.',
Ch='Chaulock:BAAALgAECgcJCAAAAA==.Chausup:BAAALgADCgQJBAABLgAECggJJwAEAKQkAA==.Chautime:BAABLgAECn8nAAIEAAgJpCTCBwBYAwAEAAgJpCTCBwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgcJCwANAAAAAA==.Chemdizz:BAAALgAECggJEgAAAA==.Chialliance:BAABLgAECn8lAAMcAAkJrhOMHADhAQAcAAkJrhOMHADhAQAJAAEJowGo6gAaAAAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAgJIwAMAMgSAA==.Chknsaladin:BAAALgAECgEJAQAAAA==.Chocö:BAAALgAECgYJCAAAAA==.Choujisan:BAABLgAECn8bAAIWAAcJGhEmOwBYAQAWAAcJGhEmOwBYAQABLgAFFAMJCgAEAO8XAA==.Chrysamere:BAAALgADCgcJDQAAAA==.Chugrar:BAAALgADCggJDQAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8gAAIKAAkJuB+MAwDwAgAKAAkJuB+MAwDwAgAAAA==.Clawlock:BAAALgAECgYJBgAAAA==.Cloft:BAAALgAECgkJDwAAAA==.Clumzylock:BAABLgAECn8sAAMDAAkJTxOCNAAGAgADAAkJTxOCNAAGAgAdAAYJ+QsXOADUAAAAAA==.Clumzymage:BAAALgAECgIJAwABLgAECgkJLAADAE8TAA==.',
Co='Code:BAACLgAFFH8FAAIUAAIJkxnCMACZAAAUAAIJkxnCMACZAAAuAAQKfx8AAhQACQm9IskHABQDABQACQm9IskHABQDAAAA.Cohk:BAAALgADCgQJBAAAAA==.Consfearacy:BAAALgAECggJCgAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8jAAIEAAcJCB+FUgDPAQAEAAcJCB+FUgDPAQAAAA==.Corrl:BAABLgAECn8VAAIPAAcJSRhfigBfAQAPAAcJSRhfigBfAQABLgAECgcJIwAEAAgfAA==.',
Cr='Craventail:BAAALgAECgYJBwAAAA==.Crayzie:BAAALgADCgEJAQAAAA==.Crazyeye:BAAALgADCgUJBQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgAFFAEJAQABLgAFFAMJBQAQAAEMAA==.Creatrix:BAAALgADCgcJBwAAAA==.Crossblesser:BAAALgAECgEJAQAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuchito:BAAALgADCgUJBQAAAA==.Cuma:BAAALgAECgEJBgAAAA==.Cumb:BAABLgAECn8WAAMHAAYJcx5oTgCXAQAHAAYJYRxoTgCXAQAeAAIJnxDSMwAxAAAAAA==.Curatoria:BAAALgAECgYJEgAAAA==.',
Cw='Cwood:BAAALgAECgEJAQABLgAFFAMJBQAPADEIAA==.Cwwddsz:BAAALgAECgEJAQABLgAFFAMJBQAPADEIAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgYJDAAAAA==.',
Da='Daioh:BAAALgADCgEJAQAAAA==.Daladin:BAAALgADCgEJAQAAAA==.Dalanos:BAAALgADCgUJBQAAAA==.Damacraze:BAACLgAFFH8HAAIBAAIJlR16dgChAAABAAIJlR16dgChAAAuAAQKfx4AAgEACAm6IbUQALQCAAEACAm6IbUQALQCAAAA.Darkbluerose:BAABLgAECn8XAAMCAAYJrQfdJQCDAAAKAAUJLgXKIQDJAAACAAYJVAbdJQCDAAAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmay:BAAALgADCgcJBwABLgAECggJNgAfAAoUAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAABLgAECn8eAAILAAkJ8AeINQB4AQALAAkJ8AeINQB4AQAAAA==.Daxine:BAAALgAECgkJDwAAAA==.',
De='Deadboy:BAAALgADCggJCgAAAA==.Deadroar:BAAALgAFFAIJAwABLgAFFAIJCAAMAGEUAA==.Deadwill:BAAALgAECgMJAwAAAA==.Deaminase:BAABLgAECn85AAIPAAgJlSDjIgCPAgAPAAgJlSDjIgCPAgAAAA==.Deathknell:BAABLgAFFH8IAAIQAAMJKAtfpQDNAAAQAAMJKAtfpQDNAAAAAA==.Decypher:BAABLgAECn8nAAIgAAkJwRgVEQBXAgAgAAkJwRgVEQBXAgAAAA==.Deepdeath:BAABLgAFFH8HAAIbAAQJoRohEQBOAQAbAAQJoRohEQBOAQAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAABLgAECn8aAAIfAAgJexoyGgB1AgAfAAgJexoyGgB1AgAAAA==.Demidru:BAABLgAECn8qAAIcAAcJ4xynGQD8AQAcAAcJ4xynGQD8AQAAAA==.Demonboar:BAABLgAECn8cAAMIAAgJOBOUHgCBAQAIAAgJOBOUHgCBAQAHAAYJPwSUmwDhAAAAAA==.Demonrocky:BAAALgADCgkJCwAAAA==.Demontomato:BAAALgAFFAIJAwAAAA==.Demunic:BAACLgAFFH8IAAMeAAQJnAJlDQBqAAAIAAMJlAIYJAB5AAAeAAMJgwJlDQBqAAAuAAQKfxgAAh4ACAnHBdwXAN8AAB4ACAnHBdwXAN8AAAAA.Dennis:BAAALgAECgIJBQAAAA==.Derringer:BAAALgAECgkJDQAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dharin:BAAALgAECgEJAQAAAA==.Dhqt:BAAALgAECgMJBQABLgAFFAMJBQAQAAEMAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dihnnis:BAAALgAECgMJBgAAAA==.Dingbangow:BAAALgAECgUJCwAAAA==.Discoinferno:BAAALgAECgIJAgAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAABLgAECn8cAAIIAAgJlBQnGQC0AQAIAAgJlBQnGQC0AQAAAA==.',
Dk='Dktyler:BAAALgADCgQJBAABLgAFFAQJCAAeAJwCAA==.',
Do='Doneza:BAAALgAECgQJBAAAAA==.Donki:BAABLgAFFH8FAAIQAAUJ1gk8fAAKAQAQAAUJ1gk8fAAKAQAAAA==.Donothingwin:BAACLgAFFH8IAAIDAAIJKyHehgCyAAADAAIJKyHehgCyAAAuAAQKfyUAAwMACQl/Jt0DAH4DAAMACQl/Jt0DAH4DAB0AAwkKJZgnACUBAAAA.Doomgirl:BAAALgAECgkJDwAAAA==.Dotalott:BAAALgAECggJBQAAAA==.Doublelift:BAABLgAFFH8IAAMaAAQJoBBOGgASAQAaAAQJoBBOGgASAQAgAAEJ6Q9NNgAyAAAAAA==.',
Dr='Dragondeznut:BAAALgAECgIJAgAAAA==.Drakblak:BAABLgAECn8jAAIgAAkJRBQZGwADAgAgAAkJRBQZGwADAgAAAA==.Drakisara:BAAALgAECgYJBQABLgAECgQJBQANAAAAAA==.Draukarí:BAABLgAECn8sAAQXAAkJfB5TAQDlAgAXAAkJQh5TAQDlAgADAAcJYRzvKABtAgAdAAEJiB+5XwBQAAAAAA==.Drayer:BAABLgAECn8xAAILAAgJahHzNQB1AQALAAgJahHzNQB1AQAAAA==.Dreivyn:BAAALgAECgQJBwAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAABLgAECn8hAAIHAAkJABklJgAxAgAHAAkJABklJgAxAgAAAA==.Drunkenmist:BAABLgAECn8pAAIhAAgJnBChNQCXAQAhAAgJnBChNQCXAQAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8aAAMTAAYJVBy+GACWAQATAAYJVBy+GACWAQAiAAEJAAChEgAAAAAuAAQKfy8AAxMACQllIo0GAO8CABMACQllIo0GAO8CACIABgkIFVYaAGEBAAAA.',
Du='Dudley:BAAALgAECgUJBwAAAA==.Dumbledork:BAAALgAECgEJAwAAAA==.Dundundun:BAAALgAECggJCgAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAABLgAECn8cAAMBAAkJXwkEXQCKAQABAAkJXwkEXQCKAQACAAEJrwDWmwAQAAAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgAECgQJBQABLgAFFAgJLwAQAJQjAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAACLgAFFH8JAAIjAAMJvhFXMADIAAAjAAMJvhFXMADIAAAuAAQKfx0AAiMACQkPHeAGAA4DACMACQkPHeAGAA4DAAAA.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8jAAMCAAcJ9BWRCgC3AQACAAcJ4RWRCgC3AQABAAQJygi/VAD1AAAuAAQKfy8AAwIACQlbI9MCALYCAAIACQlbI9MCALYCAAEAAgljFhPmAHkAAAAA.',
Eg='Eggdrop:BAACLgAFFH8GAAIWAAMJAhjvLwDqAAAWAAMJAhjvLwDqAAAuAAQKfzgAAhYACQnaH2IIANkCABYACQnaH2IIANkCAAAA.Egufro:BAAALgAECgYJBgABLgAFFAQJFAAYAIcRAA==.',
Eh='Ehgu:BAACLgAFFH8UAAIYAAQJhxG8CQAfAQAYAAQJhxG8CQAfAQAuAAQKfzIAAhgACQl8HLYGAGYCABgACQl8HLYGAGYCAAAA.',
Ei='Eismond:BAABLgAFFH8HAAIRAAMJ4wiWLACSAAARAAMJ4wiWLACSAAAAAA==.',
El='Eleaya:BAAALgAECgIJAgAAAA==.Elediyn:BAAALgAECgMJBgAAAA==.Eleverclear:BAABLgAECn8YAAMLAAcJWRSpPgB+AQALAAcJWRSpPgB+AQAEAAIJXw+8PwFoAAAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAABLgAECn8UAAIEAAgJbAZqrwAdAQAEAAgJbAZqrwAdAQAAAA==.',
Em='Emidget:BAABLgAECn8hAAIPAAgJsRakUADnAQAPAAgJsRakUADnAQAAAA==.',
En='Endervish:BAAALgAECgYJCwABLgAFFAQJCgABAC0NAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.',
Er='Erhmer:BAAALgAECgkJDwAAAA==.Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAABLgAECn8XAAIQAAYJqAoHzwDnAAAQAAYJqAoHzwDnAAAAAA==.',
Fa='Faaith:BAAALgADCgQJBAAAAA==.Fabermor:BAAALgAECgEJAQAAAA==.Fairygon:BAAALgAECgUJBQAAAA==.Fairyhunter:BAAALgAECgYJBwAAAA==.Fairymonk:BAACLgAFFH8FAAIhAAMJnRXtNgDAAAAhAAMJnRXtNgDAAAAuAAQKfxUAAyEABgl1G+wsAMQBACEABgl1G+wsAMQBABkAAgm9ExV4AFQAAAAA.Fangrat:BAAALgAECgEJAgABLgAFFAMJBQAQAAEMAA==.Fariona:BAAALgADCggJCgAAAA==.Fartbarf:BAABLgAECn8kAAIDAAgJcxJ4VADKAQADAAgJcxJ4VADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Fatfatfat:BAABLgAFFH8IAAIMAAIJYRSEJgB8AAAMAAIJYRSEJgB8AAAAAA==.Fatshark:BAAALgAECgEJAQABLgAFFAIJCAAMAGEUAA==.Faya:BAAALgADCgUJBQABLgAFFAQJCgABAHgSAA==.',
Fe='Fennicuss:BAAALgAECgEJAgABLgAFFAUJBQAQANYJAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAABLgAECn8YAAIhAAgJpgaLXQD3AAAhAAgJpgaLXQD3AAAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAgJKgAkAPQkAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fj='Fjándi:BAAALgAECgcJCwAAAA==.',
Fl='Flameblue:BAABLgAECn8fAAQTAAgJyAQpXADBAAATAAcJ2gMpXADBAAAiAAMJawZmGgB3AAAVAAUJ2AF/MgBaAAAAAA==.Flandia:BAAALgAECgQJDwAAAA==.Fleen:BAAALgAECgIJBAABLgAECgYJFgAHAHMeAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAABLgAECn84AAIQAAkJ0xLURQDvAQAQAAkJ0xLURQDvAQAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frittata:BAAALgAECgUJBQABLgAFFAQJEQAPALkQAA==.Frostbringer:BAAALgAECgMJAwAAAA==.Frostmäw:BAAALgAECgQJAwAAAA==.Frostworn:BAAALgAECgEJAQAAAA==.Frostybetch:BAAALgAECgcJDAAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIEAAcJ+RwHMwBWAgAEAAcJ+RwHMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAgJHAARAHsVAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgAECgUJBQAAAA==.',
Fy='Fylerian:BAACLgAFFH8uAAIcAAgJGiP9AQC/AgAcAAgJGiP9AQC/AgAuAAQKfyIAAhwACQn0JHgCAJcDABwACQn0JHgCAJcDAAAA.Fylerianmage:BAABLgAECn8YAAIPAAYJMiD1lwClAQAPAAYJMiD1lwClAQABLgAFFAgJLgAcABojAA==.Fylerianprie:BAAALgAFFAEJAQABLgAFFAgJLgAcABojAA==.Fyrebane:BAAALgAECgYJBgAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Gamasham:BAAALgAECgEJAQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAACLgAFFH8IAAITAAYJ7g6CHwBcAQATAAYJ7g6CHwBcAQAuAAQKfxUAAxMACAnaIwYIANQCABMABwnZIwYIANQCACIABwlQHeoJAEACAAAA.Gargalon:BAABLgAFFH8FAAITAAUJ1wqzNwDkAAATAAUJ1wqzNwDkAAAAAA==.Gatør:BAABLgAECn8WAAIkAAcJNAPpLwDEAAAkAAcJNAPpLwDEAAAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAABLgAECn8ZAAIMAAgJhBxZEQDSAQAMAAgJhBxZEQDSAQAAAA==.',
Gh='Ghettomike:BAAALgAECgcJDAABLgAECgkJCQANAAAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Gillixos:BAAALgAECgEJAQAAAA==.Giny:BAABLgAECn8wAAIlAAkJ3BT+IADZAQAlAAkJ3BT+IADZAQAAAA==.',
Gl='Glandros:BAAALgADCgYJDAAAAA==.Glorin:BAAALgAECgYJDAAAAA==.',
Go='Gobbledeez:BAABLgAECn8VAAIfAAgJ1hdVNwDPAQAfAAgJ1hdVNwDPAQAAAA==.Gojojo:BAABLgAECn8pAAIWAAgJfRxBEwC0AgAWAAgJfRxBEwC0AgAAAA==.Gongfuboar:BAAALgAECgkJCwAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgUJDgAAAA==.Govinniuur:BAABLgAECn8lAAIRAAgJQhBOIQBFAQARAAgJQhBOIQBFAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECgkJQgAQAHIXAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgAECgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIPAAgJ1CLiEwAxAwAPAAgJ1CLiEwAxAwAAAA==.Greatness:BAAALgAECgYJBgAAAA==.Grizzy:BAABLgAFFH8NAAIIAAUJ9RfaDQAzAQAIAAUJ9RfaDQAzAQAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groomash:BAAALgAECgEJAgAAAA==.Groundscore:BAAALgAECgQJBAABLgAECgUJCQANAAAAAA==.Gryf:BAAALgADCgQJBAAAAA==.',
Gu='Gundam:BAAALgAECggJDgABLgAFFAgJHwAPAEcYAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgAECgkJDQAAAA==.Gwydionatlan:BAAALgADCgEJAQABLgAECgYJBgANAAAAAA==.',
Gy='Gyndrinolara:BAABLgAECn8fAAIBAAkJNhMEPwDhAQABAAkJNhMEPwDhAQAAAA==.',
Ha='Hafadude:BAAALgAECgkJDgAAAA==.Hakouh:BAABLgAECn8YAAIEAAgJ2g2PgABrAQAEAAgJ2g2PgABrAQAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Harrypotta:BAAALgAECgEJAwAAAA==.Hatereading:BAAALgAECgUJCgAAAA==.',
He='Headhuntér:BAABLgAECn8oAAIKAAkJQgjlHAC1AQAKAAkJQgjlHAC1AQAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgUJBwAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECgkJOQAVAJsYAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAFFAYJDQAgAEUJAA==.Hellokrittyz:BAAALgAECgEJAQAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAYJFwAYAKAjAA==.Hikiru:BAAALgAECgkJEQAAAA==.Hikura:BAAALgAECgcJBgAAAA==.Hirohh:BAAALgAECgUJBQAAAA==.',
Hk='Hkinc:BAAALgAECgYJCgABLgAECggJIgAEAB0hAA==.',
Ho='Holydwarfen:BAAALgAECgEJAQAAAA==.Holygrey:BAAALgAECgEJAgAAAA==.Holysh:BAAALgADCgYJBgAAAA==.Holywater:BAACLgAFFH8SAAIGAAQJThLxBwD2AAAGAAQJThLxBwD2AAAuAAQKfz4AAgYACAkOIdAEALMCAAYACAkOIdAEALMCAAAA.Homeles:BAAALgAECgkJCQAAAA==.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAABLgAECn8WAAMDAAYJ+B5rQQAJAgADAAYJ+B5rQQAJAgAdAAIJtxbsUgB1AAAAAA==.Horick:BAAALgAECgEJAQAAAA==.Houndo:BAAALgADCggJCAAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Hu='Hunnie:BAAALgAECgEJAQAAAA==.',
Hy='Hyperiann:BAAALgAECgEJAQAAAA==.Hypersqvrl:BAAALgAECgEJAQABLgAFFAMJBgAmAEEfAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Ic='Iceyrot:BAAALgAECgYJCAAAAA==.',
Ih='Ihatemodels:BAAALgADCgEJAQAAAA==.',
Ii='Iightning:BAAALgAECgYJCgAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJBAABLgAFFAEJAQANAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAABLgAECn8gAAMIAAcJOh4kEQAUAgAIAAcJOh4kEQAUAgAHAAQJIgWS5wBlAAAAAA==.Ineedbowjob:BAAALgAECgYJEAAAAA==.Intothedark:BAAALgAECgQJBgAAAA==.Intotherain:BAAALgADCgIJAwAAAA==.Inya:BAAALgAECgYJEAAAAA==.Inyomouf:BAAALgAECgEJAgAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIEAAgJxyCPFwDbAgAEAAgJxyCPFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgcJDwAAAA==.',
Is='Isaacnewton:BAABLgAECn8rAAIWAAcJCSHsFwAtAgAWAAcJCSHsFwAtAgAAAA==.Islandstyle:BAAALgAECgEJAQAAAA==.',
It='Ithoril:BAAALgADCgcJCwAAAA==.Itsdone:BAABLgAECn8uAAMDAAkJ2BNCVACeAQADAAkJ5RJCVACeAQAdAAMJSxTjQACxAAABLgAFFAYJDQAgAEUJAA==.',
Iv='Iveliz:BAABLgAECn8eAAIaAAkJZBMtHgDSAQAaAAkJZBMtHgDSAQAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAFFAYJBwATAIUCAA==.',
Ja='Jackill:BAAALgAECgEJAQAAAA==.Jackk:BAACLgAFFH8PAAILAAYJpBv3EgCQAQALAAYJpBv3EgCQAQAuAAQKfzkAAwsACAkmIT8IAOoCAAsACAkmIT8IAOoCAAQABwlzESuPAFEBAAAA.Jackks:BAAALgAECgEJAQABLgAFFAYJDwALAKQbAA==.Jadewulf:BAAALgADCgcJBgABLgAECggJFQABAI0WAA==.Jaeger:BAABLgAECn8cAAIKAAgJfhrSCwAVAgAKAAgJfhrSCwAVAgAAAA==.Jaellas:BAAALgADCgEJAQAAAA==.Jamalsdad:BAAALgAECgIJAgAAAA==.Janzan:BAABLgAECn8VAAIfAAYJcxPJXwA3AQAfAAYJcxPJXwA3AQAAAA==.Jasmonk:BAABLgAECn86AAImAAkJCQ2FJwB4AQAmAAkJCQ2FJwB4AQAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8aAAIHAAgJpg6MfgAfAQAHAAgJpg6MfgAfAQAAAA==.',
Ji='Jinkz:BAAALgAECgYJCQAAAA==.',
Jo='Jorhel:BAAALgAECgkJDgAAAA==.Josephsmith:BAAALgAECgkJCAAAAA==.',
Ju='Judgevis:BAABLgAECn8WAAILAAgJrg+mPwBDAQALAAgJrg+mPwBDAQAAAA==.Jumbles:BAAALgAECgkJDwAAAA==.Justeene:BAAALgAECgYJBgABLgAECgQJBQANAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
Jy='Jynxy:BAAALgAECgEJAQAAAA==.',
['Jø']='Jøshu:BAAALgAECgUJBwAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwANAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katedolores:BAAALgAECggJCQABLgAFFAMJBwAKAN0eAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgAECgYJBgAAAA==.Kazuu:BAAALgADCgEJBgAAAA==.',
Ke='Keepup:BAACLgAFFH8FAAIHAAIJFRepdQCPAAAHAAIJFRepdQCPAAAuAAQKfxkAAwcABwn0Ir8dAF8CAAcABwn0Ir8dAF8CAB4AAQmAFuUwADwAAAEuAAUUAgkIAAMAKyEA.Keg:BAAALgAFFAEJAgABLgAFFAgJHAARAHsVAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECgkJLAAfACwbAA==.Keladun:BAAALgAECgUJDAAAAA==.',
Kh='Khaho:BAABLgAECn8bAAIPAAgJuhMweACFAQAPAAgJuhMweACFAQAAAA==.Khonan:BAACLgAFFH8FAAMmAAMJjQ1YJgCzAAAmAAMJjQ1YJgCzAAAhAAEJWgSDaQAmAAAuAAQKfx0ABCEABgm2Doc0AB8BACEABgm2Doc0AB8BACYABgllFypEAOsAABkAAQmxA/KWAB4AAAEuAAUUBQkRAAcANiIA.',
Ki='Kiamar:BAAALgAECgkJEAAAAA==.Kicey:BAAALgAECgkJBQABLgAFFAIJBQAUAJMZAA==.Kidgroove:BAAALgADCgYJBgAAAA==.Kijyo:BAABLgAECn8fAAIeAAkJIhY+CADvAQAeAAkJIhY+CADvAQAAAA==.Kimbrewly:BAAALgAECgYJBgABLgAECgcJFAAJAEwfAA==.Kishu:BAAALgADCggJDQAAAA==.Kitten:BAAALgAECggJDgAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Kl='Kleokleo:BAAALgAECgEJBAAAAA==.',
Kn='Knutebomb:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.Korlax:BAAALgAECgQJBgAAAA==.',
Kr='Krex:BAAALgAECgYJCQAAAA==.Kristeena:BAAALgAECggJEAAAAA==.Krossedup:BAAALgADCgcJDgAAAA==.Kryptonikk:BAAALgAECgYJEQAAAA==.Krystal:BAAALgAECgMJBgAAAA==.Kröw:BAABLgAECn8eAAIYAAkJaA4GEQCeAQAYAAkJaA4GEQCeAQAAAA==.',
Ku='Kudrix:BAABLgAECn8zAAImAAkJyiSuAQBaAwAmAAkJyiSuAQBaAwAAAA==.Kurgaz:BAAALgAECgYJBgAAAA==.Kurø:BAABLgAECn82AAIQAAkJLyBcIQCAAgAQAAkJLyBcIQCAAgAAAA==.',
Kw='Kwanzie:BAAALgAECgMJAwAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.Kyzen:BAAALgAECgYJDgAAAA==.',
['Kà']='Kàri:BAACLgAFFH8FAAIJAAIJ4gVkXQBdAAAJAAIJ4gVkXQBdAAAuAAQKfxsAAgkACQn7GCAYAIMCAAkACQn7GCAYAIMCAAAA.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMQAAcJ6BSZaAC8AQAQAAcJDhSZaAC8AQASAAMJvBFgFQA/AAAAAA==.Latherfanta:BAAALgAECgcJEQAAAA==.Laurijaydn:BAAALgAFFAEJAgAAAA==.Laylâ:BAAALgAECgEJAwAAAA==.',
Le='Lelink:BAABLgAECn8YAAIQAAkJmRNwNwAeAgAQAAkJmRNwNwAeAgAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leniuum:BAAALgADCgMJBgABLgAFFAQJEgABACIPAA==.Leoden:BAAALgADCgUJBAAAAA==.Leopard:BAAALgAECgkJBwAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAABLgAECn8WAAIIAAUJvApLRQDgAAAIAAUJvApLRQDgAAABLgAECgcJBwANAAAAAA==.Lightlana:BAACLgAFFH8TAAIEAAUJXRSmSAAWAQAEAAUJXRSmSAAWAQAuAAQKfyUAAgQACAm5IdAYANQCAAQACAm5IdAYANQCAAAA.Lightwalker:BAAALgAECgUJBQAAAA==.Likeaglove:BAAALgAECggJEQABLgAFFAYJDQAgAEUJAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8pAAMfAAkJHx4UDgDhAgAfAAkJHx4UDgDhAgAlAAMJ5QpMbgCKAAAAAA==.Lizzieag:BAECLgAFFH8OAAIWAAUJZxOYHgAzAQAWAAUJZxOYHgAzAQAuAAQKf0kAAhYACQmvHLcLAKsCABYACQmvHLcLAKsCAAAA.',
Ll='Llemons:BAAALgAECgIJAwABLgAFFAQJEQAPALkQAA==.Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loafsies:BAAALgADCgMJAwAAAA==.Loakai:BAAALgAECgEJAQAAAA==.Lockman:BAAALgADCgcJEQAAAA==.Lockndotz:BAAALgAECgcJEgABLgAECgQJBQANAAAAAA==.Loenil:BAABLgAECn8mAAIEAAgJywwNngA4AQAEAAgJywwNngA4AQAAAA==.Lohueng:BAABLgAECn8XAAIGAAgJpRK4EwCMAQAGAAgJpRK4EwCMAQAAAA==.Lolhigh:BAAALgAECgEJAQAAAA==.Loodah:BAAALgAECggJCgAAAA==.Lookee:BAABLgAECn8eAAIPAAYJshaaiwBdAQAPAAYJshaaiwBdAQAAAA==.Loranoth:BAAALgADCggJDwAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.Lovecox:BAAALgAECgEJAgAAAA==.',
Lu='Lucielle:BAAALgAECgYJCwAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn89AAIJAAkJziLrBABoAwAJAAkJziLrBABoAwAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAcJHAABAMcPAA==.Lustarhymes:BAAALgAECgUJBQAAAA==.',
Ly='Lyxon:BAABLgAECn8rAAMJAAkJtBaNGQB3AgAJAAkJtBaNGQB3AgAcAAEJbwxXkgAqAAAAAA==.',
['Lå']='Låw:BAAALgAECgIJBAAAAA==.',
Ma='Mabrian:BAAALgADCgcJBwAAAA==.Mael:BAAALgADCgUJDQAAAA==.Maesma:BAAALgAECgcJBwABLgAFFAQJCgABAHgSAA==.Mafoôza:BAABLgAECn8uAAIWAAkJOiIhCwCzAgAWAAkJOiIhCwCzAgAAAA==.Magicalama:BAAALgADCgYJCwABLgAFFAYJFAAKAIkVAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgQJBAABLgAECggJHQABAPMXAA==.Magpen:BAAALgADCgMJBgAAAA==.Magtark:BAAALgAECgIJBAAAAA==.Mahboyblu:BAAALgAECgMJAwAAAA==.Mahndoo:BAACLgAFFH8RAAIPAAQJuRCzXwAsAQAPAAQJuRCzXwAsAQAuAAQKfyAAAg8ACAmRGk9QAOgBAA8ACAmRGk9QAOgBAAAA.Makto:BAAALgADCgUJCAAAAA==.Malia:BAAALgAECgcJCQAAAA==.Maliciouso:BAABLgAECn8sAAIfAAkJLBv5EgCxAgAfAAkJLBv5EgCxAgAAAA==.Malindas:BAAALgADCgUJBQAAAA==.Malogano:BAAALgAECgEJAQAAAA==.Malédiction:BAABLgAECn8bAAIPAAgJ6RXXdwDiAQAPAAgJ6RXXdwDiAQAAAA==.Mastagrey:BAAALgADCgUJBQAAAA==.Mattdemøn:BAAALgAECgMJAwABLgAECggJLAABAEIfAA==.Matua:BAAALgAECgMJBAAAAA==.Maximillian:BAAALgAECgYJCAAAAA==.Maymae:BAABLgAECn8aAAIfAAgJQwuJUgBkAQAfAAgJQwuJUgBkAQABLgAECggJNgAfAAoUAA==.',
Me='Medizine:BAAALgAECgYJCQAAAA==.Medon:BAAALgADCgYJBgAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megabonk:BAAALgAECgQJBQABLgAECggJKQAWAH0cAA==.Megademac:BAABLgAECn8fAAIHAAcJIA70ggAWAQAHAAcJIA70ggAWAQAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.Merquise:BAAALgAECgUJBQAAAA==.Metus:BAAALgADCgkJCQAAAA==.',
Mi='Miistral:BAABLgAECn8mAAIEAAkJRBfQRgDvAQAEAAkJRBfQRgDvAQAAAA==.Mimmz:BAAALgAECgEJAQAAAA==.Miniblinks:BAAALgADCgQJAwAAAA==.Minisid:BAABLgAFFH8KAAIPAAMJwgv5hADVAAAPAAMJwgv5hADVAAABLgAFFAgJLQAWAJcfAA==.Miriia:BAAALgAECgIJAwAAAA==.Mirshta:BAAALgADCggJEQAAAA==.Missmaam:BAABLgAECn8lAAMeAAcJqyCPCADoAQAeAAcJqyCPCADoAQAHAAQJJA9VxwCbAAABLgAFFAQJBgAhAPEOAA==.Mistinmae:BAAALgAECgEJAgABLgAECggJNgAfAAoUAA==.Mistrjenkins:BAAALgAECgYJDQAAAA==.Mistyeva:BAAALgAECgUJBQABLgAECgkJPQAJAM4iAA==.Mixoz:BAAALgAECgQJBAAAAA==.Miyoko:BAAALgAECgYJDwAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQANAAAAAA==.Mokotrize:BAABLgAECn83AAIGAAkJHRmVCQAzAgAGAAkJHRmVCQAzAgAAAA==.Momtok:BAAALgAECgUJBwAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAACLgAFFH8NAAIcAAUJaBTaIAATAQAcAAUJaBTaIAATAQAuAAQKfykAAhwACAlhHGwQAJ0CABwACAlhHGwQAJ0CAAAA.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECggJLAABAEIfAA==.Mordred:BAABLgAECn8qAAIeAAYJxwowGgDIAAAeAAYJxwowGgDIAAAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCQABLgAFFAQJDwAfAFMVAA==.',
Mu='Mud:BAAALgAECgUJBwAAAA==.Munchies:BAAALgAECgYJCgAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQABLgAECggJGgAZAE8WAA==.Myrolee:BAABLgAECn8aAAQZAAgJTxZYHwCpAQAZAAgJXhRYHwCpAQAhAAgJkgwVRABUAQAmAAQJPhFDXAChAAAAAA==.Myrowrynn:BAAALgAECgYJCgABLgAECggJGgAZAE8WAA==.Myrozond:BAAALgAECgYJDwABLgAECggJGgAZAE8WAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAAEAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIEAAcJZyNNGQDRAgAEAAcJZyNNGQDRAgAAAA==.Mäx:BAAALgAECgEJAQAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAACLgAFFH8GAAImAAMJQR9fFAAVAQAmAAMJQR9fFAAVAQAuAAQKfzQAAiYACQlqJfoCADQDACYACQlqJfoCADQDAAAA.Narset:BAAALgADCgYJDgAAAA==.Nattum:BAAALgADCgYJBwAAAA==.Nayasylpha:BAABLgAECn8sAAIZAAgJxhzxDwCdAgAZAAgJxhzxDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Nemophilist:BAAALgAECgQJBAAAAA==.Neown:BAABLgAECn8YAAIPAAYJ7BI+qgAnAQAPAAYJ7BI+qgAnAQABLgAECggJKgAJAEgeAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAACLgAFFH8IAAIPAAMJNh/ebQANAQAPAAMJNh/ebQANAQAuAAQKfy4AAg8ACQkxIX8mAH4CAA8ACQkxIX8mAH4CAAAA.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAABLgAECn8fAAIgAAYJkQtIQADoAAAgAAYJkQtIQADoAAAAAA==.Nightfaze:BAAALgAECggJDAABLgAECgQJBQANAAAAAA==.Nightknigh:BAAALgAECgEJAgAAAA==.Nirri:BAAALgAECgkJEQAAAA==.Nishendra:BAABLgAECn8aAAIVAAkJix3+BgDQAgAVAAkJix3+BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAABLgAECn8jAAMBAAkJ+BFZPgDjAQABAAkJ+BFZPgDjAQAKAAYJkgkvNQAJAQAAAA==.Nitezilla:BAAALgAECgQJBQAAAA==.',
No='Noblok:BAAALgAECgQJBQAAAA==.Nocando:BAACLgAFFH8NAAIgAAYJRQn9DwBNAQAgAAYJRQn9DwBNAQAuAAQKfxgAAiAACQkLGC4TAD4CACAACQkLGC4TAD4CAAAA.Nofeetpicsyo:BAABLgAECn82AAIaAAgJewyrMgBOAQAaAAgJewyrMgBOAQABLgAECgkJLAADAE8TAA==.Noni:BAAALgADCgEJAQAAAA==.Nootella:BAABLgAECn8UAAILAAYJlSIoHgAlAgALAAYJlSIoHgAlAgABLgAECgkJGwAjAIsXAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAABLgAECn8qAAQGAAcJnyAKDQDwAQAEAAYJySBnSQAGAgAGAAcJLhwKDQDwAQALAAIJnRtpZACgAAAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8eAAIaAAgJGBoMGwAGAgAaAAgJGBoMGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAFFAUJDgAXAFUUAA==.Nylinuya:BAAALgAECgYJEwABLgAFFAUJDgAXAFUUAA==.Nyteskye:BAAALgAECgYJCAAAAA==.Nyxoblivion:BAAALgADCgcJEQAAAA==.',
['Nî']='Nîco:BAABLgAECn8qAAIJAAgJSB7wGABwAgAJAAgJSB7wGABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAACLgAFFH8OAAIZAAQJlw2kKgD6AAAZAAQJlw2kKgD6AAAuAAQKfyIAAxkACQkrEOEhAJcBABkACQnjD+EhAJcBACYAAQlYFct4ADkAAAAA.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAACLgAFFH8UAAIDAAUJSRmiRQA5AQADAAUJSRmiRQA5AQAuAAQKfzMAAgMACQnQFiQ0AAcCAAMACQnQFiQ0AAcCAAAA.Ollphéist:BAAALgAECgYJBgAAAA==.Oláf:BAAALgADCgcJBwAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECgkJOQAVAJsYAA==.',
On='Oneall:BAABLgAECn8zAAIcAAgJmxUoIgC0AQAcAAgJmxUoIgC0AQAAAA==.Onehit:BAAALgAECgMJBQAAAA==.Onlyspells:BAABLgAECn8WAAMPAAgJaAm2pwCKAQAPAAgJaAm2pwCKAQAOAAEJnAELEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8lAAIRAAkJJRgkGACgAQARAAkJJRgkGACgAQAAAA==.',
Or='Orchideva:BAAALgADCgEJAQABLgAECgkJPQAJAM4iAA==.Orelikai:BAAALgADCgQJBAAAAA==.Oreoz:BAAALgADCgUJBQAAAA==.Orphän:BAAALgAECgEJAQABLgAECgcJCQANAAAAAA==.',
Ot='Othin:BAABLgAECn8ZAAIJAAgJKRt/HABfAgAJAAgJKRt/HABfAgAAAA==.Ottoshock:BAAALgAECgEJAQAAAA==.',
Pa='Painloa:BAABLgAECn8fAAMSAAgJpApfFAA2AQASAAgJpApfFAA2AQAQAAYJZwFg7wCfAAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8cAAIjAAkJ8Q7fHACuAQAjAAkJ8Q7fHACuAQAAAA==.Pandadance:BAAALgAECgcJEwAAAA==.Pandakill:BAAALgAECgUJBgAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandaxi:BAAALgAECgIJAgABLgAECggJIgAEAB0hAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAwAAAA==.Papachungus:BAAALgADCgYJCQABLgAFFAUJBQAQANYJAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJEAANAAAAAA==.Papagenu:BAAALgAECgYJCQABLgAECgYJEAANAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8tAAIPAAkJLyO3FQDVAgAPAAkJLyO3FQDVAgAAAA==.Pazzie:BAAALgAECgUJDQAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.Phreyja:BAAALgAECgEJAQAAAA==.',
Pm='Pmac:BAABLgAECn8VAAIPAAUJWxAa0wDpAAAPAAUJWxAa0wDpAAABLgAECgcJHwAHACAOAA==.Pmbambee:BAAALgADCggJCAABLgAECgkJMAABALYPAA==.',
Po='Poggie:BAAALgAECgQJBgAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potox:BAAALgAECgUJBwAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Power:BAAALgAECgUJBwAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Primerecall:BAAALgAECgkJAgAAAA==.Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgAECgcJCwAAAA==.',
Pu='Punishment:BAAALgAECgUJBwAAAA==.Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAABLgAECn80AAMdAAkJACEyAQDoAgAdAAkJACEyAQDoAgADAAMJTA4/4ACYAAAAAA==.',
Qa='Qai:BAABLgAECn8iAAMFAAgJkg+aFwBEAQAFAAUJ7BaaFwBEAQAMAAgJNgf6QACcAAAAAA==.',
Qu='Quan:BAAALgAECgIJCAAAAA==.Quelestraza:BAABLgAECn8fAAMVAAkJzRQNCwApAgAVAAkJzRQNCwApAgATAAEJjgVHmAAoAAAAAA==.',
Ra='Raewyck:BAABLgAECn89AAIBAAgJpBa8LQD8AQABAAgJpBa8LQD8AQAAAA==.Ragar:BAAALgAECgUJBQABLgAFFAMJDQAWAHslAA==.Raginbull:BAABLgAECn8tAAMkAAgJ8xqSDgD+AQAkAAgJ8xqSDgD+AQAWAAEJcwEMtwATAAAAAA==.Raginganja:BAAALgADCgMJBgAAAA==.Ragingmaze:BAABLgAECn8hAAMQAAkJ+A5IXgCrAQAQAAkJYwxIXgCrAQARAAEJpx8nTgBWAAAAAA==.Rainburrow:BAABLgAECn8VAAIZAAgJCxc1GgDSAQAZAAgJCxc1GgDSAQAAAA==.Raptormortis:BAABLgAECn8nAAMlAAkJpRodFABIAgAlAAkJpRodFABIAgAfAAYJ5BMrWABRAQAAAA==.Rawd:BAAALgADCgIJAgAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgANAAAAAA==.Raylen:BAAALgAECgkJDwAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgANAAAAAA==.Reinitia:BAAALgAECgUJCQAAAA==.Reinny:BAABLgAECn8bAAIJAAgJPQ9dQACOAQAJAAgJPQ9dQACOAQAAAA==.Reinslight:BAAALgAECgEJAQAAAA==.Rellic:BAAALgAECgMJBgAAAA==.Remy:BAABLgAECn8UAAIEAAcJBB+CQAADAgAEAAcJBB+CQAADAgAAAA==.Renkagisa:BAAALgAECgYJEgAAAA==.Renku:BAAALgAECgQJEgAAAA==.Retana:BAAALgAECgQJCAAAAA==.Retrisan:BAAALgAECgUJBQAAAA==.Revenge:BAAALgAECgYJCwAAAA==.',
Rh='Rhinn:BAABLgAECn8hAAIYAAgJXgwAFgBcAQAYAAgJXgwAFgBcAQAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAABLgAECn8WAAIEAAcJuiBFMwAwAgAEAAcJuiBFMwAwAgAAAA==.Ritsuri:BAAALgAECgMJBAABLgAECgMJBAANAAAAAA==.Ritsuyi:BAAALgAECgEJAQABLgAECgMJBAANAAAAAA==.Ritualbeef:BAAALgAECgQJBAABLgAECgkJDgANAAAAAA==.Riven:BAAALgAECggJDgAAAA==.',
Ro='Roarbear:BAABLgAECn8gAAIWAAkJIhmCFABLAgAWAAkJIhmCFABLAgAAAA==.Roastedz:BAABLgAECn82AAIdAAgJ4Q5iDwBFAQAdAAgJ4Q5iDwBFAQAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roodeekay:BAAALgAECgQJCAABLgAECggJNgAUAK4fAA==.Roomi:BAABLgAECn85AAIYAAkJ4BvCBgBlAgAYAAkJ4BvCBgBlAgAAAA==.Roowar:BAABLgAECn8YAAIbAAcJ/RzmDgD7AQAbAAcJ/RzmDgD7AQABLgAECggJNgAUAK4fAA==.Rorié:BAAALgADCggJDAAAAA==.Rorthu:BAAALgAECgkJDwAAAA==.Roru:BAACLgAFFH8FAAIDAAMJXxDbegDJAAADAAMJXxDbegDJAAAuAAQKfzQAAwMACQkJIXwJAAUDAAMACQkJIXwJAAUDAB0AAwlLBZlUAHAAAAAA.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgAECgkJDwAAAA==.Rustyd:BAAALgAFFAQJBAABLgAFFAYJHQAPALkkAA==.Ruxman:BAAALgAFFAEJAgAAAA==.',
Ry='Ry:BAABLgAECn8YAAIDAAUJTyKBewBBAQADAAUJTyKBewBBAQAAAA==.Ryanna:BAAALgAECgYJCwAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgcJDAAAAA==.',
['Ræ']='Rædar:BAAALgADCggJCAABLgAECgkJJQANAAAAAA==.Rædiêncë:BAABLgAECn8cAAIEAAkJEwYVoQAzAQAEAAkJEwYVoQAzAQAAAA==.',
['Rò']='Ròó:BAABLgAECn82AAQUAAgJrh/rCAACAwAUAAgJrh/rCAACAwAnAAMJLR5+FAC1AAAoAAIJiSN8HQBcAAAAAA==.',
Sa='Saevio:BAACLgAFFH8FAAIQAAIJ2AWV8AB4AAAQAAIJ2AWV8AB4AAAuAAQKfy8AAxAACQkFHVohAIECABAACQkFHVohAIECABEABQmPDlAvAOIAAAAA.Sajin:BAAALgAECgEJAQAAAA==.Salazandur:BAAALgAECgEJAQABLgAECgkJHwAeACIWAA==.Sallean:BAAALgAECgEJAQAAAA==.Salvader:BAAALgAECgkJEAAAAA==.Sanctus:BAABLgAECn8YAAIEAAcJXQKOHAGTAAAEAAcJXQKOHAGTAAAAAA==.Sanlorastik:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwANAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAACLgAFFH8QAAMQAAQJmhNOVgBCAQAQAAQJmhNOVgBCAQASAAEJ2Q3VJQBHAAAuAAQKfysAAxAACQnmGlhCADACABAACQnmGlhCADACABIABglhERwXABsBAAAA.Saso:BAAALgAECgYJDAAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAILAAMJ/hULDgD3AAALAAMJ/hULDgD3AAAuAAQKfxcAAgsACAnGJWMEACcDAAsACAnGJWMEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJBAAAAA==.Scoot:BAEALgAFFAIJAwABLgAFFAYJEwAgAPodAA==.Scotchnsoda:BAACLgAFFH8aAAMgAAUJfhJwEgAxAQAgAAUJfhJwEgAxAQAjAAEJJgPUTgA0AAAuAAQKfy4ABCAACQnuE3spAKYBACAACQnfE3spAKYBACMABgnCE3EtAGwBABoAAQlyANFrABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgAECgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgUJEQAAAA==.Selenegosa:BAABLgAECn8fAAMiAAgJnBWwDQAtAQAiAAYJGBewDQAtAQATAAYJNBAZVADbAAABLgAFFAMJBwAKAN0eAA==.Seran:BAABLgAECn8kAAIBAAkJbSCOEADJAgABAAkJbSCOEADJAgAAAA==.Serenade:BAABLgAECn88AAIcAAkJ3RINHgDUAQAcAAkJ3RINHgDUAQAAAA==.Severyne:BAABLgAECn8oAAIJAAgJIiUUBQA8AwAJAAgJIiUUBQA8AwABLgAFFAcJDwAhADoeAA==.',
Sh='Shadowchad:BAAALgADCgUJCAAAAA==.Shadowmeld:BAAALgAECgcJEAAAAA==.Shadowpump:BAAALgAECgYJDAAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgAECgIJAgAAAA==.Shallanaera:BAAALgAECgYJBgAAAA==.Shamanco:BAAALgAECgYJBwAAAA==.Shamanu:BAAALgAECgcJEQABLgAECgcJGAAEAGcjAA==.Shamsel:BAABLgAECn8+AAIaAAkJDBFPHgDRAQAaAAkJDBFPHgDRAQAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8jAAIMAAgJyBLXAwDSAQAMAAgJyBLXAwDSAQAuAAQKfygAAgwACQn2IEICABEDAAwACQn2IEICABEDAAAA.Shikes:BAABLgAFFH8PAAIPAAQJTRAUXQAwAQAPAAQJTRAUXQAwAQAAAA==.Shinpaku:BAAALgADCgIJAgAAAA==.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJDAAAAA==.Shorin:BAAALgADCgYJCwAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAACLgAFFH8GAAIJAAMJtSBAKAAWAQAJAAMJtSBAKAAWAQAuAAQKfzMAAwkACQmZIwQEAFADAAkACAliJQQEAFADABwAAQn1CjWEAD0AAAAA.Shweatyballs:BAABLgAECn8XAAIPAAYJahtGjQC4AQAPAAYJahtGjQC4AQAAAA==.Shóki:BAABLgAECn8UAAMDAAgJ+QwHagBnAQADAAgJ+QwHagBnAQAdAAIJPAg2QwAkAAAAAA==.',
Si='Sidetrax:BAAALgADCgQJBAAAAA==.Silran:BAABLgAECn8XAAIEAAgJCwzDwgACAQAEAAgJCwzDwgACAQAAAA==.Silverwings:BAAALgADCgEJAQAAAA==.Simmara:BAACLgAFFH8KAAIBAAQJLQ0ARgAaAQABAAQJLQ0ARgAaAQAuAAQKfyEAAwEACQkrER1IAMQBAAEACQkrER1IAMQBAAoABAmCBIYkAKYAAAAA.Sinistar:BAAALgAECgEJAQAAAA==.Sinner:BAECLgAFFH8TAAIgAAYJ+h3hBQD0AQAgAAYJ+h3hBQD0AQAuAAQKfxoAAyAACQkXHdIHAM4CACAACQkXHdIHAM4CABoAAwnuAxNZAFcAAAAA.Sinrael:BAAALgAECgUJCQAAAA==.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAgJKgAkAPQkAA==.Skoala:BAAALgAECggJEAAAAA==.Skruff:BAAALgAECgIJAwAAAA==.Skylinelol:BAAALgAECgEJAQAAAA==.Skywalkah:BAAALgADCgIJAgABLgAECgcJCwANAAAAAA==.',
Sl='Slamuraijack:BAAALgAECgcJBwAAAA==.Slayngin:BAAALgAECgQJCQABLgAECgUJCAANAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAFFAMJAwAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAABLgADCgYJBgANAAAAAA==.',
Sn='Snipë:BAAALgAECgIJAgAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgMJBQAAAA==.Solweaver:BAAALgADCgIJAgAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAABLgAECn8hAAIGAAgJ5hbyEACxAQAGAAgJ5hbyEACxAQAAAA==.',
Sq='Squirrely:BAAALgADCgIJAgABLgAECggJLAABAEIfAA==.Squirrt:BAAALgAECgUJCQAAAA==.Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAABLgAECn8mAAIRAAgJaAU6MwDLAAARAAgJaAU6MwDLAAAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Stoneý:BAAALgAECgIJAgAAAA==.Stonystark:BAAALgAECgEJBAAAAA==.Straam:BAACLgAFFH8bAAIfAAQJaR37JABOAQAfAAQJaR37JABOAQAuAAQKf0UAAh8ACQmIIpoHADMDAB8ACQmIIpoHADMDAAAA.Stumpe:BAAALgAECgIJAwAAAA==.Stupidity:BAAALgAECgkJDgAAAA==.Støney:BAABLgAECn87AAIPAAkJ7BEZUQDlAQAPAAkJ7BEZUQDlAQAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAgJKgAkAPQkAA==.Subroutine:BAABLgAECn8WAAICAAgJHh/4DgDKAgACAAgJHh/4DgDKAgABLgAFFAgJKgAkAPQkAA==.Subtractive:BAACLgAFFH8qAAIkAAgJ9CQRAQDHAgAkAAgJ9CQRAQDHAgAuAAQKfxsAAiQACAmmJiQBAIYDACQACAmmJiQBAIYDAAAA.Superiorha:BAABLgAECn8cAAImAAkJMR9oBwDQAgAmAAkJMR9oBwDQAgAAAA==.',
Sw='Swagchamp:BAAALgADCgQJBQABLgAECgcJCwANAAAAAA==.Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIPAAIJ2SHQMwDKAAAPAAIJ2SHQMwDKAAAuAAQKfyIAAg8ACQk5I7oFAKcDAA8ACQk5I7oFAKcDAAAA.',
Sy='Sylthara:BAABLgAECn8uAAMfAAgJMRSQNwDOAQAfAAgJMRSQNwDOAQAYAAEJXQOwRQAgAAAAAA==.Syrellis:BAAALgAECgEJAgAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8xAAIeAAkJchVfCADsAQAeAAkJchVfCADsAQAAAA==.Tahle:BAAALgAECgIJAgAAAA==.Tailian:BAAALgAECgMJAwAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAABLgAECn8zAAIPAAgJ6Bn1PwAaAgAPAAgJ6Bn1PwAaAgAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tater:BAAALgADCgcJBwAAAA==.Tatonka:BAAALgADCgYJAwAAAA==.Tavin:BAAALgAECgUJBQAAAA==.Tazchem:BAAALgAECgQJBQAAAA==.',
Te='Techboar:BAAALgAECgEJAQAAAA==.Teinuya:BAACLgAFFH8OAAMXAAUJVRSHBAA9AQAXAAUJOhSHBAA9AQADAAIJMAvPqQB8AAAuAAQKfz8ABBcACQn6IE8BAO8CABcACQl/IE8BAO8CAB0ABgkSHQUMAAICAAMABAkCFxSpAPAAAAAA.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Temparia:BAAALgAECgYJBgAAAA==.Tenderfiddle:BAAALgAECgYJEwAAAA==.Tenochitilan:BAAALgAECggJDwAAAA==.Tenuous:BAABLgAECn8ZAAMcAAgJzBnhGAACAgAcAAgJzBnhGAACAgAJAAQJ6QbtmgB4AAAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAFFAMJBgAJALUgAA==.Thanar:BAAALgADCgEJAQAAAA==.Thevelo:BAAALgAECgEJAQABLgAECgcJFgAKAM4TAA==.Thisistheway:BAACLgAFFH8JAAIkAAMJ0hTjHACpAAAkAAMJ0hTjHACpAAAuAAQKfy0AAiQACQnjHOcIAGYCACQACQnjHOcIAGYCAAEuAAUUBQkXABUARRkA.Thoorz:BAAALgAECgUJCQAAAA==.Thornielizie:BAAALgAECgEJAQAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAABLgAECn8XAAMBAAYJfxhuegBGAQABAAYJvhduegBGAQACAAYJ0QqmVAD4AAABLgAECgUJCQANAAAAAA==.Thothh:BAABLgAECn8aAAQjAAYJ1A2pOgAkAQAjAAYJWg2pOgAkAQAaAAQJYAvFYACSAAAgAAIJXQ+1bAB3AAAAAA==.Thraxacious:BAACLgAFFH8SAAIFAAUJKRtYBgBDAQAFAAUJKRtYBgBDAQAuAAQKfyEAAgUACQnTGGMLAAECAAUACQnTGGMLAAECAAAA.Thulcandra:BAABLgAECn8UAAIPAAYJxB/fYwARAgAPAAYJxB/fYwARAgAAAA==.Thulsadoomm:BAABLgAECn8yAAIRAAgJ1h3RDAA8AgARAAgJ1h3RDAA8AgAAAA==.Thundermay:BAABLgAECn82AAIfAAgJChStMwDfAQAfAAgJChStMwDfAQAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAABLgAECn85AAIkAAcJghAvIAAsAQAkAAcJghAvIAAsAQAAAA==.Tigó:BAABLgAECn8oAAIEAAkJjSB4FADGAgAEAAkJjSB4FADGAgAAAA==.Tigölebittie:BAABLgAECn8uAAMJAAkJ2xInKwD8AQAJAAkJ2xInKwD8AQAcAAUJDBBCVAC5AAAAAA==.Tiifa:BAAALgADCgIJAQAAAA==.Tinkerrbella:BAABLgAECn8WAAQBAAcJvQ3yUwBsAQABAAcJvQ3yUwBsAQACAAUJFgIZbQCKAAAKAAIJsgGFWgBBAAABLgAFFAcJHAABAMcPAA==.Tireliaa:BAAALgAECgUJCAAAAA==.Tizzymami:BAAALgADCgQJBAAAAA==.',
Tj='Tjnewt:BAAALgADCgkJCQAAAA==.',
To='Toatsie:BAABLgAECn8VAAIEAAgJJBfbWgC6AQAEAAgJJBfbWgC6AQAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Trazen:BAAALgAECgUJBAAAAA==.Tribulationz:BAAALgAECgQJBAABLgAECgYJDgANAAAAAA==.Trumpybear:BAABLgAECn8iAAIEAAgJHSFfIgB7AgAEAAgJHSFfIgB7AgAAAA==.',
Ts='Tsun:BAABLgAECn85AAMbAAkJNR0ZCABwAgAbAAkJsRwZCABwAgAkAAkJbxLfEQDIAQAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgcJCgABLgAECgcJGAAEAGcjAA==.',
Ud='Uddertrouble:BAEBLgAECn8dAAIBAAgJ8xdJSwC7AQABAAgJ8xdJSwC7AQAAAA==.',
Uf='Ufos:BAAALgADCggJHgAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAPANkhAA==.',
Ul='Ulfgrim:BAAALgAECgEJAQAAAA==.',
Un='Uncletat:BAABLgAECn9AAAQgAAkJuyRgAgB8AwAgAAkJuyRgAgB8AwAjAAYJmCFWDwBJAgAaAAEJHRQDggA1AAAAAA==.',
Ur='Urmada:BAABLgAECn80AAIPAAkJfw80WQDOAQAPAAkJfw80WQDOAQAAAA==.Urmami:BAABLgAECn8wAAIDAAkJ+hPsNwD5AQADAAkJ+hPsNwD5AQAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Uz='Uzui:BAAALgAECgcJDgAAAA==.',
Va='Vael:BAAALgAECgUJCAAAAA==.Vahnt:BAABLgAECn8yAAIfAAgJGxh1IAAcAgAfAAgJGxh1IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8rAAIEAAkJLh6CJgCMAgAEAAkJLh6CJgCMAgAAAA==.Vampire:BAABLgAECn8VAAIHAAkJ6hpfGwBtAgAHAAkJ6hpfGwBtAgAAAA==.Vampyre:BAACLgAFFH8cAAIRAAgJexW9DACnAQARAAgJexW9DACnAQAuAAQKfx4AAhEACQnFIfoCADMDABEACQnFIfoCADMDAAAA.Vanadie:BAAALgAECgcJBwAAAA==.Vanta:BAAALgAECgYJBwAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJBAAAAA==.Vendettá:BAABLgAECn8VAAIfAAYJzhjVWQBLAQAfAAYJzhjVWQBLAQAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgAECgQJBAAAAA==.',
Vi='Vidi:BAAALgAECgUJBQAAAA==.Vinai:BAAALgAECgEJAQAAAA==.Virala:BAABLgAFFH8FAAIQAAMJAQwUpQDNAAAQAAMJAQwUpQDNAAAAAA==.Visenya:BAAALgAECgUJEQAAAA==.Vishontey:BAAALgAECgQJBQAAAA==.Vitaminn:BAABLgAECn8zAAQEAAkJPR4OHQCVAgAEAAkJPR4OHQCVAgALAAIJTwZkigBUAAAGAAEJnBf7PgBCAAAAAA==.Vithiris:BAAALgADCgYJBgAAAA==.',
Vk='Vk:BAABLgAECn8YAAQRAAkJrQjVKAAMAQARAAgJUAnVKAAMAQASAAYJmwRSJQChAAAQAAMJKQGpgAEqAAAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAwAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECgkJDgAAAA==.Vynnigosa:BAAALgAFFAEJAQAAAA==.Vynora:BAAALgAECgkJCwAAAA==.Vyrse:BAABLgAFFH8MAAITAAcJbxARGACdAQATAAcJbxARGACdAQAAAA==.',
Wa='Wafflez:BAAALgAECgcJBwAAAA==.Walterlight:BAAALgAECgEJAQAAAA==.Wampa:BAAALgAECgYJCwAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wasabii:BAAALgAFFAMJBAAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgQJCAABLgAFFAUJBQAQANYJAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8NAAIWAAMJeyVRDwARAQAWAAMJeyVRDwARAQAuAAQKfzoAAxsACQkeJbwFAKkCABYABwmvJZkNAOkCABsACQmZI7wFAKkCAAAA.Windente:BAABLgAECn8mAAMBAAkJ5RUOTwCwAQABAAgJJRYOTwCwAQACAAQJ7AqtKgBoAAAAAA==.Wing:BAEBLgAFFH8HAAIEAAMJiyCcUAAIAQAEAAMJiyCcUAAIAQABLgAFFAYJEwAgAPodAA==.Wiseau:BAABLgAECn8sAAMBAAgJQh96HQBxAgABAAgJQh96HQBxAgACAAEJ4wMElAAmAAAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgYJDAAAAA==.',
Wu='Wulfhound:BAABLgAECn8VAAIBAAgJjRYURQDOAQABAAgJjRYURQDOAQAAAA==.Wulfnbolt:BAAALgAECgQJBQAAAA==.Wulfsblood:BAAALgADCgQJBAABLgAECggJFQABAI0WAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECgkJJQAAAQ==.',
Xe='Xeno:BAAALgAECgEJAQAAAA==.Xexhu:BAAALgAECgcJBwAAAA==.',
Xo='Xonice:BAAALgAECgIJAgAAAA==.',
Xp='Xpand:BAAALgAECgMJAwAAAA==.',
Xu='Xuen:BAABLgAECn8iAAImAAkJxg88IQCiAQAmAAkJxg88IQCiAQAAAA==.',
Ya='Yazbrez:BAAALgADCgEJAQABLgAECgYJEgANAAAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zackattack:BAAALgAFFAIJAwAAAA==.Zaeluna:BAABLgAECn8zAAIMAAgJZiB1AwDWAgAMAAgJZiB1AwDWAgAAAA==.Zanikan:BAAALgAECgkJAgAAAA==.Zanzer:BAAALgAECgUJEAAAAA==.Zathara:BAABLgAECn8gAAIFAAkJWxX7CgAIAgAFAAkJWxX7CgAIAgAAAA==.',
Ze='Zechs:BAAALgAECgYJCwAAAA==.Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zereena:BAAALgADCgUJBQAAAA==.Zeroshot:BAAALgAECgEJBQAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.Zeyleian:BAAALgAECgUJBQAAAA==.',
Zo='Zorvax:BAAALgAECgUJCwAAAA==.',
Zp='Zpazzie:BAAALgAECgQJCQAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgAECgEJAQAAAA==.',
['Zö']='Zörö:BAABLgAECn8dAAIQAAkJdRv3JABuAgAQAAkJdRv3JABuAgAAAA==.',
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
