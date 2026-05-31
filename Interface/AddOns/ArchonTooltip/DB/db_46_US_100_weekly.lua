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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','Druid-Feral','Paladin-Protection','DemonHunter-Devourer','Hunter-Survival','Shaman-Elemental','Paladin-Holy','Druid-Guardian','Unknown-Unknown','Mage-Fire','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Rogue-Subtlety','Evoker-Preservation','Druid-Restoration','Warlock-Affliction','Monk-Brewmaster','Warrior-Arms','Warrior-Fury','Druid-Balance','Warlock-Destruction','Priest-Shadow','DemonHunter-Vengeance','Priest-Holy','Shaman-Restoration','DemonHunter-Havoc','Monk-Mistweaver','Evoker-Devastation','Priest-Discipline','Shaman-Enhancement','Warrior-Protection','Monk-Windwalker','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aamodar:BAABLgAECn8iAAMBAAgJ9BGhQwC/AQABAAgJ9BGhQwC/AQACAAMJ/gclJQBzAAAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAACLgAFFH8HAAIDAAQJsA4WSgAgAQADAAQJsA4WSgAgAQAuAAQKfzcAAgMACAl+Gi4xAAcCAAMACAl+Gi4xAAcCAAAA.Abhorrent:BAAALgAECgEJAQAAAA==.',
Ac='Acathisia:BAAALgAECgEJAQAAAA==.Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgQJBAAAAA==.Adino:BAABLgAECn87AAIBAAkJHREKNAD2AQABAAkJHREKNAD2AQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAACLgAFFH8VAAIEAAUJiBojLQA7AQAEAAUJiBojLQA7AQAuAAQKfyYAAgQACAkiI/AOABcDAAQACAkiI/AOABcDAAAA.Aetherz:BAAALgAECgEJAQAAAA==.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.Agrolazor:BAAALgADCgUJBQAAAA==.',
Ah='Ahote:BAACLgAFFH8FAAIFAAMJ4h5kBwAYAQAFAAMJ4h5kBwAYAQAuAAQKfxoAAgUABQk3JgIIAC8CAAUABQk3JgIIAC8CAAAA.Ahtee:BAABLgAECn89AAMEAAkJCSAGEgDDAgAEAAkJCSAGEgDDAgAGAAQJdwjONQBuAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.Akuprovik:BAABLgAECn8kAAIHAAgJ6g0vXQBYAQAHAAgJ6g0vXQBYAQAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Alanthos:BAAALgAECgQJBAAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgAECgcJBwABLgAFFAQJCQABAE8RAA==.Alexandraus:BAAALgAECggJEQAAAA==.Alexiea:BAAALgAECgQJBAAAAA==.Algodon:BAABLgAFFH8GAAIEAAMJkQxOYQDMAAAEAAMJkQxOYQDMAAAAAA==.Allenduin:BAAALgADCgEJAQAAAA==.Almeads:BAAALgAECgEJAQAAAA==.Alonias:BAAALgAECgUJCQAAAA==.Alseena:BAABLgAECn8fAAIEAAcJqBlNcgBvAQAEAAcJqBlNcgBvAQAAAA==.Alysiita:BAAALgAECgEJAQAAAA==.',
Am='Amadeux:BAACLgAFFH8TAAIIAAUJeRmhDQBMAQAIAAUJeRmhDQBMAQAuAAQKfyQAAggACAlfIHAHAIACAAgACAlfIHAHAIACAAAA.Amarawr:BAAALgADCgYJBgABLgAFFAUJEwAIAHkZAA==.Amicae:BAAALgADCgcJCAAAAA==.Ammandor:BAAALgAECgQJBAAAAA==.Amun:BAAALgAECgEJAQAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgYJDgABLgAECggJMQAJAAQhAA==.Anform:BAAALgAECgIJAgAAAA==.Anryn:BAAALgAECgYJBgABLgAFFAUJFQAEAIgaAA==.Anthais:BAAALgAECgQJBAAAAA==.Anvar:BAACLgAFFH8JAAIBAAQJTxGlOAAiAQABAAQJTxGlOAAiAQAuAAQKfx8AAgEACQkEHrkXAIECAAEACQkEHrkXAIECAAAA.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgYJCQAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn9FAAIKAAkJ+SF4AwBZAwAKAAkJ+SF4AwBZAwAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Arianrhod:BAAALgAECgQJBAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arunis:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECggJDAAAAA==.',
At='Atrumdeus:BAABLgAECn9JAAIEAAkJbR8XDgDfAgAEAAkJbR8XDgDfAgAAAA==.',
Au='Audiamer:BAABLgAECn8XAAMLAAkJwxXVDwDIAQALAAgJnxbVDwDIAQAFAAkJbgqzEwBeAQAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQAMAAAAAA==.Aweyaeh:BAAALgAECgEJAgAAAA==.Awkykit:BAABLgAECn8fAAINAAgJqAVmBwAAAQANAAgJqAVmBwAAAQAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAILAAYJVxB+FwD/AAALAAYJVxB+FwD/AAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Baloou:BAAALgAECgEJAQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8pAAIOAAgJJxt8MgA3AgAOAAgJJxt8MgA3AgAAAA==.Bannann:BAAALgAECgEJAQAAAA==.Banned:BAAALgAECgQJBQABLgAFFAIJCAADACshAA==.Bariôn:BAAALgAECgQJBwAAAA==.Barney:BAAALgADCgYJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAgJJQAPAOIgAA==.Beaklondemon:BAAALgAECgcJBwABLgAFFAgJJQAPAOIgAA==.Beaksbigdk:BAACLgAFFH8lAAMPAAgJ4iCgAwCrAgAPAAcJ4iCgAwCrAgAQAAEJAACnEQBmAAAuAAQKf0EAAw8ACQk6JssJABEDAA8ACQkXJssJABEDABAACAmnJIEGAKYCAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAABLgAECn8ZAAMPAAgJFRCTfwCEAQAPAAgJ1A+TfwCEAQAQAAcJ7gSSMwCyAAAAAA==.Beedo:BAAALgAECgEJAgAAAA==.Beef:BAAALgAECgYJBgABLgAFFAUJDgARALgcAA==.Beefknight:BAAALgAECgMJAwAAAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAABLgAECn8cAAISAAkJPQskGADBAQASAAkJPQskGADBAQAAAA==.Belldia:BAACLgAFFH8aAAIBAAcJxw92CQDSAQABAAcJxw92CQDSAQAuAAQKf0cAAwEACQnZII0PAL8CAAEACQnZII0PAL8CAAIABQnTDaZQAAsBAAAA.Beni:BAAALgAECgUJDAAAAA==.Beniima:BAABLgAECn8fAAIOAAkJrBetLABQAgAOAAkJrBetLABQAgAAAA==.Benimarú:BAAALgAECgQJBAAAAA==.Bennylickz:BAABLgAECn85AAMTAAkJmxgjDAACAgATAAgJXhcjDAACAgARAAcJNxSCIwClAQAAAA==.',
Bi='Bibby:BAAALgAECgYJEAAAAA==.Bibi:BAAALgAECgQJBAAAAA==.Birdbear:BAABLgAECn8cAAMFAAYJ+AqFIQDVAAAFAAYJ+AqFIQDVAAAUAAUJeAuxcQDOAAAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAFFAQJDAAVAE0TAA==.Blufox:BAABLgAECn8bAAIEAAcJWiQaIgBmAgAEAAcJWiQaIgBmAgAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAOANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgIJAgABLgAECgYJFgAHAHMeAA==.',
Br='Brainpower:BAAALgAECgYJBgAAAA==.Broherum:BAAALgAECgEJAgAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.Brunia:BAAALgADCgIJAgAAAA==.',
Bu='Bubonicmyro:BAAALgAECgMJAwABLgAECggJGgAWAE8WAA==.Buckbeak:BAAALgAECgYJDAAAAA==.Bulgingtotem:BAAALgAECgEJAQAAAA==.Busting:BAAALgAECgYJEAAAAA==.Buttmucker:BAAALgAECgIJAgAAAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAIJAgAAAA==.',
By='Byebye:BAAALgAECgcJBgAAAA==.',
['Bà']='Bàhamut:BAAALgAECgYJDwAAAA==.',
['Bå']='Båemax:BAABLgAECn8gAAMXAAgJmxGoGwBlAQAXAAgJQA6oGwBlAQAYAAYJFg0zTAD/AAAAAA==.',
Ca='Caelestos:BAABLgAECn8ZAAMIAAgJiBsJDgA7AgAIAAcJiBsJDgA7AgACAAcJvApeHAC2AAAAAA==.Castar:BAAALgADCgIJAgAAAA==.Catalella:BAAALgAECgcJBgAAAA==.',
Cc='Ccwwds:BAAALgADCgYJDQABLgAFFAMJBQAOADEIAA==.',
Ce='Celypzo:BAAALgADCgkJCQAAAA==.Cewkie:BAABLgAECn8uAAIYAAgJOxlxGQAOAgAYAAgJOxlxGQAOAgAAAA==.',
Ch='Chaulock:BAAALgAECgcJCAAAAA==.Chausup:BAAALgADCgQJBAABLgAECggJJwAEAKQkAA==.Chautime:BAABLgAECn8nAAIEAAgJpCTCBwBYAwAEAAgJpCTCBwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgcJCwAMAAAAAA==.Chemdizz:BAAALgAECgYJDwAAAA==.Chialliance:BAABLgAECn8lAAMZAAkJrhOgGQDmAQAZAAkJrhOgGQDmAQAUAAEJowGo6gAaAAAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAYJGQALAOYVAA==.Chknsaladin:BAAALgAECgEJAQAAAA==.Chocö:BAAALgAECgYJBwAAAA==.Choujisan:BAABLgAECn8ZAAIYAAcJpA+pOQBKAQAYAAcJpA+pOQBKAQABLgAFFAMJCgAEAO8XAA==.Chrysamere:BAAALgADCgcJDQAAAA==.Chugrar:BAAALgADCggJDQAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8eAAIIAAgJUiGMAwDwAgAIAAgJUiGMAwDwAgAAAA==.Cloft:BAAALgAECgYJBgAAAA==.Clumzylock:BAABLgAECn8dAAMDAAcJYQ7KcQBLAQADAAcJOA7KcQBLAQAaAAYJ+QsXOADUAAABLgAECggJNgAbAHsMAA==.Clumzymage:BAAALgADCgYJBgABLgAECggJNgAbAHsMAA==.',
Co='Code:BAACLgAFFH8FAAISAAIJkxlqKQChAAASAAIJkxlqKQChAAAuAAQKfx8AAhIACQm9IskHABQDABIACQm9IskHABQDAAAA.Consfearacy:BAAALgAECggJCgAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8jAAIEAAcJCB89SQDSAQAEAAcJCB89SQDSAQAAAA==.Corrl:BAABLgAECn8VAAIOAAcJSRjdfwBdAQAOAAcJSRjdfwBdAQABLgAECgcJIwAEAAgfAA==.',
Cr='Crayzie:BAAALgADCgEJAQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgAECgQJBQABLgAFFAEJAQAMAAAAAA==.Creatrix:BAAALgADCgcJBwAAAA==.Crossblesser:BAAALgAECgEJAQAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuma:BAAALgAECgEJBgAAAA==.Cumb:BAABLgAECn8WAAMHAAYJcx6KSACVAQAHAAYJYRyKSACVAQAcAAIJnxC4LgAyAAAAAA==.Curatoria:BAAALgAECgYJEAAAAA==.',
Cw='Cwood:BAAALgAECgEJAQABLgAFFAMJBQAOADEIAA==.Cwwddsz:BAAALgAECgEJAQABLgAFFAMJBQAOADEIAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgYJDAAAAA==.',
Da='Daioh:BAAALgADCgEJAQAAAA==.Daladin:BAAALgADCgEJAQAAAA==.Dalanos:BAAALgADCgUJBQAAAA==.Damacraze:BAACLgAFFH8HAAIBAAIJlR2QYACqAAABAAIJlR2QYACqAAAuAAQKfx4AAgEACAm6IbUQALQCAAEACAm6IbUQALQCAAAA.Darkbluerose:BAABLgAECn8XAAMCAAYJrQeHIgCHAAAIAAUJLgXKIQDJAAACAAYJVAaHIgCHAAAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAABLgAECn8ZAAIKAAgJNAd6PAA+AQAKAAgJNAd6PAA+AQAAAA==.Daxine:BAAALgAECgYJBgAAAA==.',
De='Deadboy:BAAALgADCggJCgAAAA==.Deadroar:BAAALgAFFAIJAwABLgAFFAIJBQALAAQRAA==.Deadwill:BAAALgAECgMJAwAAAA==.Deaminase:BAABLgAECn8xAAIOAAgJDxwrOAAhAgAOAAgJDxwrOAAhAgAAAA==.Deathknell:BAAALgAFFAIJAgAAAA==.Decypher:BAABLgAECn8gAAIdAAkJaBfbEABHAgAdAAkJaBfbEABHAgAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAABLgAECn8ZAAIeAAgJOxknGgBfAgAeAAgJOxknGgBfAgAAAA==.Demidru:BAABLgAECn8jAAIZAAcJQBi5HwCwAQAZAAcJQBi5HwCwAQAAAA==.Demonboar:BAABLgAECn8cAAMfAAgJOBPcGgCFAQAfAAgJOBPcGgCFAQAHAAYJPwSUmwDhAAAAAA==.Demonrocky:BAAALgADCgkJCwAAAA==.Demunic:BAACLgAFFH8GAAMcAAQJSAIVCwBqAAAfAAMJlAJxHAB/AAAcAAMJlQEVCwBqAAAuAAQKfxgAAhwACAnHBWgVAOMAABwACAnHBWgVAOMAAAAA.Dennis:BAAALgAECgIJBQAAAA==.Derringer:BAAALgAECgYJBgAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dharin:BAAALgAECgEJAQAAAA==.Dhqt:BAAALgAECgMJBQABLgAFFAEJAQAMAAAAAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dihnnis:BAAALgAECgMJBgAAAA==.Dingbangow:BAAALgAECgUJCwAAAA==.Discoinferno:BAAALgAECgIJAgAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAABLgAECn8YAAIfAAYJ2BalIABOAQAfAAYJ2BalIABOAQAAAA==.',
Dk='Dktyler:BAAALgADCgQJBAABLgAFFAQJBgAcAEgCAA==.',
Do='Doneza:BAAALgAECgMJAwAAAA==.Donki:BAABLgAFFH8FAAIPAAUJ1gmrZwAQAQAPAAUJ1gmrZwAQAQAAAA==.Donothingwin:BAACLgAFFH8IAAIDAAIJKyF+dQC+AAADAAIJKyF+dQC+AAAuAAQKfyUAAwMACQl/Jt0DAH4DAAMACQl/Jt0DAH4DABoAAwkKJZgnACUBAAAA.Doomgirl:BAAALgAECgYJBgAAAA==.Dotalott:BAAALgADCgYJCwAAAA==.Doublelift:BAABLgAFFH8FAAMbAAIJuA1RKACLAAAbAAIJuA1RKACLAAAdAAEJ6Q9YMQAyAAAAAA==.',
Dr='Dragondeznut:BAAALgAECgIJAgAAAA==.Drakblak:BAABLgAECn8jAAIdAAkJRBQZGwADAgAdAAkJRBQZGwADAgAAAA==.Drakisara:BAAALgAECgQJBAABLgAECgQJBQAMAAAAAA==.Draukarí:BAABLgAECn8sAAQVAAkJfB5TAQDlAgAVAAkJQh5TAQDlAgADAAcJYRzvKABtAgAaAAEJiB+5XwBQAAAAAA==.Drayer:BAABLgAECn8xAAIKAAgJahE6MgB3AQAKAAgJahE6MgB3AQAAAA==.Dreivyn:BAAALgAECgIJAgAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAABLgAECn8gAAIHAAgJ1hmKMADuAQAHAAgJ1hmKMADuAQAAAA==.Drunkenmist:BAABLgAECn8iAAIgAAYJVBPHOgBTAQAgAAYJVBPHOgBTAQAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8ZAAMRAAUJKCBxGABgAQARAAUJKCBxGABgAQAhAAEJAAAwEAAAAAAuAAQKfy0AAxEACQllIjULAIwCABEACQllIjULAIwCACEABgkIFVYaAGEBAAAA.',
Du='Dudley:BAAALgAECgIJAgAAAA==.Dumbledork:BAAALgAECgEJAgAAAA==.Dundundun:BAAALgAECggJCgAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAABLgAECn8cAAMBAAkJXwkDUgCUAQABAAkJXwkDUgCUAQACAAEJrwDWmwAQAAAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgAECgMJAwABLgAFFAgJJQAPAOIgAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAABLgAECn8VAAIiAAgJcBhCDwBcAgAiAAgJcBhCDwBcAgAAAA==.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8jAAMCAAcJ9BUwBwDKAQACAAcJ4RUwBwDKAQABAAQJygg5QwACAQAuAAQKfy8AAwIACQlbI1QCAMECAAIACQlbI1QCAMECAAEAAgljFqfRAHsAAAAA.',
Eg='Eggdrop:BAABLgAECn84AAIYAAkJ2h/JBgDiAgAYAAkJ2h/JBgDiAgAAAA==.Egufro:BAAALgAECgYJBgABLgAFFAQJDAAjAGIRAA==.',
Eh='Ehgu:BAACLgAFFH8MAAIjAAQJYhEPBwAwAQAjAAQJYhEPBwAwAQAuAAQKfzAAAiMACQkXGjwHAEICACMACQkXGjwHAEICAAAA.',
Ei='Eismond:BAAALgAFFAEJAQAAAA==.',
El='Eleaya:BAAALgAECgIJAgAAAA==.Elediyn:BAAALgAECgMJBgAAAA==.Eleverclear:BAABLgAECn8YAAMKAAcJWRSpPgB+AQAKAAcJWRSpPgB+AQAEAAIJXw+FLwFeAAAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAABLgAECn8UAAIEAAgJbAbBowAWAQAEAAgJbAbBowAWAQAAAA==.',
Em='Emidget:BAABLgAECn8YAAIOAAcJHhMkdwBwAQAOAAcJHhMkdwBwAQAAAA==.',
En='Endervish:BAAALgAECgYJBwABLgAFFAQJBgABAC0NAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.',
Er='Erhmer:BAAALgAECggJBgAAAA==.Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAABLgAECn8XAAIPAAYJqApuvQDqAAAPAAYJqApuvQDqAAAAAA==.',
Fa='Faaith:BAAALgADCgQJBAAAAA==.Fabermor:BAAALgAECgEJAQAAAA==.Fairygon:BAAALgAECgUJBQAAAA==.Fairyhunter:BAAALgAECgYJBwAAAA==.Fairymonk:BAABLgAECn8VAAMgAAYJdRu+JgDDAQAgAAYJdRu+JgDDAQAWAAIJvRMbcQBUAAAAAA==.Fangrat:BAAALgAECgEJAQABLgAFFAEJAQAMAAAAAA==.Fariona:BAAALgADCggJCgAAAA==.Fartbarf:BAABLgAECn8kAAIDAAgJcxJ4VADKAQADAAgJcxJ4VADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Fatfatfat:BAABLgAFFH8FAAILAAIJBBGUHgB6AAALAAIJBBGUHgB6AAAAAA==.Fatshark:BAAALgAECgEJAQABLgAFFAIJBQALAAQRAA==.Faya:BAAALgADCgUJBQABLgAFFAQJCQABAE8RAA==.',
Fe='Fennicuss:BAAALgAECgEJAgAAAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAABLgAECn8YAAIgAAgJpgYVUAD3AAAgAAgJpgYVUAD3AAAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAgJJAAkAPQkAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fj='Fjándi:BAAALgAECgcJCwAAAA==.',
Fl='Flameblue:BAAALgAECgcJEgAAAA==.Flandia:BAAALgAECgQJDwAAAA==.Fleen:BAAALgAECgIJBAABLgAECgYJFgAHAHMeAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAABLgAECn84AAIPAAkJ0xJFPgD2AQAPAAkJ0xJFPgD2AQAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frittata:BAAALgAECgUJBQABLgAFFAQJDQAOAPMPAA==.Frostbringer:BAAALgAECgMJAwAAAA==.Frostmäw:BAAALgAECgQJAwAAAA==.Frostworn:BAAALgADCgYJBgAAAA==.Frostybetch:BAAALgAECgcJDAAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIEAAcJ+RwHMwBWAgAEAAcJ+RwHMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAgJHAAQAHsVAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgAECgUJBQAAAA==.',
Fy='Fylerian:BAACLgAFFH8lAAIZAAgJzCIOAQDHAgAZAAgJzCIOAQDHAgAuAAQKfyIAAhkACQn0JHgCAJcDABkACQn0JHgCAJcDAAAA.Fylerianmage:BAABLgAECn8YAAIOAAYJMiD1lwClAQAOAAYJMiD1lwClAQABLgAFFAgJJQAZAMwiAA==.Fylerianprie:BAAALgAFFAEJAQABLgAFFAgJJQAZAMwiAA==.Fyrebane:BAAALgAECgYJBgAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAACLgAFFH8GAAIRAAQJ3BKnNgDIAAARAAQJ3BKnNgDIAAAuAAQKfxUAAxEACAnaI0MHAM4CABEABwnZI0MHAM4CACEABwlQHeoJAEACAAAA.Gargalon:BAABLgAFFH8FAAIRAAUJ1wpNLwDrAAARAAUJ1wpNLwDrAAAAAA==.Gatør:BAAALgAECgcJEwAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAABLgAECn8ZAAILAAgJhBzLDgDXAQALAAgJhBzLDgDXAQAAAA==.',
Gh='Ghettomike:BAAALgAECgcJDAABLgAECgkJCQAMAAAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Gillixos:BAAALgAECgEJAQAAAA==.Giny:BAABLgAECn8wAAIJAAkJ3BR8HQDdAQAJAAkJ3BR8HQDdAQAAAA==.',
Gl='Glandros:BAAALgADCgYJDAAAAA==.Glorin:BAAALgAECgYJDAAAAA==.',
Go='Gobbledeez:BAABLgAECn8VAAIeAAgJ1hfXMQDRAQAeAAgJ1hfXMQDRAQAAAA==.Gojojo:BAABLgAECn8pAAIYAAgJfRxBEwC0AgAYAAgJfRxBEwC0AgAAAA==.Gongfuboar:BAAALgAECgkJCwAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgMJCQAAAA==.Govinniuur:BAABLgAECn8lAAIQAAgJQhDiHQBNAQAQAAgJQhDiHQBNAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECgkJNwAPACAWAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgAECgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIOAAgJ1CLiEwAxAwAOAAgJ1CLiEwAxAwAAAA==.Greatness:BAAALgAECgYJBgAAAA==.Grizzy:BAAALgAFFAEJAgAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groundscore:BAAALgADCgUJBQABLgAECgMJBAAMAAAAAA==.Gryf:BAAALgADCgQJBAAAAA==.',
Gu='Gundam:BAAALgAECggJDgABLgAFFAcJHQAOABQbAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgAECgYJBgAAAA==.Gwydionatlan:BAAALgADCgEJAQABLgAECgYJBgAMAAAAAA==.',
Gy='Gyndrinolara:BAABLgAECn8eAAIBAAgJ6BNvSwCnAQABAAgJ6BNvSwCnAQAAAA==.',
Ha='Hafadude:BAAALgAECgkJDAAAAA==.Hakouh:BAAALgAECggJDwAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Hatereading:BAAALgAECgUJBgAAAA==.',
He='Headhuntér:BAABLgAECn8eAAIIAAgJ8gWVJgBZAQAIAAgJ8gWVJgBZAQAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgQJBgAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECgkJOQATAJsYAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAFFAUJCwAdAPoJAA==.Hellokrittyz:BAAALgADCgcJBwAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAYJFgAjAKAjAA==.Hikiru:BAAALgAECgkJCwAAAA==.Hikura:BAAALgAECgcJBgAAAA==.Hirohh:BAAALgAECgUJBQAAAA==.',
Hk='Hkinc:BAAALgAECgYJCgABLgAECggJIgAEAB0hAA==.',
Ho='Holydwarfen:BAAALgAECgEJAQAAAA==.Holysh:BAAALgADCgYJBgAAAA==.Holywater:BAACLgAFFH8KAAIGAAMJsxMCCgC9AAAGAAMJsxMCCgC9AAAuAAQKfz4AAgYACAkOIdAEALMCAAYACAkOIdAEALMCAAAA.Homeles:BAAALgAECgkJCQAAAA==.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAABLgAECn8WAAMDAAYJ+B5rQQAJAgADAAYJ+B5rQQAJAgAaAAIJtxbsUgB1AAAAAA==.Horick:BAAALgAECgEJAQAAAA==.Houndo:BAAALgADCggJCAAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Hu='Hunnie:BAAALgAECgEJAQAAAA==.',
Hy='Hyperiann:BAAALgAECgEJAQAAAA==.Hypersqvrl:BAAALgAECgEJAQABLgAECgkJNAAlAGolAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Ic='Iceyrot:BAAALgAECgYJBwAAAA==.',
Ih='Ihatemodels:BAAALgADCgEJAQAAAA==.',
Ii='Iightning:BAAALgADCgEJAQAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJAwABLgAFFAEJAQAMAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAABLgAECn8gAAMfAAcJOh6pDgAbAgAfAAcJOh6pDgAbAgAHAAQJIgXD2QBcAAAAAA==.Ineedbowjob:BAAALgAECgYJEAAAAA==.Intothedark:BAAALgAECgQJBgAAAA==.Intotherain:BAAALgADCgIJAwAAAA==.Inya:BAAALgAECgYJDQAAAA==.Inyomouf:BAAALgAECgEJAgAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIEAAgJxyCPFwDbAgAEAAgJxyCPFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgcJDwAAAA==.',
Is='Isaacnewton:BAABLgAECn8rAAIYAAcJCSEqFQAzAgAYAAcJCSEqFQAzAgAAAA==.Islandstyle:BAAALgAECgEJAQAAAA==.',
It='Ithoril:BAAALgADCgcJCwAAAA==.Itsdone:BAABLgAECn8tAAMDAAgJJRM5TQDhAQADAAgJDhI5TQDhAQAaAAMJSxSRJwBmAAABLgAFFAUJCwAdAPoJAA==.',
Iv='Iveliz:BAABLgAECn8eAAIbAAkJZBPiGgDSAQAbAAkJZBPiGgDSAQAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAFFAYJBwARAIUCAA==.',
Ja='Jackk:BAACLgAFFH8NAAIKAAUJMBpeGQA8AQAKAAUJMBpeGQA8AQAuAAQKfzMAAwoACAkmIT8IAOoCAAoACAkmIT8IAOoCAAQABQnZCSrLANsAAAAA.Jackks:BAAALgAECgEJAQABLgAFFAUJDQAKADAaAA==.Jadewulf:BAAALgADCgcJBgABLgAECggJFQABAI0WAA==.Jaeger:BAABLgAECn8cAAIIAAgJfhrSCwAVAgAIAAgJfhrSCwAVAgAAAA==.Jaellas:BAAALgADCgEJAQAAAA==.Jamalsdad:BAAALgAECgIJAgAAAA==.Janzan:BAABLgAECn8VAAIeAAYJcxPYVwA3AQAeAAYJcxPYVwA3AQAAAA==.Jasmonk:BAABLgAECn86AAIlAAkJCQ2EIgCGAQAlAAkJCQ2EIgCGAQAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8aAAIHAAgJpg4PdQAcAQAHAAgJpg4PdQAcAQAAAA==.',
Ji='Jinkz:BAAALgAECgYJCQAAAA==.',
Jo='Jorhel:BAAALgADCgcJBwAAAA==.Josephsmith:BAAALgAECgkJCAAAAA==.',
Ju='Judgevis:BAABLgAECn8WAAIKAAgJrg/hOgBGAQAKAAgJrg/hOgBGAQAAAA==.Jumbles:BAAALgAECgYJBgAAAA==.Justeene:BAAALgAECgYJBgABLgAECgQJBQAMAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
['Jø']='Jøshu:BAAALgAECgUJBwAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwAMAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katedolores:BAAALgAECggJCQABLgAFFAMJBwAIAN0eAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgAECgYJBgAAAA==.Kazuu:BAAALgADCgEJBgAAAA==.',
Ke='Keepup:BAACLgAFFH8FAAIHAAIJFRcPZQCaAAAHAAIJFRcPZQCaAAAuAAQKfxkAAwcABwn0IgsbAF4CAAcABwn0IgsbAF4CABwAAQmAFhgsADwAAAEuAAUUAgkIAAMAKyEA.Keg:BAAALgAFFAEJAgABLgAFFAgJHAAQAHsVAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECgkJKwAeACwbAA==.Keladun:BAAALgAECgUJDAAAAA==.',
Kh='Khaho:BAABLgAECn8bAAIOAAgJuhNDbgCEAQAOAAgJuhNDbgCEAQAAAA==.Khonan:BAABLgAECn8ZAAQlAAYJixeLNwBAAQAlAAUJPhWLNwBAAQAgAAYJtg6HNAAfAQAWAAEJsQPylgAeAAABLgAFFAcJFQAOALYZAA==.',
Ki='Kiamar:BAAALgAECgkJEAAAAA==.Kicey:BAAALgAECgkJBQABLgAFFAIJBQASAJMZAA==.Kijyo:BAABLgAECn8dAAIcAAkJDRY0BwD5AQAcAAkJDRY0BwD5AQAAAA==.Kishu:BAAALgADCggJDQAAAA==.Kitten:BAAALgAECggJCAAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Kl='Kleokleo:BAAALgAECgEJAgAAAA==.',
Kn='Knutebomb:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.Korlax:BAAALgAECgQJBQAAAA==.',
Kr='Krex:BAAALgADCgYJDQAAAA==.Krossedup:BAAALgADCgcJDgAAAA==.Kryptonikk:BAAALgAECgYJEAAAAA==.Krystal:BAAALgAECgMJBgAAAA==.Kröw:BAABLgAECn8eAAIjAAkJaA6lDgCoAQAjAAkJaA6lDgCoAQAAAA==.',
Ku='Kudrix:BAABLgAECn8pAAIlAAgJGSLhCACjAgAlAAgJGSLhCACjAgAAAA==.Kurgaz:BAAALgAECgYJBgAAAA==.Kurø:BAABLgAECn80AAIPAAkJRR7zHwB2AgAPAAkJRR7zHwB2AgAAAA==.',
Kw='Kwanzie:BAAALgAECgMJAwAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.Kyzen:BAAALgAECgUJCAAAAA==.',
['Kà']='Kàri:BAACLgAFFH8FAAIUAAIJ4gXlUgBqAAAUAAIJ4gXlUgBqAAAuAAQKfxsAAhQACQn7GPEVAIUCABQACQn7GPEVAIUCAAAA.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMPAAcJ6BSZaAC8AQAPAAcJDhSZaAC8AQAmAAMJvBFgFQA/AAAAAA==.Latherfanta:BAAALgAECgcJEQAAAA==.Laurijaydn:BAAALgAECgcJCwAAAA==.Laylâ:BAAALgAECgEJAQAAAA==.',
Le='Lelink:BAABLgAECn8YAAIPAAkJmRPGMQAkAgAPAAkJmRPGMQAkAgAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leniuum:BAAALgADCgMJBgABLgAFFAQJEgABACIPAA==.Leoden:BAAALgADCgUJBAAAAA==.Leopard:BAAALgAECgkJBwAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAABLgAECn8WAAIfAAUJvApLRQDgAAAfAAUJvApLRQDgAAABLgAECgYJCQAMAAAAAA==.Lightlana:BAACLgAFFH8TAAIEAAUJXRSUOAAjAQAEAAUJXRSUOAAjAQAuAAQKfyUAAgQACAm5IdAYANQCAAQACAm5IdAYANQCAAAA.Lightwalker:BAAALgAECgUJBQAAAA==.Likeaglove:BAAALgAECggJEQABLgAFFAUJCwAdAPoJAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8pAAMeAAkJHx7XCwDmAgAeAAkJHx7XCwDmAgAJAAMJ5QpMbgCKAAAAAA==.Lizzieag:BAECLgAFFH8MAAIYAAQJZxPeFwA8AQAYAAQJZxPeFwA8AQAuAAQKfzgAAhgACQlqGS8RAFoCABgACQlqGS8RAFoCAAAA.',
Ll='Llemons:BAAALgAECgEJAgABLgAFFAQJDQAOAPMPAA==.Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loafsies:BAAALgADCgMJAwAAAA==.Loakai:BAAALgAECgEJAQAAAA==.Lockman:BAAALgADCgMJBAAAAA==.Lockndotz:BAAALgAECgcJEgABLgAECgQJBQAMAAAAAA==.Loenil:BAABLgAECn8mAAIEAAgJywxmkgAzAQAEAAgJywxmkgAzAQAAAA==.Lohueng:BAAALgAECgYJEwAAAA==.Lolhigh:BAAALgAECgEJAQAAAA==.Loodah:BAAALgAECggJCgAAAA==.Lookee:BAABLgAECn8aAAIOAAYJeBQFlQAzAQAOAAYJeBQFlQAzAQAAAA==.Loranoth:BAAALgADCggJDwAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.Lovecox:BAAALgAECgEJAgAAAA==.',
Lu='Lucielle:BAAALgAECgYJCwAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn89AAIUAAkJziJJBABrAwAUAAkJziJJBABrAwAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAcJGgABAMcPAA==.Lustarhymes:BAAALgAECgUJBQAAAA==.',
Ly='Lyxon:BAABLgAECn8mAAMUAAgJexcZHwA6AgAUAAgJexcZHwA6AgAZAAEJbwxEhQArAAAAAA==.',
['Lå']='Låw:BAAALgAECgIJBAAAAA==.',
Ma='Maandos:BAAALgADCgcJBwAAAA==.Mabrian:BAAALgADCgcJBwAAAA==.Mael:BAAALgADCgUJBQAAAA==.Mafoôza:BAABLgAECn8uAAIYAAkJOiIkCQC8AgAYAAkJOiIkCQC8AgAAAA==.Magicalama:BAAALgADCgYJCwABLgAFFAUJEwAIAHkZAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgIJAgABLgAECggJHAABAHEXAA==.Magpen:BAAALgADCgMJBgAAAA==.Magtark:BAAALgAECgEJAQAAAA==.Mahboyblu:BAAALgAECgMJAwAAAA==.Mahndoo:BAACLgAFFH8NAAIOAAQJ8w8qUgAtAQAOAAQJ8w8qUgAtAQAuAAQKfyAAAg4ACAmRGo5JAOcBAA4ACAmRGo5JAOcBAAAA.Makto:BAAALgADCgUJCAAAAA==.Malia:BAAALgAECgcJCQAAAA==.Maliciouso:BAABLgAECn8rAAIeAAkJLBtOEAC2AgAeAAkJLBtOEAC2AgAAAA==.Malindas:BAAALgADCgUJBQAAAA==.Malédiction:BAABLgAECn8bAAIOAAgJ6RXXdwDiAQAOAAgJ6RXXdwDiAQAAAA==.Mattdemøn:BAAALgAECgMJAwABLgAECggJLAABAEIfAA==.Matua:BAAALgAECgMJBAAAAA==.Maymae:BAABLgAECn8WAAIeAAYJwgtHZAAPAQAeAAYJwgtHZAAPAQAAAA==.',
Me='Medizine:BAAALgAECgEJBAAAAA==.Medon:BAAALgADCgYJBgAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megabonk:BAAALgAECgQJBQABLgAECggJKQAYAH0cAA==.Megademac:BAABLgAECn8fAAIHAAcJIA5LegAQAQAHAAcJIA5LegAQAQAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.Merquise:BAAALgAECgUJBQAAAA==.Metus:BAAALgADCgkJCQAAAA==.',
Mi='Miistral:BAABLgAECn8kAAIEAAkJHhevRQDdAQAEAAkJHhevRQDdAQAAAA==.Mimmz:BAAALgAECgEJAQAAAA==.Miniblinks:BAAALgADCgQJAwAAAA==.Minisid:BAABLgAFFH8KAAIOAAMJwgv9dADYAAAOAAMJwgv9dADYAAABLgAFFAcJJwAYAIMcAA==.Miriia:BAAALgAECgIJAwAAAA==.Mirshta:BAAALgADCggJEQAAAA==.Missmaam:BAABLgAECn8hAAIcAAcJqyCrBwDrAQAcAAcJqyCrBwDrAQABLgAFFAQJBgAgAPEOAA==.Mistinmae:BAAALgAECgEJAgABLgAECgcJKQAeAOUTAA==.Mistrjenkins:BAAALgAECgYJDQAAAA==.Mistyeva:BAAALgAECgUJBQABLgAECgkJPQAUAM4iAA==.Mixoz:BAAALgAECgQJBAAAAA==.Miyoko:BAAALgAECgUJBQAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQAMAAAAAA==.Mokotrize:BAABLgAECn83AAIGAAkJHRk0CAA7AgAGAAkJHRk0CAA7AgAAAA==.Momtok:BAAALgAECgUJBwAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAACLgAFFH8MAAIZAAUJRxGpHgACAQAZAAUJRxGpHgACAQAuAAQKfykAAhkACAlhHGwQAJ0CABkACAlhHGwQAJ0CAAAA.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECggJLAABAEIfAA==.Mordred:BAABLgAECn8dAAIcAAYJ2geTGgCtAAAcAAYJ2geTGgCtAAAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCQABLgAECgcJGAAaACkbAA==.',
Mu='Mud:BAAALgAECgUJBwAAAA==.Munchies:BAAALgAECgYJCgAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQABLgAECggJGgAWAE8WAA==.Myrolee:BAABLgAECn8aAAQWAAgJTxblHACsAQAWAAgJXhTlHACsAQAgAAgJkgzIOgBTAQAlAAQJPhHJUgCnAAAAAA==.Myrowrynn:BAAALgAECgYJCQABLgAECggJGgAWAE8WAA==.Myrozond:BAAALgAECgYJDwABLgAECggJGgAWAE8WAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAAEAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIEAAcJZyNNGQDRAgAEAAcJZyNNGQDRAgAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAABLgAECn80AAIlAAkJaiVcAgA8AwAlAAkJaiVcAgA8AwAAAA==.Narset:BAAALgADCgYJCwAAAA==.Nattum:BAAALgADCgYJBwAAAA==.Nayasylpha:BAABLgAECn8sAAIWAAgJxhzxDwCdAgAWAAgJxhzxDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Nemophilist:BAAALgAECgQJBAAAAA==.Neown:BAABLgAECn8YAAIOAAYJ7BJunAAmAQAOAAYJ7BJunAAmAQABLgAECggJKgAUAEgeAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAABLgAECn8uAAIOAAkJMSHUIQCBAgAOAAkJMSHUIQCBAgAAAA==.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAABLgAECn8bAAIdAAYJ6Qp+OwDwAAAdAAYJ6Qp+OwDwAAAAAA==.Nightknigh:BAAALgAECgEJAgAAAA==.Nirri:BAAALgAECgcJCAAAAA==.Nishendra:BAABLgAECn8aAAITAAkJix3+BgDQAgATAAkJix3+BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAABLgAECn8gAAMBAAgJuQ2sXgBxAQABAAgJuQ2sXgBxAQAIAAYJkglKMQAPAQAAAA==.Nitezilla:BAAALgAECgQJBQAAAA==.',
No='Noblok:BAAALgAECgQJBQAAAA==.Nocando:BAACLgAFFH8LAAIdAAUJ+gmPEQAcAQAdAAUJ+gmPEQAcAQAuAAQKfxgAAh0ACQkLGIsQAEsCAB0ACQkLGIsQAEsCAAAA.Nofeetpicsyo:BAABLgAECn82AAIbAAgJewzqLQBJAQAbAAgJewzqLQBJAQAAAA==.Noni:BAAALgADCgEJAQAAAA==.Nootella:BAABLgAECn8UAAIKAAYJlSIoHgAlAgAKAAYJlSIoHgAlAgABLgAECgkJGwAiAIsXAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAABLgAECn8qAAQGAAcJnyClCwD0AQAGAAcJLhylCwD0AQAEAAYJySDnVQCwAQAKAAIJnRsmXgChAAAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8dAAIbAAgJGBoMGwAGAgAbAAgJGBoMGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAFFAQJDAAVAE0TAA==.Nylinuya:BAAALgAECgYJEwABLgAFFAQJDAAVAE0TAA==.Nyteskye:BAAALgAECgEJAgAAAA==.Nyxoblivion:BAAALgADCgcJEQAAAA==.',
['Nî']='Nîco:BAABLgAECn8qAAIUAAgJSB7wGABwAgAUAAgJSB7wGABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAACLgAFFH8OAAIWAAQJlw3ZJAAEAQAWAAQJlw3ZJAAEAQAuAAQKfyAAAxYACAlbD/QpAFMBABYACAkID/QpAFMBACUAAQlYFct4ADkAAAAA.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAACLgAFFH8NAAIDAAUJSRk1NwBIAQADAAUJSRk1NwBIAQAuAAQKfzMAAgMACQnQFncvAA4CAAMACQnQFncvAA4CAAAA.Ollphéist:BAAALgAECgYJBgAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECgkJOQATAJsYAA==.',
On='Oneall:BAABLgAECn8zAAIZAAgJmxXdHgC3AQAZAAgJmxXdHgC3AQAAAA==.Onehit:BAAALgAECgMJBQAAAA==.Onlyspells:BAABLgAECn8WAAMOAAgJaAm2pwCKAQAOAAgJaAm2pwCKAQANAAEJnAELEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8lAAIQAAkJJRgFFQCrAQAQAAkJJRgFFQCrAQAAAA==.',
Or='Orchideva:BAAALgADCgEJAQABLgAECgkJPQAUAM4iAA==.Orelikai:BAAALgADCgQJBAAAAA==.Oreoz:BAAALgADCgUJBQAAAA==.',
Ot='Othin:BAABLgAECn8ZAAIUAAgJKRslGgBhAgAUAAgJKRslGgBhAgAAAA==.Ottoshock:BAAALgAECgEJAQAAAA==.',
Pa='Painloa:BAABLgAECn8eAAMmAAgJpApeEgAjAQAmAAgJpApeEgAjAQAPAAYJZwFg7wCfAAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8cAAIiAAkJ8Q7fHACuAQAiAAkJ8Q7fHACuAQAAAA==.Pandadance:BAAALgAECgcJEwAAAA==.Pandakill:BAAALgAECgUJBgAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandaxi:BAAALgAECgIJAgABLgAECggJIgAEAB0hAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAwAAAA==.Papachungus:BAAALgADCgYJCQAAAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJEAAMAAAAAA==.Papagenu:BAAALgAECgYJCQABLgAECgYJEAAMAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8tAAIOAAkJLyOFEgDXAgAOAAkJLyOFEgDXAgAAAA==.Pazzie:BAAALgAECgMJCAAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.Phreyja:BAAALgAECgEJAQAAAA==.',
Pm='Pmac:BAABLgAECn8VAAIOAAUJWxB/wQDpAAAOAAUJWxB/wQDpAAABLgAECgcJHwAHACAOAA==.',
Po='Poggie:BAAALgAECgQJBgAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potox:BAAALgAECgIJAgAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Power:BAAALgAECgUJBwAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Primerecall:BAAALgAECgkJAgAAAA==.Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgAECgcJCwAAAA==.',
Pu='Punishment:BAAALgAECgUJBwAAAA==.Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAABLgAECn80AAMaAAkJACHxAADxAgAaAAkJACHxAADxAgADAAMJTA4a0wCdAAAAAA==.',
Qa='Qai:BAABLgAECn8iAAMFAAgJkg+aFwBEAQAFAAUJ7BaaFwBEAQALAAgJNgf8NwCeAAAAAA==.',
Qu='Quan:BAAALgAECgIJBwAAAA==.Quelestraza:BAABLgAECn8dAAMTAAgJSBaWDAD5AQATAAgJSBaWDAD5AQARAAEJjgXliAApAAAAAA==.',
Ra='Raewyck:BAABLgAECn89AAIBAAgJpBa8LQD8AQABAAgJpBa8LQD8AQAAAA==.Ragar:BAAALgAECgUJBQABLgAFFAMJDQAYAHslAA==.Raginbull:BAABLgAECn8pAAIkAAgJ8xqUDAAMAgAkAAgJ8xqUDAAMAgAAAA==.Raginganja:BAAALgADCgMJBgAAAA==.Ragingmaze:BAABLgAECn8hAAMPAAkJ+A73VACyAQAPAAkJYwz3VACyAQAQAAEJpx9MRwBXAAAAAA==.Rainburrow:BAAALgAECggJEwAAAA==.Raptormortis:BAABLgAECn8nAAMJAAkJpRpYEQBQAgAJAAkJpRpYEQBQAgAeAAYJ5BM8UABTAQAAAA==.Rawd:BAAALgADCgIJAgAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgAMAAAAAA==.Raylen:BAAALgAECgYJBgAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgAMAAAAAA==.Reinitia:BAAALgAECgUJCQAAAA==.Reinny:BAABLgAECn8VAAIUAAgJ8Al4VQAnAQAUAAgJ8Al4VQAnAQAAAA==.Rellic:BAAALgAECgMJBAAAAA==.Remy:BAABLgAECn8UAAIEAAcJBB9bOQAEAgAEAAcJBB9bOQAEAgAAAA==.Renkagisa:BAAALgAECgYJCQAAAA==.Renku:BAAALgAECgQJEgAAAA==.Retana:BAAALgAECgQJCAAAAA==.Retrisan:BAAALgAECgUJBQAAAA==.',
Rh='Rhinn:BAABLgAECn8dAAIjAAgJyQv5EwBYAQAjAAgJyQv5EwBYAQAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAABLgAECn8UAAIEAAcJCCA+MAAmAgAEAAcJCCA+MAAmAgAAAA==.Ritsuri:BAAALgAECgIJAgABLgAECgMJBAAMAAAAAA==.Ritsuyi:BAAALgAECgEJAQABLgAECgMJBAAMAAAAAA==.Ritualbeef:BAAALgADCgYJCAABLgAECgkJDAAMAAAAAA==.Riven:BAAALgAECggJDgAAAA==.',
Ro='Roarbear:BAABLgAECn8gAAIYAAkJIhnPEQBTAgAYAAkJIhnPEQBTAgAAAA==.Roastedz:BAABLgAECn8uAAIaAAgJfA6aDQBHAQAaAAgJfA6aDQBHAQAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roodeekay:BAAALgAECgQJCAABLgAECggJMQASAK4fAA==.Roomi:BAABLgAECn85AAIjAAkJ4Bu6BQBuAgAjAAkJ4Bu6BQBuAgAAAA==.Roowar:BAAALgAECgcJEwABLgAECggJMQASAK4fAA==.Rorié:BAAALgADCggJDAAAAA==.Rorthu:BAAALgAECgYJBgAAAA==.Roru:BAABLgAECn8qAAMDAAkJRxreGgB1AgADAAkJRxreGgB1AgAaAAMJSwWZVABwAAAAAA==.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgAECgYJBgAAAA==.Ruxman:BAAALgAECgEJAwAAAA==.',
Ry='Ry:BAABLgAECn8VAAIDAAUJcB9PegBnAQADAAUJcB9PegBnAQAAAA==.Ryanna:BAAALgAECgYJCwAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgcJDAAAAA==.',
['Ræ']='Rædiêncë:BAABLgAECn8cAAIEAAkJEwZAlQAuAQAEAAkJEwZAlQAuAQAAAA==.',
['Rò']='Ròó:BAABLgAECn8xAAQSAAgJrh/rCAACAwASAAgJrh/rCAACAwAnAAMJLR5+FAC1AAAoAAIJiSOBGgBdAAAAAA==.',
Sa='Saevio:BAABLgAECn8pAAMPAAgJVxyxOAAJAgAPAAgJVxyxOAAJAgAQAAUJjw7kKgDoAAAAAA==.Sajin:BAAALgADCgcJDQAAAA==.Salazandur:BAAALgAECgEJAQABLgAECgkJHQAcAA0WAA==.Sallean:BAAALgAECgEJAQAAAA==.Salvader:BAAALgAECgcJCgAAAA==.Sanctus:BAAALgAECgYJDgAAAA==.Sanlorastik:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwAMAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAACLgAFFH8LAAMPAAMJ+BXbbwD/AAAPAAMJ+BXbbwD/AAAmAAEJ2Q03HABNAAAuAAQKfykAAw8ACAmBG1hCADACAA8ACAmBG1hCADACACYABglhEbQTABMBAAAA.Saso:BAAALgAECgYJCAAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAIKAAMJ/hULDgD3AAAKAAMJ/hULDgD3AAAuAAQKfxcAAgoACAnGJWMEACcDAAoACAnGJWMEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJBAAAAA==.Scoot:BAEALgAFFAIJAwABLgAFFAYJEwAdAPodAA==.Scotchnsoda:BAACLgAFFH8WAAMdAAQJCRDFFQDvAAAdAAQJCRDFFQDvAAAiAAEJJgMHQwA2AAAuAAQKfy4ABB0ACQnuE3spAKYBAB0ACQnfE3spAKYBACIABgnCE4AoAGkBABsAAQlyANFrABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgAECgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgUJDwAAAA==.Selenegosa:BAABLgAECn8fAAMhAAgJnBVCDAA7AQAhAAYJGBdCDAA7AQARAAYJNBBDSgDeAAABLgAFFAMJBwAIAN0eAA==.Seran:BAABLgAECn8kAAIBAAkJbSAiDQDVAgABAAkJbSAiDQDVAgAAAA==.Serenade:BAABLgAECn85AAIZAAkJmxLDGwDSAQAZAAkJmxLDGwDSAQAAAA==.Severyne:BAABLgAECn8oAAIUAAgJIiUUBQA8AwAUAAgJIiUUBQA8AwABLgAFFAYJCgAgALYfAA==.',
Sh='Shadowchad:BAAALgADCgUJCAAAAA==.Shadowmeld:BAAALgAECgcJEAAAAA==.Shadowpump:BAAALgAECgYJDAAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgAECgIJAgAAAA==.Shallanaera:BAAALgAECgYJBgAAAA==.Shamanco:BAAALgAECgYJBwAAAA==.Shamanu:BAAALgAECgcJEQABLgAECgcJGAAEAGcjAA==.Shamsel:BAABLgAECn81AAIbAAgJgg8KKABuAQAbAAgJgg8KKABuAQAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8ZAAILAAYJ5hW2BQBzAQALAAYJ5hW2BQBzAQAuAAQKfygAAgsACQn2IEICABEDAAsACQn2IEICABEDAAAA.Shikes:BAABLgAFFH8KAAIOAAQJjgydVwAkAQAOAAQJjgydVwAkAQAAAA==.Shinpaku:BAAALgADCgIJAgAAAA==.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJDAAAAA==.Shorin:BAAALgADCgYJCwAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAACLgAFFH8GAAIUAAMJtSBAJAAfAQAUAAMJtSBAJAAfAQAuAAQKfzMAAxQACQmZIwQEAFADABQACAliJQQEAFADABkAAQn1Cnx3AEEAAAAA.Shweatyballs:BAABLgAECn8XAAIOAAYJahtGjQC4AQAOAAYJahtGjQC4AQAAAA==.Shóki:BAAALgAECggJDgAAAA==.',
Si='Sidetrax:BAAALgADCgQJBAAAAA==.Silran:BAABLgAECn8XAAIEAAgJCwzPswD9AAAEAAgJCwzPswD9AAAAAA==.Silverwings:BAAALgADCgEJAQAAAA==.Simmara:BAACLgAFFH8GAAIBAAQJLQ0xNgAoAQABAAQJLQ0xNgAoAQAuAAQKfyEAAwEACQkrEak9ANIBAAEACQkrEak9ANIBAAgABAmCBIYkAKYAAAAA.Sinistar:BAAALgAECgEJAQAAAA==.Sinner:BAECLgAFFH8TAAIdAAYJ+h2XAwAKAgAdAAYJ+h2XAwAKAgAuAAQKfxoAAx0ACQkXHdIHAM4CAB0ACQkXHdIHAM4CABsAAwnuAxNZAFcAAAAA.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAgJJAAkAPQkAA==.Skoala:BAAALgAECgcJDAAAAA==.Skruff:BAAALgAECgIJAwAAAA==.Skywalkah:BAAALgADCgIJAgABLgAECgcJCwAMAAAAAA==.',
Sl='Slamuraijack:BAAALgAECgcJBwAAAA==.Slayngin:BAAALgAECgQJCQABLgAECgUJCAAMAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAFFAMJAwAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAABLgADCgYJBgAMAAAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgMJAwAAAA==.Solweaver:BAAALgADCgIJAgAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAABLgAECn8hAAIGAAgJ5hYhDwC2AQAGAAgJ5hYhDwC2AQAAAA==.',
Sq='Squirrely:BAAALgADCgIJAgABLgAECggJLAABAEIfAA==.Squirrt:BAAALgAECgUJBQAAAA==.Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAABLgAECn8iAAIQAAgJ/gTvLgDNAAAQAAgJ/gTvLgDNAAAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Stonystark:BAAALgAECgEJBAAAAA==.Straam:BAACLgAFFH8VAAIeAAQJaR3NHABaAQAeAAQJaR3NHABaAQAuAAQKf0UAAh4ACQmIIlMGADcDAB4ACQmIIlMGADcDAAAA.Stumpe:BAAALgAECgIJAwAAAA==.Stupidity:BAAALgAECgYJBgAAAA==.Støney:BAABLgAECn87AAIOAAkJ7BHLSQDmAQAOAAkJ7BHLSQDmAQAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAgJJAAkAPQkAA==.Subroutine:BAABLgAECn8WAAICAAgJHh/4DgDKAgACAAgJHh/4DgDKAgABLgAFFAgJJAAkAPQkAA==.Subtractive:BAACLgAFFH8kAAIkAAgJ9CRuAADpAgAkAAgJ9CRuAADpAgAuAAQKfxsAAiQACAmmJiQBAIYDACQACAmmJiQBAIYDAAAA.Superiorha:BAABLgAECn8cAAIlAAkJMR8tBgDYAgAlAAkJMR8tBgDYAgAAAA==.',
Sw='Swagchamp:BAAALgADCgQJBQABLgAECgcJCwAMAAAAAA==.Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIOAAIJ2SHQMwDKAAAOAAIJ2SHQMwDKAAAuAAQKfyIAAg4ACQk5I7oFAKcDAA4ACQk5I7oFAKcDAAAA.',
Sy='Sylthara:BAABLgAECn8mAAMeAAcJYhR8PgCXAQAeAAcJYhR8PgCXAQAjAAEJXQMSOwAkAAAAAA==.Syrellis:BAAALgAECgEJAgAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8xAAIcAAkJchVJBwD2AQAcAAkJchVJBwD2AQAAAA==.Tahle:BAAALgAECgIJAgAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAABLgAECn8iAAIOAAcJPRhfWwCzAQAOAAcJPRhfWwCzAQAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tater:BAAALgADCgcJBwAAAA==.Tatonka:BAAALgADCgYJAwAAAA==.Tavin:BAAALgAECgUJBQAAAA==.Tazchem:BAAALgAECgQJBQAAAA==.',
Te='Techboar:BAAALgAECgEJAQAAAA==.Teinuya:BAACLgAFFH8MAAMVAAQJTROxAwA/AQAVAAQJMhOxAwA/AQADAAIJMAssmgCBAAAuAAQKfz0ABBUACQn6IPwAAPoCABUACQl/IPwAAPoCABoABgkSHQUMAAICAAMABAkCF2ieAPcAAAAA.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Temparia:BAAALgAECgYJBgAAAA==.Tenderfiddle:BAAALgAECgYJEwAAAA==.Tenochitilan:BAAALgAECggJDQAAAA==.Tenuous:BAABLgAECn8ZAAMZAAgJzBliFgAFAgAZAAgJzBliFgAFAgAUAAQJ6Qb9kgB6AAAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAFFAMJBgAUALUgAA==.Thanar:BAAALgADCgEJAQAAAA==.Thevelo:BAAALgADCgcJBwABLgAECgcJEwAMAAAAAA==.Thisistheway:BAACLgAFFH8JAAIkAAMJ0hQ4GAC/AAAkAAMJ0hQ4GAC/AAAuAAQKfy0AAiQACQnjHGEHAHcCACQACQnjHGEHAHcCAAEuAAUUBAkVABMAmBsA.Thoorz:BAAALgAECgMJBAAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAABLgAECn8XAAMBAAYJfxjJbABQAQABAAYJvhfJbABQAQACAAYJ0QqmVAD4AAABLgAECgMJBAAMAAAAAA==.Thothh:BAABLgAECn8aAAQiAAYJ1A2LMwAlAQAiAAYJWg2LMwAlAQAbAAQJagvtVwCIAAAdAAIJXQ+1bAB3AAAAAA==.Thraxacious:BAACLgAFFH8QAAIFAAQJKRuDBABQAQAFAAQJKRuDBABQAQAuAAQKfyEAAgUACQnTGMQJAAcCAAUACQnTGMQJAAcCAAAA.Thulcandra:BAABLgAECn8UAAIOAAYJxB/fYwARAgAOAAYJxB/fYwARAgAAAA==.Thulsadoomm:BAABLgAECn8lAAIQAAcJ4x0KEQDhAQAQAAcJ4x0KEQDhAQAAAA==.Thundermay:BAABLgAECn8pAAIeAAcJ5RNSPAChAQAeAAcJ5RNSPAChAQAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAABLgAECn8sAAIkAAYJ5w1vJwDeAAAkAAYJ5w1vJwDeAAAAAA==.Tigó:BAABLgAECn8oAAIEAAkJjSCwEADMAgAEAAkJjSCwEADMAgAAAA==.Tigölebittie:BAABLgAECn8qAAMUAAkJTBIpKgDxAQAUAAkJTBIpKgDxAQAZAAQJcw9NXQCDAAAAAA==.Tiifa:BAAALgADCgIJAQAAAA==.Tinkerrbella:BAABLgAECn8WAAQBAAcJvQ3yUwBsAQABAAcJvQ3yUwBsAQACAAUJFgIZbQCKAAAIAAIJsgFHUwBEAAABLgAFFAcJGgABAMcPAA==.Tireliaa:BAAALgAECgUJCAAAAA==.Tizzymami:BAAALgADCgQJBAAAAA==.',
Tj='Tjnewt:BAAALgADCgkJCQAAAA==.',
To='Toatsie:BAABLgAECn8VAAIEAAgJJBebUAC+AQAEAAgJJBebUAC+AQAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Tribulationz:BAAALgAECgQJBAABLgAECggJMQAJAAQhAA==.Trumpybear:BAABLgAECn8iAAIEAAgJHSH3HACAAgAEAAgJHSH3HACAAgAAAA==.',
Ts='Tsun:BAABLgAECn85AAMXAAkJNR3pBgB2AgAXAAkJsRzpBgB2AgAkAAkJbxKJDwDXAQAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgcJCgABLgAECgcJGAAEAGcjAA==.',
Ud='Uddertrouble:BAEBLgAECn8cAAIBAAgJcRe6QgDCAQABAAgJcRe6QgDCAQAAAA==.',
Uf='Ufos:BAAALgADCggJHgAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAOANkhAA==.',
Ul='Ulfgrim:BAAALgADCggJEwAAAA==.',
Un='Uncletat:BAABLgAECn9AAAQdAAkJuyTkAQCGAwAdAAkJuyTkAQCGAwAiAAYJmCFWDwBJAgAbAAEJHRSPcgA4AAAAAA==.',
Ur='Urmada:BAABLgAECn80AAIOAAkJfw99VADHAQAOAAkJfw99VADHAQAAAA==.Urmami:BAABLgAECn8wAAIDAAkJ+hPJMQAEAgADAAkJ+hPJMQAEAgAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Uz='Uzui:BAAALgAECgcJDgAAAA==.',
Va='Vael:BAAALgAECgMJAwAAAA==.Vahnt:BAABLgAECn8yAAIeAAgJGxh1IAAcAgAeAAgJGxh1IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8rAAIEAAkJLh6CJgCMAgAEAAkJLh6CJgCMAgAAAA==.Vampire:BAABLgAECn8VAAIHAAkJ6hpCGABvAgAHAAkJ6hpCGABvAgAAAA==.Vampyre:BAACLgAFFH8cAAIQAAgJexU1CAC9AQAQAAgJexU1CAC9AQAuAAQKfx4AAhAACQnFIfoCADMDABAACQnFIfoCADMDAAAA.Vanadie:BAAALgAECgYJBgAAAA==.Vanta:BAAALgADCgcJDQAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJBAAAAA==.Vendettá:BAABLgAECn8VAAIeAAYJzhg5UgBLAQAeAAYJzhg5UgBLAQAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgAECgQJBAAAAA==.',
Vi='Vidi:BAAALgAECgUJBQAAAA==.Virala:BAAALgAFFAEJAQAAAA==.Visenya:BAAALgAECgUJEQAAAA==.Vishontey:BAAALgAECgQJBQAAAA==.Vitaminn:BAABLgAECn8zAAQEAAkJPR43GACcAgAEAAkJPR43GACcAgAKAAIJTwZkigBUAAAGAAEJnBf7PgBCAAAAAA==.Vithiris:BAAALgADCgYJBgAAAA==.',
Vk='Vk:BAAALgAECgkJEwAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAwAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECgkJDgAAAA==.Vynnigosa:BAAALgAECggJCAAAAA==.Vynora:BAAALgAECgkJCwAAAA==.Vyrse:BAAALgAFFAQJBAAAAA==.',
Wa='Wafflez:BAAALgAECgcJBwAAAA==.Walterlight:BAAALgAECgEJAQAAAA==.Wampa:BAAALgAECgYJCAAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wasabii:BAAALgAFFAMJBAAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgQJCAAAAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8NAAIYAAMJeyWjHQAnAQAYAAMJeyWjHQAnAQAuAAQKfzoAAxcACQkeJb4EALICABgABwmvJZkNAOkCABcACQmZI74EALICAAAA.Windente:BAABLgAECn8mAAMBAAkJ5RWIRAC8AQABAAgJJRaIRAC8AQACAAQJ7ApiJwBoAAAAAA==.Wing:BAEBLgAFFH8HAAIEAAMJiyC1PgAXAQAEAAMJiyC1PgAXAQABLgAFFAYJEwAdAPodAA==.Wiseau:BAABLgAECn8sAAMBAAgJQh/XGAB7AgABAAgJQh/XGAB7AgACAAEJ4wMElAAmAAAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgYJDAAAAA==.',
Wu='Wulfhound:BAABLgAECn8VAAIBAAgJjRZ5OgDeAQABAAgJjRZ5OgDeAQAAAA==.Wulfnbolt:BAAALgAECgEJAQAAAA==.Wulfsblood:BAAALgADCgQJBAABLgAECggJFQABAI0WAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECggJHgAAAQ==.',
Xe='Xexhu:BAAALgAECgcJBwAAAA==.',
Xp='Xpand:BAAALgAECgEJAQAAAA==.',
Xu='Xuen:BAABLgAECn8WAAIlAAgJIQ5QKQBWAQAlAAgJIQ5QKQBWAQAAAA==.',
Ya='Yazbrez:BAAALgADCgEJAQABLgAECgYJEAAMAAAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zackattack:BAAALgAFFAIJAwAAAA==.Zaeluna:BAABLgAECn8zAAILAAgJZiB1AwDWAgALAAgJZiB1AwDWAgAAAA==.Zanikan:BAAALgAECgkJAgAAAA==.Zanzer:BAAALgAECgUJEAAAAA==.Zathara:BAABLgAECn8gAAIFAAkJWxWnCQAKAgAFAAkJWxWnCQAKAgAAAA==.',
Ze='Zechs:BAAALgAECgYJBwAAAA==.Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zeroshot:BAAALgAECgEJBQAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.Zeyleian:BAAALgAECgUJBQAAAA==.',
Zo='Zorvax:BAAALgAECgUJCwAAAA==.',
Zp='Zpazzie:BAAALgAECgQJCQAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgAECgEJAQAAAA==.',
['Zö']='Zörö:BAABLgAECn8dAAIPAAkJdRtqIAB0AgAPAAkJdRtqIAB0AgAAAA==.',
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
